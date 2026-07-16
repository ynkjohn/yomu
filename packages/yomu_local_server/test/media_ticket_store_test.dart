import 'package:test/test.dart';
import 'package:yomu_local_server/yomu_local_server.dart';

void main() {
  test('ticket is session-bound', () {
    final store = MediaTicketStore();
    final id = store.issue(
      sessionId: 'session-a',
      target: '/api/v1/manga/1/thumbnail',
    );
    expect(
      store.resolve(ticketId: id, sessionId: 'session-a')?.target,
      isNotNull,
    );
    expect(store.resolve(ticketId: id, sessionId: 'session-b'), isNull);
  });
}
