import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_desktop/shell/desktop_lifecycle.dart';
import 'package:yomu_storage/yomu_storage.dart';

void main() {
  test('StorageFirstBootstrap does not call afterStorage when open fails',
      () async {
    var after = false;
    await expectLater(
      StorageFirstBootstrap.run(
        openStorage: () async {
          throw StateError('lock held');
        },
        afterStorage: () async {
          after = true;
        },
      ),
      throwsStateError,
    );
    expect(after, isFalse);
  });

  test('StorageFirstBootstrap runs afterStorage only after openStorage',
      () async {
    final order = <String>[];
    await StorageFirstBootstrap.run(
      openStorage: () async {
        order.add('open');
      },
      afterStorage: () async {
        order.add('after');
      },
    );
    expect(order, ['open', 'after']);
  });

  test('HttpServerRestartCoordinator disposes new server on abort after start',
      () async {
    final events = <String>[];
    final result = await HttpServerRestartCoordinator.replaceServer<String>(
      stopOld: () async {
        events.add('stopOld');
      },
      startNew: () async {
        events.add('startNew');
        return 'server-new';
      },
      disposeServer: (s) async {
        events.add('dispose:$s');
      },
      shouldAbort: () {
        // Abort after start would be checked post-start; first check before start.
        return events.contains('startNew');
      },
      commit: (s) {
        events.add('commit:$s');
      },
    );
    expect(result, isNull);
    expect(events, contains('stopOld'));
    expect(events, contains('startNew'));
    expect(events, contains('dispose:server-new'));
    expect(events, isNot(contains('commit:server-new')));
  });

  test('HttpServerRestartCoordinator: start failure cleans server before rethrow',
      () async {
    final events = <String>[];
    // Mirrors HomeShell: build server, start throws → dispose inline, rethrow.
    // Coordinator must not commit; no live reference left.
    Object? live;
    await expectLater(
      HttpServerRestartCoordinator.replaceServer<String>(
        stopOld: () async {
          events.add('stopOld');
          live = null;
        },
        startNew: () async {
          events.add('startNew');
          const created = 'server-new';
          try {
            throw StateError('bind failed');
          } catch (_) {
            events.add('dispose-inline:$created');
            rethrow;
          }
        },
        disposeServer: (s) async {
          events.add('dispose:$s');
        },
        shouldAbort: () => false,
        commit: (s) {
          live = s;
          events.add('commit:$s');
        },
      ),
      throwsStateError,
    );
    expect(live, isNull);
    expect(events, contains('stopOld'));
    expect(events, contains('startNew'));
    expect(events, contains('dispose-inline:server-new'));
    expect(events, isNot(contains('commit:server-new')));
  });

  test('HttpServerRestartCoordinator: unmount mid-restart disposes new server',
      () async {
    final events = <String>[];
    var mounted = true;
    Object? live;
    final result = await HttpServerRestartCoordinator.replaceServer<String>(
      stopOld: () async {
        events.add('stopOld');
        live = null;
      },
      startNew: () async {
        events.add('startNew');
        mounted = false; // unmount while start completes
        return 'server-new';
      },
      disposeServer: (s) async {
        events.add('dispose:$s');
      },
      shouldAbort: () => !mounted,
      commit: (s) {
        live = s;
        events.add('commit');
      },
    );
    expect(result, isNull);
    expect(live, isNull);
    expect(events, ['stopOld', 'startNew', 'dispose:server-new']);
  });

  test('HttpServerRestartCoordinator: shutdown during restart aborts commit',
      () async {
    final queue = DesktopLifecycleQueue();
    final events = <String>[];
    Object? live;
    // Gate: restart enters stopOld, then we mark shutdown, then stopOld continues.
    final enteredStop = Completer<void>();
    final allowStopContinue = Completer<void>();

    final restart = queue.run(() async {
      await HttpServerRestartCoordinator.replaceServer<String>(
        stopOld: () async {
          events.add('stopOld');
          if (!enteredStop.isCompleted) enteredStop.complete();
          await allowStopContinue.future;
        },
        startNew: () async {
          events.add('startNew');
          return 'S';
        },
        disposeServer: (s) async {
          events.add('dispose:$s');
        },
        shouldAbort: () => queue.shuttingDown,
        commit: (s) {
          live = s;
          events.add('commit');
        },
      );
    });

    await enteredStop.future;
    final shutdown = queue.shutdown(() async {
      events.add('shutdown');
      live = null;
    });
    // shuttingDown is true; release stopOld so shouldAbort aborts before startNew.
    allowStopContinue.complete();

    await restart;
    await shutdown;
    expect(events, contains('stopOld'));
    expect(events, contains('shutdown'));
    expect(events, isNot(contains('commit')));
    // Aborted after stopOld (before start) — no replacement server to dispose.
    expect(events, isNot(contains('startNew')));
    expect(live, isNull);
  });

  test('ResourceTeardown closes server even if stop throws', () async {
    final events = <String>[];
    await ResourceTeardown.run(
      stopServer: () async {
        events.add('stop');
        throw StateError('stop failed');
      },
      closeServer: () async {
        events.add('close');
      },
      disposeManager: () async {
        events.add('manager');
      },
      closeDb: () async {
        events.add('db');
      },
    );
    expect(events, ['stop', 'close', 'manager', 'db']);
  });

  test(
    'second open via StorageFirstBootstrap never reaches Auth/Core/Suwayomi',
    () async {
      final root = await Directory.systemTemp.createTemp('yomu-boot-coord-');
      addTearDown(() async {
        try {
          if (YomuDatabase.instance != null) {
            await YomuDatabase.instance!.close();
          }
        } catch (_) {}
        try {
          root.deleteSync(recursive: true);
        } catch (_) {}
      });

      final first = await YomuDatabase.open(root);
      var auth = false;
      var core = false;
      var suwa = false;

      await expectLater(
        StorageFirstBootstrap.run(
          openStorage: () => YomuDatabase.open(root),
          afterStorage: () async {
            // These factories are what HomeShell runs only after storage open.
            auth = true;
            core = true;
            suwa = true;
          },
        ),
        throwsStateError,
      );
      expect(auth, isFalse);
      expect(core, isFalse);
      expect(suwa, isFalse);
      await first.close();
    },
  );
}
