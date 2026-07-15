import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_desktop/screens/explore_screen.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';

ExploreCatalogQuery query(
  String source,
  SourceMangaFetchType type, [
  String value = '',
]) => ExploreCatalogQuery(
  sourceId: source,
  fetchType: type,
  normalizedQuery: normalizeExploreQuery(value),
);

void main() {
  test('troca rápida de fonte rejeita a resposta da fonte anterior', () {
    final gate = ExploreCatalogRequestGate();
    final sourceA = gate.reset(query('source-a', SourceMangaFetchType.popular))!;
    final sourceB = gate.reset(query('source-b', SourceMangaFetchType.popular))!;

    expect(gate.accepts(sourceA), isFalse);
    expect(gate.accepts(sourceB), isTrue);
  });

  test('Popular para Recentes rejeita resposta fora de ordem', () {
    final gate = ExploreCatalogRequestGate();
    final popular = gate.reset(query('source', SourceMangaFetchType.popular))!;
    final latest = gate.reset(query('source', SourceMangaFetchType.latest))!;

    expect(gate.accepts(popular), isFalse);
    expect(gate.accepts(latest), isTrue);
  });

  test('busca substituída invalida a resposta anterior', () {
    final gate = ExploreCatalogRequestGate();
    final berserk = gate.reset(
      query('source', SourceMangaFetchType.search, '  Berserk  '),
    )!;
    final vagabond = gate.reset(
      query('source', SourceMangaFetchType.search, 'VAGABOND'),
    )!;

    expect(berserk.query.normalizedQuery, 'berserk');
    expect(vagabond.query.normalizedQuery, 'vagabond');
    expect(gate.accepts(berserk), isFalse);
    expect(gate.accepts(vagabond), isTrue);
  });

  test('página 2 antiga não é aceita após reset', () {
    final gate = ExploreCatalogRequestGate();
    final active = query('source', SourceMangaFetchType.popular);
    gate.reset(active);
    final oldPage2 = gate.next(active, 2)!;
    final reset = gate.reset(active)!;

    expect(gate.accepts(oldPage2), isFalse);
    expect(gate.accepts(reset), isTrue);
  });

  test('duplo carregar mais produz somente uma solicitação', () {
    final gate = ExploreCatalogRequestGate();
    final active = query('source', SourceMangaFetchType.popular);
    gate.reset(active);

    final first = gate.next(active, 2);
    final duplicate = gate.next(active, 2);

    expect(first, isNotNull);
    expect(duplicate, isNull);
    gate.complete(first!);
    expect(gate.next(active, 2), isNotNull);
  });

  test('reset idempotente não dispara segundo page-1 em voo', () {
    final gate = ExploreCatalogRequestGate();
    final active = query('source', SourceMangaFetchType.popular);
    final first = gate.reset(active);
    final second = gate.reset(active);

    expect(first, isNotNull);
    expect(second, isNull);
    expect(gate.accepts(first!), isTrue);
  });

  test('resposta em voo permanece aceita sem depender do campo de busca ao vivo', () {
    final gate = ExploreCatalogRequestGate();
    final request = gate.reset(
      query('source', SourceMangaFetchType.search, 'berserk'),
    )!;
    // Live UI query can diverge while request is in flight; acceptance is
    // generation-bound, not live-field-bound.
    expect(gate.accepts(request), isTrue);
    gate.reset(query('source', SourceMangaFetchType.search, 'vagabond'));
    expect(gate.accepts(request), isFalse);
  });
}
