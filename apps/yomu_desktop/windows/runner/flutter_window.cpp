#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

std::optional<WPARAM> ResizeCommandForEdge(
    const flutter::EncodableValue* argument) {
  const auto edge = std::get_if<std::string>(argument);
  if (edge == nullptr) {
    return std::nullopt;
  }
  if (*edge == "left") {
    return WMSZ_LEFT;
  }
  if (*edge == "right") {
    return WMSZ_RIGHT;
  }
  if (*edge == "top") {
    return WMSZ_TOP;
  }
  if (*edge == "topLeft") {
    return WMSZ_TOPLEFT;
  }
  if (*edge == "topRight") {
    return WMSZ_TOPRIGHT;
  }
  if (*edge == "bottom") {
    return WMSZ_BOTTOM;
  }
  if (*edge == "bottomLeft") {
    return WMSZ_BOTTOMLEFT;
  }
  if (*edge == "bottomRight") {
    return WMSZ_BOTTOMRIGHT;
  }
  return std::nullopt;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "app.yomu/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<
                 flutter::MethodResult<flutter::EncodableValue>> result) {
        const HWND window = GetHandle();
        if (window == nullptr) {
          result->Error("window_unavailable", "The Yomu window is unavailable.");
          return;
        }

        if (call.method_name() == "startDrag") {
          POINT cursor{};
          GetCursorPos(&cursor);
          ReleaseCapture();
          PostMessage(window, WM_NCLBUTTONDOWN, HTCAPTION,
                      MAKELPARAM(cursor.x, cursor.y));
          result->Success();
          return;
        }
        if (call.method_name() == "startResize") {
          const std::optional<WPARAM> resize_command =
              ResizeCommandForEdge(call.arguments());
          if (!resize_command.has_value()) {
            result->Error("invalid_resize_edge",
                          "The requested resize edge is invalid.");
            return;
          }
          if (!IsZoomed(window)) {
            ReleaseCapture();
            PostMessage(window, WM_SYSCOMMAND,
                        SC_SIZE | resize_command.value(), 0);
          }
          result->Success();
          return;
        }
        if (call.method_name() == "minimize") {
          ShowWindow(window, SW_MINIMIZE);
          result->Success();
          return;
        }
        if (call.method_name() == "toggleMaximize") {
          ShowWindow(window, IsZoomed(window) ? SW_RESTORE : SW_MAXIMIZE);
          result->Success();
          return;
        }
        if (call.method_name() == "close") {
          PostMessage(window, WM_CLOSE, 0, 0);
          result->Success();
          return;
        }

        result->NotImplemented();
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  window_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
