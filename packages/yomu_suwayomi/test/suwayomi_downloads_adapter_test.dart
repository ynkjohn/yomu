import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:yomu_core/yomu_core.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';

void main() {
  test('maps empty and active queues to Yomu states', () async {
    var active = false;
    final adapter = _adapter(
      (_) async => _downloadsResponse(
        state: active ? 'Started' : 'STOPPED',
        queue: active
            ? [
                _item('QUEUED', chapterId: 1),
                _item('Downloading', chapterId: 2, progress: 0.5),
                _item('ERROR', chapterId: 3),
                _item('COMPLETED', chapterId: 4, progress: 1),
              ]
            : const [],
      ),
    );

    final empty = await adapter.getStatus();
    expect(empty.managerState, DownloadManagerState.paused);
    expect(empty.hasActivity, isFalse);

    active = true;
    final snapshot = await adapter.getStatus();
    expect(snapshot.managerState, DownloadManagerState.running);
    expect(snapshot.activeCount, 1);
    expect(snapshot.hasActivity, isTrue);
    expect(snapshot.queue.map((item) => item.state), [
      DownloadItemState.queued,
      DownloadItemState.downloading,
      DownloadItemState.failed,
      DownloadItemState.completed,
    ]);
  });

  test(
    'preserves enqueue, dequeue, pause, resume and clear operations',
    () async {
      final operations = <String>[];
      final adapter = _adapter((request) async {
        final query = _query(request);
        if (query.contains('enqueueChapterDownloads')) {
          operations.add('enqueue');
          return _mutationResponse('enqueueChapterDownloads');
        }
        if (query.contains('dequeueChapterDownloads')) {
          operations.add('dequeue');
          return _mutationResponse('dequeueChapterDownloads');
        }
        if (query.contains('clearDownloader')) {
          operations.add('clear');
          return _mutationResponse('clearDownloader');
        }
        if (query.contains('startDownloader')) {
          operations.add('resume');
          return _mutationResponse('startDownloader');
        }
        if (query.contains('stopDownloader')) {
          operations.add('pause');
          return _mutationResponse('stopDownloader');
        }
        operations.add('status');
        return _downloadsResponse(state: 'STOPPED', queue: const []);
      });

      await adapter.enqueueChapters([1, 2]);
      await adapter.dequeueChapters([1]);
      await adapter.resume();
      final ack = await adapter.pause();
      await adapter.clear();

      expect(ack.acknowledged, isTrue);
      expect(operations, [
        'enqueue',
        'dequeue',
        'resume',
        'pause',
        'status',
        'clear',
      ]);
    },
  );

  test('pause ack and activity queries stay bounded contracts', () async {
    final adapter = _adapter((request) async {
      final query = _query(request);
      if (query.contains('stopDownloader')) {
        return _mutationResponse('stopDownloader');
      }
      return _downloadsResponse(
        state: 'STOPPED',
        queue: [_item('QUEUED', chapterId: 7)],
      );
    });

    expect(await adapter.hasActivity(), isTrue);
    expect(
      await adapter.pauseAndAwaitAck(timeout: const Duration(seconds: 1)),
      const DownloadPauseAck(
        managerState: DownloadManagerState.paused,
        acknowledged: true,
      ),
    );
  });

  test('unknown states and invalid progress fail safe', () async {
    final unknownManager = _adapter(
      (_) async => _downloadsResponse(state: 'MYSTERY', queue: const []),
    );
    final unknownItem = _adapter(
      (_) async =>
          _downloadsResponse(state: 'STOPPED', queue: [_item('MYSTERY')]),
    );
    final invalidProgress = _adapter(
      (_) async => _downloadsResponse(
        state: 'STOPPED',
        queue: [_item('QUEUED', progress: 1.5)],
      ),
    );

    for (final adapter in [unknownManager, unknownItem, invalidProgress]) {
      await expectLater(
        adapter.getStatus(),
        throwsA(
          isA<EngineException>().having(
            (error) => error.failure.code,
            'code',
            'engine_download_state_unsupported',
          ),
        ),
      );
    }
  });

  test('transport failure and pause timeout are sanitized', () async {
    final unavailable = _adapter(
      (_) async => http.Response('private upstream body', 500),
    );
    await expectLater(
      unavailable.getStatus(),
      throwsA(
        isA<EngineException>().having(
          (error) => error.toString(),
          'sanitized',
          allOf(
            contains('engine_downloads_unavailable'),
            isNot(contains('private')),
          ),
        ),
      ),
    );

    final blocked = SuwayomiDownloadsAdapter(_BlockingDownloadsApi());
    await expectLater(
      blocked.pauseAndAwaitAck(timeout: const Duration(milliseconds: 1)),
      throwsA(
        isA<EngineException>().having(
          (error) => error.failure.code,
          'code',
          'engine_download_pause_timeout',
        ),
      ),
    );
  });
}

SuwayomiDownloadsAdapter _adapter(
  Future<http.Response> Function(http.Request request) handler,
) => SuwayomiDownloadsAdapter(
  SuwayomiApi(
    SuwayomiClient(
      baseUrl: 'http://127.0.0.1:14567',
      httpClient: MockClient(handler),
    ),
  ),
);

String _query(http.Request request) {
  expect(request.url.path, '/api/graphql');
  return (jsonDecode(request.body) as Map<String, dynamic>)['query'] as String;
}

Map<String, Object?> _item(String state, {int? chapterId, double? progress}) =>
    {
      'state': state,
      'progress': progress,
      'chapter': chapterId == null
          ? null
          : {'id': chapterId, 'name': 'Capítulo $chapterId', 'mangaId': 9},
      'manga': {'id': 9, 'title': 'Obra'},
    };

http.Response _downloadsResponse({
  required String state,
  required List<Map<String, Object?>> queue,
}) => http.Response(
  jsonEncode({
    'data': {
      'downloadStatus': {'state': state, 'queue': queue},
    },
  }),
  200,
  headers: {'content-type': 'application/json'},
);

http.Response _mutationResponse(String field) => http.Response(
  jsonEncode({
    'data': {
      field: {
        'downloadStatus': {'state': 'STOPPED'},
      },
    },
  }),
  200,
  headers: {'content-type': 'application/json'},
);

final class _BlockingDownloadsApi extends SuwayomiApi {
  _BlockingDownloadsApi()
    : super(SuwayomiClient(baseUrl: 'http://127.0.0.1:14567'));

  @override
  Future<void> stopDownloader() => Completer<void>().future;
}
