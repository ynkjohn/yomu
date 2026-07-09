import 'package:test/test.dart';
import 'package:yomu_local_server/yomu_local_server.dart';

void main() {
  test('ticket is session-bound', () {
    final store = MediaTicketStore();
    final id = store.issue(
      sessionToken: 'tok-a',
      target: '/api/v1/manga/1/thumbnail',
    );
    expect(store.resolve(ticketId: id, sessionToken: 'tok-a')?.target, isNotNull);
    expect(store.resolve(ticketId: id, sessionToken: 'tok-b'), isNull);
  });
}
