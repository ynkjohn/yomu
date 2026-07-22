import 'dart:async';

import 'package:test/test.dart';
import 'package:yomu_core/yomu_core.dart';

void main() {
  test(
    'coalesces newer progress without publishing a stale response',
    () async {
      final upstream = _ControlledProgressGateway();
      final coordinator = ReadingProgressCoordinator(upstream);

      final first = coordinator.updateProgress(
        chapterId: 1,
        lastPageRead: 2,
        isRead: false,
      );
      await _flush();
      final newer = coordinator.updateProgress(
        chapterId: 1,
        lastPageRead: 7,
        isRead: true,
      );

      upstream.completeNext(page: 2);
      await _flush();
      expect(upstream.calls.map((call) => call.lastPageRead), [2, 7]);
      expect(await _isComplete(first), isFalse);

      upstream.completeNext(page: 6, isRead: false);
      expect(
        await first,
        const ReadingProgressSnapshot(
          chapterId: 1,
          lastPageRead: 7,
          isRead: true,
        ),
      );
      expect(await newer, await first);
    },
  );

  test('preserves A to B to A order and chapter high-water', () async {
    final upstream = _ControlledProgressGateway();
    final coordinator = ReadingProgressCoordinator(upstream);

    final a1 = coordinator.updateProgress(
      chapterId: 1,
      lastPageRead: 3,
      isRead: false,
    );
    await _flush();
    final b = coordinator.updateProgress(
      chapterId: 2,
      lastPageRead: 1,
      isRead: false,
    );
    final a2 = coordinator.saveFinal(
      chapterId: 1,
      lastPageRead: 9,
      isRead: true,
    );

    upstream.completeNext(page: 3);
    await _flush();
    upstream.completeNext(page: 1);
    await _flush();
    upstream.completeNext(page: 9, isRead: true);

    await Future.wait([a1, b, a2]);
    expect(upstream.calls.map((call) => (call.chapterId, call.lastPageRead)), [
      (1, 3),
      (2, 1),
      (1, 9),
    ]);
  });

  test('older error is absorbed when a newer write succeeds', () async {
    final upstream = _ControlledProgressGateway();
    final coordinator = ReadingProgressCoordinator(upstream);

    final old = coordinator.updateProgress(
      chapterId: 4,
      lastPageRead: 1,
      isRead: false,
    );
    await _flush();
    final current = coordinator.updateProgress(
      chapterId: 4,
      lastPageRead: 5,
      isRead: false,
    );
    upstream.failNext(StateError('raw upstream failure'));
    await _flush();
    upstream.completeNext(page: 5);

    expect((await old).lastPageRead, 5);
    expect((await current).lastPageRead, 5);
  });

  test('page zero stays 0-based', () async {
    final upstream = _ImmediateProgressGateway();
    final coordinator = ReadingProgressCoordinator(upstream);

    final saved = await coordinator.updateProgress(
      chapterId: 7,
      lastPageRead: 0,
      isRead: false,
    );

    expect(saved.lastPageRead, 0);
    expect(upstream.lastPageRead, 0);
  });

  test('stopAccepting rejects new writes and drain is bounded', () async {
    final upstream = _ControlledProgressGateway();
    final coordinator = ReadingProgressCoordinator(upstream);
    final admitted = coordinator.updateProgress(
      chapterId: 8,
      lastPageRead: 2,
      isRead: false,
    );
    await _flush();

    coordinator.stopAccepting();
    expect(
      coordinator.updateProgress(chapterId: 8, lastPageRead: 3, isRead: false),
      throwsA(isA<EngineException>()),
    );
    final finalSave = coordinator.saveFinal(
      chapterId: 8,
      lastPageRead: 4,
      isRead: true,
    );
    expect(
      await coordinator.drain(timeout: Duration.zero),
      ReadingProgressDrainResult.timedOut,
    );

    upstream.completeNext(page: 2);
    await _flush();
    upstream.completeNext(page: 4, isRead: true);
    await Future.wait([admitted, finalSave]);
    expect(
      await coordinator.drain(timeout: const Duration(seconds: 1)),
      ReadingProgressDrainResult.drained,
    );
  });
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

Future<bool> _isComplete(Future<Object?> future) async {
  var complete = false;
  future.then<void>((_) => complete = true, onError: (_) => complete = true);
  await _flush();
  return complete;
}

final class _ProgressCall {
  const _ProgressCall(this.chapterId, this.lastPageRead, this.isRead);

  final int chapterId;
  final int lastPageRead;
  final bool isRead;
}

final class _ControlledProgressGateway implements ReadingProgressGateway {
  final calls = <_ProgressCall>[];
  final pending = <Completer<ReadingProgressSnapshot>>[];

  @override
  Future<ReadingProgressSnapshot> updateProgress({
    required int chapterId,
    required int lastPageRead,
    required bool isRead,
  }) {
    calls.add(_ProgressCall(chapterId, lastPageRead, isRead));
    final completer = Completer<ReadingProgressSnapshot>();
    pending.add(completer);
    return completer.future;
  }

  void completeNext({required int page, bool isRead = false}) {
    final call = calls[calls.length - pending.length];
    pending
        .removeAt(0)
        .complete(
          ReadingProgressSnapshot(
            chapterId: call.chapterId,
            lastPageRead: page,
            isRead: isRead,
          ),
        );
  }

  void failNext(Object error) => pending.removeAt(0).completeError(error);
}

final class _ImmediateProgressGateway implements ReadingProgressGateway {
  int? lastPageRead;

  @override
  Future<ReadingProgressSnapshot> updateProgress({
    required int chapterId,
    required int lastPageRead,
    required bool isRead,
  }) async {
    this.lastPageRead = lastPageRead;
    return ReadingProgressSnapshot(
      chapterId: chapterId,
      lastPageRead: lastPageRead,
      isRead: isRead,
    );
  }
}
