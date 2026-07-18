// ignore_for_file: avoid_print
// Gate funcional #1 — E2E Suwayomi + Keiyoushi até páginas reais.
//
//   dart run tool/gate_functional_1.dart
//
// Exit 0 only if at least one chapter page URL is returned.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yomu_suwayomi/yomu_suwayomi.dart';

const keiyoushiIndex =
    'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json';

const preferredPkg = 'eu.kanade.tachiyomi.extension.all.mangadex';
const fallbackPkgHints = <String>[
  'eu.kanade.tachiyomi.extension.en.mangahere',
  'eu.kanade.tachiyomi.extension.en.mangakakalot',
  'eu.kanade.tachiyomi.extension.all.comick',
];

class GateEvidence {
  final steps = <String>[];
  final errors = <String>[];
  final gqlFields = <String>[];
  String? extensionPkg;
  String? extensionName;
  String? sourceId;
  String? sourceName;
  String? sourceLang;
  String searchQuery = 'one';
  int? mangaId;
  String? mangaTitle;
  int chapterCount = 0;
  int? chapterId;
  String? chapterName;
  int pageCount = 0;
  final pageUrls = <String>[];
  String? aboutVersion;
  bool pagesGatePassed = false;

  void step(String s) {
    steps.add(s);
    print('>> $s');
  }

  void err(String e) {
    errors.add(e);
    print('!! $e');
  }

  void field(String f) {
    if (!gqlFields.contains(f)) gqlFields.add(f);
  }
}

Future<void> main(List<String> args) async {
  final writeDoc = !args.contains('--no-write');
  final evidence = GateEvidence();
  final root = Directory(
    p.join(Directory.systemTemp.path, 'yomu-gate-functional-1'),
  );
  if (root.existsSync()) {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  }
  root.createSync(recursive: true);

  final manifest = await VendorManifest.loadForRuntime();

  final manager = SuwayomiProcessManager(
    paths: SuwayomiPaths(root),
    manifest: manifest,
    host: '127.0.0.1',
    port: kYomuSuwayomiPort,
  );
  final client = manager.createClient();

  Future<Map<String, dynamic>?> gql(
    String label,
    String query, {
    Map<String, dynamic>? variables,
  }) async {
    try {
      final body = await client.graphql(query, variables: variables);
      evidence.step('GQL OK: $label');
      return body;
    } catch (e) {
      evidence.err('GQL FAIL $label: $e');
      return null;
    }
  }

  try {
    // 1. Start
    evidence.step(
      'Start Suwayomi managed @ 127.0.0.1:$kYomuSuwayomiPort '
      'rootDir=${manager.managedRootDir}',
    );
    final started =
        await manager.start(readyTimeout: const Duration(minutes: 4));
    final startOk = started.when(
      ok: (s) {
        evidence.step('Start status: ${s.state.name} baseUrl=${s.baseUrl}');
        return true;
      },
      err: (m, _) {
        evidence.err('Start failed: $m');
        return false;
      },
    );
    if (!startOk) {
      await _finish(evidence, manager, writeDoc, exitCode: 1);
      return;
    }

    final isolation = await manager.verifyManagedDataRoot();
    if (!isolation.isOk) {
      evidence.err(isolation.message ?? 'isolation failed');
      await _finish(evidence, manager, writeDoc, exitCode: 2);
      return;
    }
    evidence.step('Isolation OK observedRoot=${isolation.observedRoot}');

    final about = await client.about();
    evidence.aboutVersion =
        about == null ? null : '${about['version']} / ${about['revision']}';
    evidence.step('About: ${evidence.aboutVersion}');

    // 2. Keiyoushi store
    evidence.field('addExtensionStore(input: { indexUrl })');
    final addStore = await gql(
      'addExtensionStore',
      r'''
      mutation($url: String!) {
        addExtensionStore(input: { indexUrl: $url }) {
          extensionStore { name indexUrl isLegacy extensionListUrl }
        }
      }
      ''',
      variables: {'url': keiyoushiIndex},
    );
    if (addStore == null) {
      // may already exist from prior run — list stores
      evidence.step('addExtensionStore failed; listing stores…');
    }
    evidence.field('extensionStores { nodes { name indexUrl isLegacy } }');
    final stores = await gql(
      'extensionStores',
      r'''
      query {
        extensionStores {
          nodes { name indexUrl isLegacy }
          totalCount
        }
      }
      ''',
    );
    final storeNodes =
        (((stores?['data'] as Map?)?['extensionStores'] as Map?)?['nodes']
                as List?) ??
            [];
    evidence.step(
      'Stores total=${((stores?['data'] as Map?)?['extensionStores'] as Map?)?['totalCount']} '
      'nodes=${storeNodes.length} detail=$storeNodes',
    );
    if (storeNodes.isEmpty) {
      evidence.err('No extension stores configured after Keiyoushi add');
      await _finish(evidence, manager, writeDoc, exitCode: 3);
      return;
    }

    // 3. Fetch + list extensions
    evidence.field('fetchExtensions(input: {})');
    final fetch = await gql(
      'fetchExtensions',
      r'''
      mutation {
        fetchExtensions(input: {}) {
          clientMutationId
          extensions { pkgName name isInstalled lang }
        }
      }
      ''',
    );
    final fetched = (((fetch?['data'] as Map?)?['fetchExtensions']
            as Map?)?['extensions'] as List?) ??
        [];
    evidence.step('fetchExtensions returned ${fetched.length} extensions');

    evidence.field(
      'extensions { nodes { pkgName name isInstalled versionName lang } }',
    );
    final extList = await gql(
      'extensions',
      r'''
      query {
        extensions {
          nodes { pkgName name isInstalled versionName lang apkName }
          totalCount
        }
      }
      ''',
    );
    final extNodes =
        (((extList?['data'] as Map?)?['extensions'] as Map?)?['nodes']
                as List?) ??
            [];
    final total =
        ((extList?['data'] as Map?)?['extensions'] as Map?)?['totalCount'];
    evidence.step('extensions totalCount=$total nodes=${extNodes.length}');
    if (extNodes.isEmpty) {
      evidence.err('Extension catalog empty after fetch');
      await _finish(evidence, manager, writeDoc, exitCode: 4);
      return;
    }

    // 4. Install extension (MangaDex preferred)
    final candidates = <Map>[];
    Map? pick(String pkg) {
      for (final n in extNodes.whereType<Map<Object?, Object?>>()) {
        if (n['pkgName'] == pkg) return n;
      }
      return null;
    }

    final preferred = pick(preferredPkg);
    if (preferred != null) candidates.add(preferred);
    for (final hint in fallbackPkgHints) {
      final m = pick(hint);
      if (m != null) candidates.add(m);
    }
    // any non-NSFW-looking english/all as last resort from list head
    for (final n in extNodes.whereType<Map<Object?, Object?>>().take(50)) {
      if (!candidates.any((c) => c['pkgName'] == n['pkgName'])) {
        candidates.add(n);
      }
    }

    String? installedPkg;
    for (final cand in candidates) {
      final pkg = '${cand['pkgName']}';
      final name = '${cand['name']}';
      evidence.step('Trying install pkg=$pkg name=$name');
      evidence.field(
        'updateExtension(input: { id: pkgName, patch: { install: true } })',
      );
      final inst = await gql(
        'install-$pkg',
        r'''
        mutation($id: String!) {
          updateExtension(input: { id: $id, patch: { install: true } }) {
            extension { pkgName name isInstalled versionName lang }
          }
        }
        ''',
        variables: {'id': pkg},
      );
      final ext = ((inst?['data'] as Map?)?['updateExtension']
          as Map?)?['extension'] as Map?;
      if (ext != null && ext['isInstalled'] == true) {
        installedPkg = pkg;
        evidence.extensionPkg = pkg;
        evidence.extensionName = '${ext['name']}';
        evidence.step('Installed OK: $ext');
        break;
      }
      evidence.err('Install did not confirm isInstalled for $pkg');
    }

    if (installedPkg == null) {
      evidence.err('Failed to install any extension candidate');
      await _finish(evidence, manager, writeDoc, exitCode: 5);
      return;
    }

    // 5. Locate source
    await Future<void>.delayed(const Duration(seconds: 3));
    evidence.field('sources { nodes { id name lang } }');
    final sources = await gql(
      'sources',
      r'''
      query {
        sources {
          nodes { id name lang iconUrl }
          totalCount
        }
      }
      ''',
    );
    final sourceNodes =
        (((sources?['data'] as Map?)?['sources'] as Map?)?['nodes'] as List?) ??
            [];
    evidence.step(
      'Sources total=${((sources?['data'] as Map?)?['sources'] as Map?)?['totalCount']} '
      'nodes=${sourceNodes.length}',
    );

    Map? source;
    // Prefer English MangaDex
    for (final n in sourceNodes.whereType<Map<Object?, Object?>>()) {
      if (n['id'].toString() == '0') continue;
      final name = '${n['name']}'.toLowerCase();
      final lang = '${n['lang']}';
      if (name.contains('mangadex') && lang == 'en') {
        source = n;
        break;
      }
    }
    source ??= sourceNodes.whereType<Map<Object?, Object?>>().cast<Map<Object?, Object?>?>().firstWhere(
          (n) => n != null && n['id'].toString() != '0',
          orElse: () => null,
        );
    if (source == null) {
      evidence.err(
        'No non-local source after install of $installedPkg '
        '(sources=${sourceNodes.length})',
      );
      await _finish(evidence, manager, writeDoc, exitCode: 6);
      return;
    }
    evidence.sourceId = '${source['id']}';
    evidence.sourceName = '${source['name']}';
    evidence.sourceLang = '${source['lang']}';
    evidence.step(
      'Using source id=${evidence.sourceId} '
      'name=${evidence.sourceName} lang=${evidence.sourceLang}',
    );

    // 6–11. Search → pick work with chapters → pages
    evidence.field(
      'fetchSourceManga(input: { source, type: SEARCH, query, page })',
    );
    evidence.field(
      'fetchMangaAndChapters(input: { id, fetchManga, fetchChapters })',
    );
    evidence.field(
      'fetchChapterPages(input: { chapterId }) { pages }',
    );
    evidence.field(
      'manga(id) { chapters { nodes { id name chapterNumber pageCount } } }',
    );

    final searchQueries = <String>[
      'berserk',
      'solo leveling',
      'one piece',
      'naruto',
      'chainsaw',
    ];

    List mangas = [];
    for (final q in searchQueries) {
      evidence.searchQuery = q;
      evidence.step('SEARCH query="$q"');
      final search = await gql(
        'fetchSourceManga-SEARCH-$q',
        r'''
        mutation($source: LongString!, $q: String!) {
          fetchSourceManga(input: {
            source: $source
            type: SEARCH
            query: $q
            page: 1
          }) {
            mangas { id title thumbnailUrl inLibrary }
            hasNextPage
          }
        }
        ''',
        variables: {
          'source': evidence.sourceId,
          'q': q,
        },
      );
      mangas = (((search?['data'] as Map?)?['fetchSourceManga']
              as Map?)?['mangas'] as List?) ??
          [];
      evidence.step('SEARCH "$q" → ${mangas.length} titles');
      if (mangas.isNotEmpty) break;
      evidence.err('SEARCH "$q" returned 0 mangas');
    }

    if (mangas.isEmpty) {
      evidence.err('All SEARCH queries empty; trying POPULAR…');
      evidence.searchQuery = '(POPULAR page 1)';
      final search = await gql(
        'fetchSourceManga-POPULAR',
        r'''
        mutation($source: LongString!) {
          fetchSourceManga(input: {
            source: $source
            type: POPULAR
            page: 1
          }) {
            mangas { id title thumbnailUrl inLibrary }
            hasNextPage
          }
        }
        ''',
        variables: {'source': evidence.sourceId},
      );
      mangas = (((search?['data'] as Map?)?['fetchSourceManga']
              as Map?)?['mangas'] as List?) ??
          [];
    }

    if (mangas.isEmpty && installedPkg == preferredPkg) {
      evidence.err(
        'MangaDex yielded no titles — trying fallback extension…',
      );
      final alt = await _tryFallbackExtension(
        gql,
        evidence,
        extNodes,
        preferredPkg,
      );
      if (alt != null) {
        installedPkg = alt.$1;
        evidence.sourceId = alt.$2;
        evidence.sourceName = alt.$3;
        evidence.sourceLang = alt.$4;
        evidence.searchQuery = 'a';
        final search = await gql(
          'fetchSourceManga-SEARCH-fallback',
          r'''
          mutation($source: LongString!, $q: String!) {
            fetchSourceManga(input: {
              source: $source
              type: SEARCH
              query: $q
              page: 1
            }) {
              mangas { id title thumbnailUrl }
              hasNextPage
            }
          }
          ''',
          variables: {'source': evidence.sourceId, 'q': 'a'},
        );
        mangas = (((search?['data'] as Map?)?['fetchSourceManga']
                as Map?)?['mangas'] as List?) ??
            [];
      }
    }

    if (mangas.isEmpty) {
      evidence.err('Gate failed: no manga titles from any search path');
      await _finish(evidence, manager, writeDoc, exitCode: 7);
      return;
    }

    List chapterNodes = [];
    Map? chosenManga;
    for (final raw in mangas.take(8)) {
      if (raw is! Map) continue;
      final mid = raw['id'] is int
          ? raw['id'] as int
          : int.tryParse('${raw['id']}');
      if (mid == null) continue;
      evidence.step('Trying manga id=$mid title=${raw['title']}');

      final fetch = await gql(
        'fetchMangaAndChapters-$mid',
        r'''
        mutation($id: Int!) {
          fetchMangaAndChapters(input: {
            id: $id
            fetchManga: true
            fetchChapters: true
          }) {
            manga { id title status author artist description }
            chapters { id name chapterNumber pageCount sourceOrder scanlator }
          }
        }
        ''',
        variables: {'id': mid},
      );

      List fromMutation = [];
      if (fetch != null) {
        final payload =
            (fetch['data'] as Map?)?['fetchMangaAndChapters'] as Map?;
        final ch = payload?['chapters'];
        if (ch is List) fromMutation = ch;
      }

      final chQuery = await gql(
        'manga-chapters-$mid',
        r'''
        query($id: Int!) {
          manga(id: $id) {
            id
            title
            description
            author
            artist
            status
            thumbnailUrl
            sourceId
            chapters {
              nodes { id name chapterNumber pageCount sourceOrder scanlator }
              totalCount
            }
          }
        }
        ''',
        variables: {'id': mid},
      );

      List fromQuery = [];
      if (chQuery != null) {
        final m = ((chQuery['data'] as Map?)?['manga'] as Map?);
        final ch = m?['chapters'];
        if (ch is Map) {
          fromQuery = (ch['nodes'] as List?) ?? [];
        }
      }

      final nodes = fromMutation.isNotEmpty ? fromMutation : fromQuery;
      evidence.step(
        'Manga $mid chapters mutation=${fromMutation.length} '
        'query=${fromQuery.length}',
      );
      if (nodes.isNotEmpty) {
        chosenManga = raw;
        chapterNodes = nodes;
        evidence.mangaId = mid;
        evidence.mangaTitle = '${raw['title']}';
        evidence.chapterCount = nodes.length;
        final detailsManga =
            ((chQuery?['data'] as Map?)?['manga'] as Map?) ??
                (((fetch?['data'] as Map?)?['fetchMangaAndChapters']
                        as Map?)?['manga'] as Map?);
        evidence.step('Details: $detailsManga');
        break;
      }
      evidence.err('Manga $mid (${raw['title']}) has 0 chapters — skip');
    }

    if (chosenManga == null || chapterNodes.isEmpty) {
      evidence.err('No manga with chapters among search results');
      await _finish(evidence, manager, writeDoc, exitCode: 8);
      return;
    }

    evidence.step(
      'Selected manga id=${evidence.mangaId} title=${evidence.mangaTitle} '
      'chapters=${evidence.chapterCount}',
    );

    final chapter = chapterNodes.first as Map;
    evidence.chapterId = chapter['id'] is int
        ? chapter['id'] as int
        : int.tryParse('${chapter['id']}');
    evidence.chapterName = '${chapter['name']}';
    evidence.step(
      'Selected chapter id=${evidence.chapterId} name=${evidence.chapterName}',
    );

    final pagesPayload = await gql(
      'fetchChapterPages',
      r'''
      mutation($id: Int!) {
        fetchChapterPages(input: { chapterId: $id }) {
          pages
          chapter { id name pageCount }
        }
      }
      ''',
      variables: {'id': evidence.chapterId},
    );

    final payload =
        ((pagesPayload?['data'] as Map?)?['fetchChapterPages'] as Map?);
    final pagesRaw = payload?['pages'];
    if (pagesRaw is List) {
      for (final item in pagesRaw) {
        if (item is String && item.isNotEmpty) {
          evidence.pageUrls.add(item);
        } else if (item is Map) {
          final url = item['url'] ?? item['imageUrl'] ?? item['path'];
          if (url != null && '$url'.isNotEmpty) {
            evidence.pageUrls.add('$url');
          }
        }
      }
    }
    evidence.pageCount = evidence.pageUrls.length;
    evidence.step(
      'Pages count=${evidence.pageCount} '
      'sample=${evidence.pageUrls.take(3).toList()} '
      'chapterMeta=${payload?['chapter']}',
    );

    // Validate at least one page is fetchable as image bytes from loopback.
    if (evidence.pageUrls.isNotEmpty) {
      final first = evidence.pageUrls.first;
      final path = first.startsWith('http')
          ? Uri.parse(first).path
          : (first.startsWith('/') ? first : '/$first');
      try {
        final img = await client.restGet(path);
        evidence.step(
          'Page GET $path → HTTP ${img.statusCode} '
          'bytes=${img.bodyBytes.length} '
          'content-type=${img.headers['content-type']}',
        );
        if (img.statusCode >= 200 &&
            img.statusCode < 300 &&
            img.bodyBytes.length > 100) {
          evidence.pagesGatePassed = true;
          evidence.step(
            'GATE: real page image payload confirmed '
            '(${img.bodyBytes.length} bytes)',
          );
        } else {
          evidence.err(
            'Page HTTP ${img.statusCode} bytes=${img.bodyBytes.length} '
            'insufficient',
          );
        }
      } catch (e) {
        evidence.err('Page image fetch error: $e');
      }
    }

    if (!evidence.pagesGatePassed) {
      evidence.err('GATE FAIL: no page URLs / image payload');
    }

    await _finish(
      evidence,
      manager,
      writeDoc,
      exitCode: evidence.pagesGatePassed ? 0 : 9,
    );
  } catch (e, st) {
    evidence.err('Unhandled: $e\n$st');
    await _finish(evidence, manager, writeDoc, exitCode: 99);
  }
}

Future<(String, String, String, String)?> _tryFallbackExtension(
  Future<Map<String, dynamic>?> Function(
    String,
    String, {
    Map<String, dynamic>? variables,
  }) gql,
  GateEvidence evidence,
  List extNodes,
  String alreadyInstalled,
) async {
  for (final hint in fallbackPkgHints) {
    Map? cand;
    for (final n in extNodes.whereType<Map<Object?, Object?>>()) {
      if (n['pkgName'] == hint) {
        cand = n;
        break;
      }
    }
    if (cand == null) continue;
    final pkg = '${cand['pkgName']}';
    evidence.step('Fallback install $pkg (MangaDex path failed)');
    final inst = await gql(
      'fallback-install-$pkg',
      r'''
      mutation($id: String!) {
        updateExtension(input: { id: $id, patch: { install: true } }) {
          extension { pkgName name isInstalled }
        }
      }
      ''',
      variables: {'id': pkg},
    );
    final ext = ((inst?['data'] as Map?)?['updateExtension']
        as Map?)?['extension'] as Map?;
    if (ext == null || ext['isInstalled'] != true) {
      evidence.err('Fallback install failed for $pkg');
      continue;
    }
    evidence.extensionPkg = pkg;
    evidence.extensionName = '${ext['name']}';
    await Future<void>.delayed(const Duration(seconds: 3));
    final sources = await gql(
      'fallback-sources',
      r'''
      query {
        sources { nodes { id name lang } }
      }
      ''',
    );
    final nodes =
        (((sources?['data'] as Map?)?['sources'] as Map?)?['nodes'] as List?) ??
            [];
    for (final n in nodes.whereType<Map<Object?, Object?>>()) {
      if (n['id'].toString() == '0') continue;
      return (
        pkg,
        '${n['id']}',
        '${n['name']}',
        '${n['lang']}',
      );
    }
  }
  return null;
}

Future<void> _finish(
  GateEvidence evidence,
  SuwayomiProcessManager manager,
  bool writeDoc, {
  required int exitCode,
}) async {
  try {
    await manager.stop();
  } catch (_) {}
  await manager.dispose();

  if (writeDoc) {
    final doc = _renderDoc(evidence, exitCode);
    final out = File(
      p.join(Directory.current.path, 'docs', 'functional-gate-1.md'),
    );
    await out.writeAsString(doc);
    print('Wrote ${out.path}');
  }

  print(
    evidence.pagesGatePassed
        ? '=== GATE FUNCTIONAL #1 PASSED ==='
        : '=== GATE FUNCTIONAL #1 FAILED (exit $exitCode) ===',
  );
  exit(exitCode);
}

String _renderDoc(GateEvidence e, int exitCode) {
  final buf = StringBuffer()
    ..writeln('# Functional Gate #1 — Evidence')
    ..writeln()
    ..writeln(
      '**Result:** ${e.pagesGatePassed ? '✅ GREEN' : '❌ RED'} '
      '(exitCode=$exitCode)',
    )
    ..writeln()
    ..writeln('Generated: ${DateTime.now().toUtc().toIso8601String()} UTC')
    ..writeln()
    ..writeln('## Commands')
    ..writeln()
    ..writeln('```powershell')
    ..writeln(r'$env:Path = "C:\src\flutter\bin;" + $env:Path')
    ..writeln(r'cd C:\Users\joaop\Projetos\yomu')
    ..writeln('dart run tool/gate_functional_1.dart')
    ..writeln('```')
    ..writeln()
    ..writeln('## Environment')
    ..writeln()
    ..writeln('| Item | Value |')
    ..writeln('|------|-------|')
    ..writeln('| Suwayomi bind | `127.0.0.1:$kYomuSuwayomiPort` (loopback only) |')
    ..writeln('| About | ${e.aboutVersion ?? "—"} |')
    ..writeln('| Isolation | managed `server.rootDir` under temp Yomu gate dir |')
    ..writeln('| LAN exposure | none |')
    ..writeln()
    ..writeln('## Extension & source')
    ..writeln()
    ..writeln('| Item | Value |')
    ..writeln('|------|-------|')
    ..writeln('| Keiyoushi index | `$keiyoushiIndex` |')
    ..writeln('| Extension pkg | `${e.extensionPkg ?? "—"}` |')
    ..writeln('| Extension name | ${e.extensionName ?? "—"} |')
    ..writeln('| Source id | `${e.sourceId ?? "—"}` |')
    ..writeln('| Source name | ${e.sourceName ?? "—"} |')
    ..writeln('| Source lang | ${e.sourceLang ?? "—"} |')
    ..writeln()
    ..writeln('## Search')
    ..writeln()
    ..writeln('| Item | Value |')
    ..writeln('|------|-------|')
    ..writeln('| Query | `${e.searchQuery}` |')
    ..writeln(
      '| Mutation | `fetchSourceManga(input: { source, type: SEARCH, query, page })` |',
    )
    ..writeln()
    ..writeln('## Selected work')
    ..writeln()
    ..writeln('| Item | Value |')
    ..writeln('|------|-------|')
    ..writeln('| Manga id | `${e.mangaId ?? "—"}` |')
    ..writeln('| Title | ${e.mangaTitle ?? "—"} |')
    ..writeln('| Chapters | **${e.chapterCount}** |')
    ..writeln('| Chapter id | `${e.chapterId ?? "—"}` |')
    ..writeln('| Chapter name | ${e.chapterName ?? "—"} |')
    ..writeln('| Pages | **${e.pageCount}** |')
    ..writeln()
    ..writeln('### Page samples')
    ..writeln()
    ..writeln('```')
    ..writeln(
      e.pageUrls.isEmpty
          ? '(none)'
          : e.pageUrls.take(5).join('\n'),
    )
    ..writeln('```')
    ..writeln()
    ..writeln('## GraphQL fields / operations confirmed')
    ..writeln();
  for (final f in e.gqlFields) {
    buf.writeln('- `$f`');
  }
  buf
    ..writeln()
    ..writeln('## Steps log')
    ..writeln()
    ..writeln('```')
    ..writeln(e.steps.join('\n'))
    ..writeln('```')
    ..writeln()
    ..writeln('## Errors')
    ..writeln()
    ..writeln('```')
    ..writeln(e.errors.isEmpty ? '(none)' : e.errors.join('\n'))
    ..writeln('```')
    ..writeln()
    ..writeln('## Criterion')
    ..writeln()
    ..writeln(
      'Gate is green only if at least one real chapter page URL/payload '
      'is returned. pagesGatePassed=${e.pagesGatePassed}.',
    )
    ..writeln()
    ..writeln('## Out of scope (not run)')
    ..writeln()
    ..writeln('- Rich UI')
    ..writeln('- Maya')
    ..writeln('- Full PWA')
    ..writeln('- Source Builder');
  return buf.toString();
}
