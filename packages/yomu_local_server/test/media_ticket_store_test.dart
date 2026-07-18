import 'package:test/test.dart';
import 'package:yomu_core/yomu_core.dart';
import 'package:yomu_local_server/yomu_local_server.dart';

void main() {
  test('ticket is session-bound', () {
    final store = MediaTicketStore();
    final id = store.issue(
      sessionId: 'session-a',
      reference: const _TestMediaReference('thumbnail-1'),
    );
    expect(
      store.resolve(ticketId: id, sessionId: 'session-a')?.reference,
      isNotNull,
    );
    expect(store.resolve(ticketId: id, sessionId: 'session-b'), isNull);
  });
}

final class _TestMediaReference implements MediaReference {
  const _TestMediaReference(this.value);

  final String value;
}
