import 'dart:async';
import 'dart:ui' as ui;

import 'package:yomu_ai/yomu_ai.dart';
import 'package:yomu_core/yomu_core.dart';

/// Holds the native desktop exit response until owned resources are torn down.
///
/// Windows waits for this response before completing a close request. Repeated
/// requests share the same future so teardown remains idempotent.
class DesktopExitCoordinator {
  DesktopExitCoordinator({
    required Future<bool> Function() confirmExit,
    required Future<void> Function() shutdown,
  }) : _confirmExit = confirmExit,
       _shutdown = shutdown;

  final Future<bool> Function() _confirmExit;
  final Future<void> Function() _shutdown;
  Future<ui.AppExitResponse>? _response;

  Future<ui.AppExitResponse> requestExit() {
    final existing = _response;
    if (existing != null) return existing;

    final request = _confirmThenShutdown();
    _response = request;
    unawaited(
      request.then(
        (response) {
          if (response == ui.AppExitResponse.cancel &&
              identical(_response, request)) {
            _response = null;
          }
        },
        onError: (Object _, StackTrace __) {
          if (identical(_response, request)) _response = null;
        },
      ),
    );
    return request;
  }

  Future<ui.AppExitResponse> _confirmThenShutdown() async {
    if (!await _confirmExit()) return ui.AppExitResponse.cancel;
    await _shutdown();
    return ui.AppExitResponse.exit;
  }
}

/// Serial lifecycle queue used by HomeShell for bootstrap, HTTP restart, and
/// shutdown (same coordination for all three).
class DesktopLifecycleQueue {
  Future<void> _chain = Future<void>.value();
  Future<void>? _shutdownFuture;
  bool shuttingDown = false;

  Future<void>? get shutdownFuture => _shutdownFuture;

  /// Run [op] after any prior lifecycle op (including restart/bootstrap).
  Future<void> run(Future<void> Function() op) {
    final c = Completer<void>();
    _chain = _chain.then((_) async {
      try {
        await op();
        if (!c.isCompleted) c.complete();
      } catch (e, st) {
        if (!c.isCompleted) c.completeError(e, st);
      }
    });
    return c.future;
  }

  /// Idempotent shutdown: seals admission synchronously, then waits for any
  /// in-flight lifecycle operation before teardown.
  Future<void> shutdown(
    Future<void> Function() teardown, {
    void Function()? beginShutdown,
  }) {
    if (_shutdownFuture != null) return _shutdownFuture!;
    shuttingDown = true;
    final c = Completer<void>();
    _shutdownFuture = c.future;
    beginShutdown?.call();
    unawaited(
      run(() async {
        try {
          await teardown();
          if (!c.isCompleted) c.complete();
        } catch (e, st) {
          if (!c.isCompleted) c.completeError(e, st);
        }
      }),
    );
    return _shutdownFuture!;
  }
}

/// Seals every mutable desktop entry point before coordinated drains begin.
///
/// The callbacks keep lifecycle/vendor implementations in [HomeShell], while
/// this synchronous boundary is shared with tests that prove no mutation can
/// be admitted once the first shutdown step returns.
class DesktopShutdownAdmission {
  static void stopAccepting({
    EngineMutationGate? engineMutations,
    MayaService? maya,
    void Function()? beginCoreShutdown,
    void Function()? stopProgressWrites,
    void Function()? beginEngineShutdown,
  }) {
    engineMutations?.stopAccepting();
    maya?.stopAccepting();
    beginCoreShutdown?.call();
    stopProgressWrites?.call();
    beginEngineShutdown?.call();
  }
}

/// Replace HTTP server under lifecycle rules.
///
/// - Stops/clears old server first.
/// - On start failure, unmount, or shutdown: disposes the replacement if created.
/// - Never leaves a dangling replacement server reference.
class HttpServerRestartCoordinator {
  /// [stopOld] should stop+close and null the stored reference.
  /// [startNew] creates and starts a server (may throw).
  /// [disposeServer] stop+close independently (close even if stop throws).
  /// [shouldAbort] true when !mounted or shuttingDown.
  /// [commit] stores the replacement server as the live reference.
  static Future<T?> replaceServer<T>({
    required Future<void> Function() stopOld,
    required Future<T> Function() startNew,
    required Future<void> Function(T server) disposeServer,
    required bool Function() shouldAbort,
    required void Function(T server) commit,
  }) async {
    T? created;
    try {
      await stopOld();
      if (shouldAbort()) return null;
      final started = await startNew();
      created = started;
      if (shouldAbort()) {
        created = null;
        await disposeServer(started);
        return null;
      }
      commit(started);
      created = null; // ownership transferred
      return started;
    } catch (e) {
      final orphan = created;
      created = null;
      if (orphan != null) {
        try {
          await disposeServer(orphan);
        } catch (_) {}
      }
      rethrow;
    }
  }
}

/// Coordinated shutdown order:
/// block mutations → final progress → drains → pause downloads → Core HTTP →
/// Maya/Auth → owned engine → DB.
///
/// [closeServer] always runs even if [stopServer] throws.
class ResourceTeardown {
  static Future<void> run({
    Future<void> Function()? cancelSubscription,
    Future<void> Function()? beginShutdown,
    Future<void> Function()? flushFinalProgress,
    Future<void> Function()? sealFinalProgress,
    Future<void> Function()? drainProgress,
    Future<bool> Function()? drainRequests,
    Future<void> Function()? sealAdmittedProgress,
    Future<void> Function()? pauseDownloads,
    Future<void> Function({required bool force})? stopServer,
    Future<void> Function()? closeServer,
    Future<void> Function()? closeMaya,
    Future<void> Function()? releaseMayaPort,
    Future<void> Function()? closeAuth,
    Future<void> Function()? shutdownEngine,
    Future<void> Function()? disposeManager,
    Future<void> Function()? closeDb,
  }) async {
    Future<void> bestEffort(Future<void> Function()? operation) async {
      try {
        await operation?.call();
      } catch (_) {}
    }

    await bestEffort(beginShutdown);
    await bestEffort(cancelSubscription);
    await bestEffort(flushFinalProgress);
    await bestEffort(sealFinalProgress);
    var forceServerStop = false;
    Future<void> drainServerRequests() async {
      try {
        forceServerStop = await drainRequests?.call() ?? false;
      } catch (_) {
        // An indeterminate request drain must not turn graceful stop into an
        // unbounded wait.
        forceServerStop = true;
      }
    }

    await Future.wait<void>([bestEffort(drainProgress), drainServerRequests()]);
    await bestEffort(sealAdmittedProgress);
    await bestEffort(pauseDownloads);
    await bestEffort(
      stopServer == null ? null : () => stopServer(force: forceServerStop),
    );
    await bestEffort(closeServer);
    await bestEffort(closeMaya);
    await bestEffort(releaseMayaPort);
    await bestEffort(closeAuth);
    if (shutdownEngine != null) {
      // Ownership confirmation is safety-critical: do not report exit success
      // or close SQLite when the owned process could not be stopped.
      await shutdownEngine();
    } else {
      await bestEffort(disposeManager);
    }
    await bestEffort(closeDb);
  }
}

/// Storage-first bootstrap phases used by HomeShell and unit tests.
///
/// Ensures Auth is initialized only after storage opens, optional Maya is
/// initialized only after Auth, and remaining services start last.
class StorageFirstBootstrap {
  /// [openStorage] must acquire lock + open DB (or throw).
  /// [initializeAuth] loads Auth from SQLite and migrates legacy sessions.
  /// [initializeOptionalMaya] loads Maya from SQLite and may migrate its legacy
  /// JSON. Only [LegacyMayaMigrationException] degrades Maya; storage failures
  /// continue to fail bootstrap.
  /// [onMayaUnavailable] receives the typed legacy failure for sanitization.
  /// [startRemainingServices] creates the reading engine and Core HTTP.
  static Future<void> run({
    required Future<void> Function() openStorage,
    required Future<void> Function() initializeAuth,
    required Future<void> Function() initializeOptionalMaya,
    required void Function(LegacyMayaMigrationException error)
    onMayaUnavailable,
    required Future<void> Function() startRemainingServices,
  }) async {
    await openStorage();
    await initializeAuth();
    try {
      await initializeOptionalMaya();
    } on LegacyMayaMigrationException catch (error) {
      onMayaUnavailable(error);
    }
    await startRemainingServices();
  }
}

/// Opens the optional cloud-provider layer without making Maya history or the
/// deterministic local assistant depend on Credential Manager or networking.
class OptionalMayaProviderBootstrap {
  static Future<T?> open<T>(Future<T> Function() initialize) async {
    try {
      return await initialize();
    } catch (_) {
      return null;
    }
  }

  /// Transfers a successfully opened provider only while bootstrap still owns
  /// it. If shutdown wins the race, disposal completes before this returns.
  static Future<T?> openAbortable<T>({
    required Future<T> Function() initialize,
    required bool Function() shouldAbort,
    required Future<void> Function(T instance) dispose,
  }) async {
    try {
      final instance = await initialize();
      if (!shouldAbort()) return instance;
      await dispose(instance);
      return null;
    } catch (_) {
      return null;
    }
  }
}
