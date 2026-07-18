import 'dart:async';

import 'package:test/test.dart';
import 'package:yomu_core/yomu_core.dart';

void main() {
  test('readiness exposes only product state and sanitized failure', () {
    const failure = EngineFailure(
      kind: EngineFailureKind.temporarilyUnavailable,
      code: 'engine_temporarily_unavailable',
      message: 'Recursos de leitura temporariamente indisponíveis.',
      retryable: true,
    );
    final retryAt = DateTime.utc(2026, 7, 18, 12);
    final recovering = EngineReadinessSnapshot(
      state: EngineReadinessState.recovering,
      failure: failure,
      attempt: 2,
      nextRetryAt: retryAt,
    );

    expect(recovering.isReady, isFalse);
    expect(recovering.failure, failure);
    expect(recovering.attempt, 2);
    expect(recovering.nextRetryAt, retryAt);
    expect(
      const EngineReadinessSnapshot(state: EngineReadinessState.ready).isReady,
      isTrue,
    );
  });

  test('engine exception contains only the sanitized failure', () {
    const failure = EngineFailure(
      kind: EngineFailureKind.operationRejected,
      code: 'engine_operation_failed',
      message: 'Não foi possível carregar a biblioteca.',
      retryable: true,
    );

    const exception = EngineException(failure);

    expect(exception.failure, failure);
    expect(
      exception.toString(),
      'EngineException(engine_operation_failed): '
      'Não foi possível carregar a biblioteca.',
    );
  });

  test('library models contain opaque media and value semantics', () {
    const cover = _TestMediaReference('cover-7');
    const chapter = LibraryResumePoint(
      id: 9,
      name: 'Capítulo 9',
      lastPageRead: 3,
    );
    const first = LibraryManga(
      id: 7,
      title: 'Yomu',
      thumbnail: cover,
      inLibrary: true,
      unreadCount: 4,
      lastReadChapter: chapter,
    );
    const second = LibraryManga(
      id: 7,
      title: 'Yomu',
      thumbnail: cover,
      inLibrary: true,
      unreadCount: 4,
      lastReadChapter: chapter,
    );

    expect(first, second);
    expect(first.hashCode, second.hashCode);
    expect(first.thumbnail, isA<MediaReference>());

    const minimal = LibraryManga(id: 8, title: 'Sem progresso');
    expect(minimal.unreadCount, isNull);
    expect(minimal.lastReadChapter, isNull);
    expect(minimal.thumbnail, isNull);
  });

  test('media payload owns a defensive byte copy', () {
    final source = <int>[1, 2, 3];
    final payload = MediaPayload(bytes: source, contentType: 'image/png');
    source[0] = 9;

    expect(payload.bytes, <int>[1, 2, 3]);
    expect(() => payload.bytes[0] = 9, throwsUnsupportedError);
    expect(
      payload,
      MediaPayload(bytes: const [1, 2, 3], contentType: 'image/png'),
    );
  });

  test('external fakes implement each narrow capability', () {
    expect(_TestReadiness(), isA<EngineReadiness>());
    expect(_TestLibraryGateway(), isA<LibraryGateway>());
    expect(_TestMediaGateway(), isA<EngineMediaGateway>());
  });
}

final class _TestMediaReference implements MediaReference {
  const _TestMediaReference(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      other is _TestMediaReference && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

final class _TestReadiness implements EngineReadiness {
  @override
  EngineReadinessSnapshot get current =>
      const EngineReadinessSnapshot(state: EngineReadinessState.initializing);

  @override
  Stream<EngineReadinessSnapshot> get changes => const Stream.empty();
}

final class _TestLibraryGateway implements LibraryGateway {
  @override
  Future<List<LibraryManga>> listLibrary() async => const [];
}

final class _TestMediaGateway implements EngineMediaGateway {
  @override
  Future<MediaPayload> fetch(
    MediaReference reference, {
    required int maxBytes,
  }) async {
    return MediaPayload(bytes: const []);
  }
}
