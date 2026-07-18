import 'package:flutter/services.dart';

abstract final class WindowsWindowChrome {
  static const MethodChannel _channel = MethodChannel('app.yomu/window');

  static Future<void> startDrag() => _channel.invokeMethod<void>('startDrag');

  static Future<void> startResize(String edge) =>
      _channel.invokeMethod<void>('startResize', edge);

  static Future<void> minimize() => _channel.invokeMethod<void>('minimize');

  static Future<void> toggleMaximize() =>
      _channel.invokeMethod<void>('toggleMaximize');

  static Future<void> close() => _channel.invokeMethod<void>('close');
}
