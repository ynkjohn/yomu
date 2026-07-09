import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_desktop/services/suwayomi_maya_port.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';

/// Records real method invocations without faking the port adapter itself.
class RecordingSuwayomiApi extends SuwayomiApi {
  RecordingSuwayomiApi()
      : super(SuwayomiClient(baseUrl: 'http://127.0.0.1:9'));

  int enqueueCalls = 0;
  int startDownloaderCalls = 0;
  List<int>? lastEnqueueIds;

  @override
  Future<void> enqueueChapterDownloads(List<int> chapterIds) async {
    enqueueCalls++;
    lastEnqueueIds = List<int>.from(chapterIds);
  }

  @override
  Future<void> startDownloader() async {
    startDownloaderCalls++;
  }
}

void main() {
  test('SuwayomiMayaPort enqueue calls enqueue + startDownloader on real API',
      () async {
    final api = RecordingSuwayomiApi();
    final port = SuwayomiMayaPort(() => api);

    await port.enqueueChapterDownload(42);

    expect(api.enqueueCalls, 1);
    expect(api.lastEnqueueIds, [42]);
    expect(api.startDownloaderCalls, 1,
        reason: 'must start downloader after enqueue');
  });
}
