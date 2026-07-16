import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'maya_credential_store.dart';

const int _credTypeGeneric = 1;
const int _credPersistLocalMachine = 2;
const int _errorFileNotFound = 2;
const int _errorNotFound = 1168;
const int _heapZeroMemory = 0x00000008;

/// Windows Credential Manager-backed API-key storage for the native desktop.
///
/// Credential blobs are stored as UTF-8 under a deterministic generic target.
/// Native input/output buffers are overwritten before release where their size
/// is known. Dart strings cannot be reliably wiped by the managed runtime, so
/// callers should avoid retaining returned keys longer than one request.
final class WindowsMayaCredentialStore implements MayaCredentialStore {
  WindowsMayaCredentialStore() : _bindings = _WinCredentialBindings.load();

  final _WinCredentialBindings _bindings;

  static bool get isSupported => Platform.isWindows && sizeOf<IntPtr>() == 8;

  @override
  Future<void> save({
    required String providerId,
    required String apiKey,
  }) async {
    final target = mayaCredentialTargetForProvider(providerId);
    validateMayaApiKey(apiKey);

    List<int> secretBytes;
    try {
      secretBytes = utf8.encode(apiKey);
    } catch (_) {
      throw const MayaCredentialStoreException(
        MayaCredentialStoreErrorCode.invalidApiKey,
      );
    }

    final arena = _NativeHeapArena(_bindings);
    try {
      final targetPointer = arena.utf16(target);
      final userPointer = arena.utf16(providerId);
      final blobPointer = arena.bytes(secretBytes.length);
      blobPointer.asTypedList(secretBytes.length).setAll(0, secretBytes);

      final credential = arena.credential();
      credential.ref
        ..type = _credTypeGeneric
        ..targetName = targetPointer
        ..credentialBlobSize = secretBytes.length
        ..credentialBlob = blobPointer
        ..persist = _credPersistLocalMachine
        ..userName = userPointer;

      if (_bindings.credWrite(credential, 0) == 0) {
        throw const MayaCredentialStoreException(
          MayaCredentialStoreErrorCode.writeFailed,
        );
      }
    } on MayaCredentialStoreException {
      rethrow;
    } catch (_) {
      throw const MayaCredentialStoreException(
        MayaCredentialStoreErrorCode.writeFailed,
      );
    } finally {
      secretBytes.fillRange(0, secretBytes.length, 0);
      arena.dispose();
    }
  }

  @override
  Future<String?> read({required String providerId}) async {
    final target = mayaCredentialTargetForProvider(providerId);
    final arena = _NativeHeapArena(_bindings);
    Pointer<_CredentialW> nativeCredential = nullptr;
    Uint8List? copiedBytes;

    try {
      final targetPointer = arena.utf16(target);
      final output = arena.credentialOutput();
      if (_bindings.credRead(targetPointer, _credTypeGeneric, 0, output) == 0) {
        final error = _bindings.getLastError();
        if (_isNotFound(error)) return null;
        throw const MayaCredentialStoreException(
          MayaCredentialStoreErrorCode.readFailed,
        );
      }

      nativeCredential = output.value;
      if (nativeCredential == nullptr) {
        throw const MayaCredentialStoreException(
          MayaCredentialStoreErrorCode.corruptCredential,
        );
      }

      final native = nativeCredential.ref;
      final size = native.credentialBlobSize;
      final blob = native.credentialBlob;
      if (native.type != _credTypeGeneric ||
          size <= 0 ||
          size > kMayaCredentialMaxApiKeyBytes ||
          blob == nullptr) {
        throw const MayaCredentialStoreException(
          MayaCredentialStoreErrorCode.corruptCredential,
        );
      }

      copiedBytes = Uint8List.fromList(blob.asTypedList(size));
      try {
        final decoded = utf8.decode(copiedBytes, allowMalformed: false);
        validateMayaApiKey(decoded);
        return decoded;
      } catch (_) {
        throw const MayaCredentialStoreException(
          MayaCredentialStoreErrorCode.corruptCredential,
        );
      }
    } on MayaCredentialStoreException {
      rethrow;
    } catch (_) {
      throw const MayaCredentialStoreException(
        MayaCredentialStoreErrorCode.readFailed,
      );
    } finally {
      final bytes = copiedBytes;
      if (bytes != null) bytes.fillRange(0, bytes.length, 0);
      if (nativeCredential != nullptr) {
        final native = nativeCredential.ref;
        final size = native.credentialBlobSize;
        final blob = native.credentialBlob;
        if (blob != nullptr &&
            size > 0 &&
            size <= kMayaCredentialMaxApiKeyBytes) {
          blob.asTypedList(size).fillRange(0, size, 0);
        }
        _bindings.credFree(nativeCredential.cast<Void>());
      }
      arena.dispose();
    }
  }

  @override
  Future<void> delete({required String providerId}) async {
    final target = mayaCredentialTargetForProvider(providerId);
    final arena = _NativeHeapArena(_bindings);
    try {
      final targetPointer = arena.utf16(target);
      if (_bindings.credDelete(targetPointer, _credTypeGeneric, 0) == 0) {
        final error = _bindings.getLastError();
        if (_isNotFound(error)) return;
        throw const MayaCredentialStoreException(
          MayaCredentialStoreErrorCode.deleteFailed,
        );
      }
    } on MayaCredentialStoreException {
      rethrow;
    } catch (_) {
      throw const MayaCredentialStoreException(
        MayaCredentialStoreErrorCode.deleteFailed,
      );
    } finally {
      arena.dispose();
    }
  }

  static bool _isNotFound(int error) =>
      error == _errorNotFound || error == _errorFileNotFound;
}

final class _FileTime extends Struct {
  @Uint32()
  external int lowDateTime;

  @Uint32()
  external int highDateTime;
}

final class _CredentialW extends Struct {
  @Uint32()
  external int flags;

  @Uint32()
  external int type;

  external Pointer<Uint16> targetName;
  external Pointer<Uint16> comment;
  external _FileTime lastWritten;

  @Uint32()
  external int credentialBlobSize;

  external Pointer<Uint8> credentialBlob;

  @Uint32()
  external int persist;

  @Uint32()
  external int attributeCount;

  external Pointer<Void> attributes;
  external Pointer<Uint16> targetAlias;
  external Pointer<Uint16> userName;
}

typedef _CredWriteNative = Int32 Function(Pointer<_CredentialW>, Uint32);
typedef _CredWriteDart = int Function(Pointer<_CredentialW>, int);
typedef _CredReadNative =
    Int32 Function(
      Pointer<Uint16>,
      Uint32,
      Uint32,
      Pointer<Pointer<_CredentialW>>,
    );
typedef _CredReadDart =
    int Function(Pointer<Uint16>, int, int, Pointer<Pointer<_CredentialW>>);
typedef _CredDeleteNative = Int32 Function(Pointer<Uint16>, Uint32, Uint32);
typedef _CredDeleteDart = int Function(Pointer<Uint16>, int, int);
typedef _CredFreeNative = Void Function(Pointer<Void>);
typedef _CredFreeDart = void Function(Pointer<Void>);
typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastErrorDart = int Function();
typedef _GetProcessHeapNative = Pointer<Void> Function();
typedef _GetProcessHeapDart = Pointer<Void> Function();
typedef _HeapAllocNative =
    Pointer<Void> Function(Pointer<Void>, Uint32, IntPtr);
typedef _HeapAllocDart = Pointer<Void> Function(Pointer<Void>, int, int);
typedef _HeapFreeNative = Int32 Function(Pointer<Void>, Uint32, Pointer<Void>);
typedef _HeapFreeDart = int Function(Pointer<Void>, int, Pointer<Void>);

final class _WinCredentialBindings {
  _WinCredentialBindings({
    required this.credWrite,
    required this.credRead,
    required this.credDelete,
    required this.credFree,
    required this.getLastError,
    required this.heap,
    required this.heapAlloc,
    required this.heapFree,
  });

  factory _WinCredentialBindings.load() {
    if (!WindowsMayaCredentialStore.isSupported) {
      throw const MayaCredentialStoreException(
        MayaCredentialStoreErrorCode.unavailable,
      );
    }
    try {
      final advapi = DynamicLibrary.open('Advapi32.dll');
      final kernel = DynamicLibrary.open('Kernel32.dll');
      final getProcessHeap = kernel
          .lookupFunction<_GetProcessHeapNative, _GetProcessHeapDart>(
            'GetProcessHeap',
          );
      final heap = getProcessHeap();
      if (heap == nullptr) {
        throw const MayaCredentialStoreException(
          MayaCredentialStoreErrorCode.unavailable,
        );
      }
      return _WinCredentialBindings(
        credWrite: advapi.lookupFunction<_CredWriteNative, _CredWriteDart>(
          'CredWriteW',
        ),
        credRead: advapi.lookupFunction<_CredReadNative, _CredReadDart>(
          'CredReadW',
        ),
        credDelete: advapi.lookupFunction<_CredDeleteNative, _CredDeleteDart>(
          'CredDeleteW',
        ),
        credFree: advapi.lookupFunction<_CredFreeNative, _CredFreeDart>(
          'CredFree',
        ),
        getLastError: kernel
            .lookupFunction<_GetLastErrorNative, _GetLastErrorDart>(
              'GetLastError',
            ),
        heap: heap,
        heapAlloc: kernel.lookupFunction<_HeapAllocNative, _HeapAllocDart>(
          'HeapAlloc',
        ),
        heapFree: kernel.lookupFunction<_HeapFreeNative, _HeapFreeDart>(
          'HeapFree',
        ),
      );
    } on MayaCredentialStoreException {
      rethrow;
    } catch (_) {
      throw const MayaCredentialStoreException(
        MayaCredentialStoreErrorCode.unavailable,
      );
    }
  }

  final _CredWriteDart credWrite;
  final _CredReadDart credRead;
  final _CredDeleteDart credDelete;
  final _CredFreeDart credFree;
  final _GetLastErrorDart getLastError;
  final Pointer<Void> heap;
  final _HeapAllocDart heapAlloc;
  final _HeapFreeDart heapFree;
}

final class _NativeHeapArena {
  _NativeHeapArena(this._bindings);

  final _WinCredentialBindings _bindings;
  final List<({Pointer<Void> pointer, int size})> _allocations = [];
  bool _disposed = false;

  Pointer<Uint8> bytes(int length) => _allocate(length).cast<Uint8>();

  Pointer<Uint16> utf16(String value) {
    final units = value.codeUnits;
    final pointer = _allocate(
      (units.length + 1) * sizeOf<Uint16>(),
    ).cast<Uint16>();
    final view = pointer.asTypedList(units.length + 1);
    view.setRange(0, units.length, units);
    view[units.length] = 0;
    return pointer;
  }

  Pointer<_CredentialW> credential() =>
      _allocate(sizeOf<_CredentialW>()).cast<_CredentialW>();

  Pointer<Pointer<_CredentialW>> credentialOutput() =>
      _allocate(sizeOf<Pointer<_CredentialW>>()).cast<Pointer<_CredentialW>>();

  Pointer<Void> _allocate(int size) {
    if (_disposed || size <= 0) {
      throw const MayaCredentialStoreException(
        MayaCredentialStoreErrorCode.unavailable,
      );
    }
    final pointer = _bindings.heapAlloc(_bindings.heap, _heapZeroMemory, size);
    if (pointer == nullptr) {
      throw const MayaCredentialStoreException(
        MayaCredentialStoreErrorCode.unavailable,
      );
    }
    _allocations.add((pointer: pointer, size: size));
    return pointer;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final allocation in _allocations.reversed) {
      allocation.pointer
          .cast<Uint8>()
          .asTypedList(allocation.size)
          .fillRange(0, allocation.size, 0);
      _bindings.heapFree(_bindings.heap, 0, allocation.pointer);
    }
    _allocations.clear();
  }
}
