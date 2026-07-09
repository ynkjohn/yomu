# Functional Gate #1 — Evidence

**Result:** ✅ GREEN (exitCode=0)

Generated: 2026-07-09T18:40:36.127097Z UTC

## Commands

```powershell
$env:Path = "C:\src\flutter\bin;" + $env:Path
cd C:\Users\joaop\Projetos\yomu
dart run tool/gate_functional_1.dart
```

## Environment

| Item | Value |
|------|-------|
| Suwayomi bind | `127.0.0.1:14567` (loopback only) |
| About | v2.3.2238 / r2238 |
| Isolation | managed `server.rootDir` under temp Yomu gate dir |
| LAN exposure | none |

## Extension & source

| Item | Value |
|------|-------|
| Keiyoushi index | `https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json` |
| Extension pkg | `eu.kanade.tachiyomi.extension.all.mangadex` |
| Extension name | MangaDex |
| Source id | `2499283573021220255` |
| Source name | MangaDex |
| Source lang | en |

## Search

| Item | Value |
|------|-------|
| Query | `berserk` |
| Mutation | `fetchSourceManga(input: { source, type: SEARCH, query, page })` |

## Selected work

| Item | Value |
|------|-------|
| Manga id | `1` |
| Title | VRMMO Chronicles of a Solo Cleric ~Surprise! I’m Actually a Berserker!~ |
| Chapters | **3** |
| Chapter id | `1` |
| Chapter name | Ch.1 |
| Pages | **93** |

### Page samples

```
/api/v1/manga/1/chapter/1/page/0
/api/v1/manga/1/chapter/1/page/1
/api/v1/manga/1/chapter/1/page/2
/api/v1/manga/1/chapter/1/page/3
/api/v1/manga/1/chapter/1/page/4
```

## GraphQL fields / operations confirmed

- `addExtensionStore(input: { indexUrl })`
- `extensionStores { nodes { name indexUrl isLegacy } }`
- `fetchExtensions(input: {})`
- `extensions { nodes { pkgName name isInstalled versionName lang } }`
- `updateExtension(input: { id: pkgName, patch: { install: true } })`
- `sources { nodes { id name lang } }`
- `fetchSourceManga(input: { source, type: SEARCH, query, page })`
- `fetchMangaAndChapters(input: { id, fetchManga, fetchChapters })`
- `fetchChapterPages(input: { chapterId }) { pages }`
- `manga(id) { chapters { nodes { id name chapterNumber pageCount } } }`

## Steps log

```
Start Suwayomi managed @ 127.0.0.1:14567 rootDir=C:\Users\joaop\AppData\Local\Temp\yomu-gate-functional-1\data\suwayomi
Start status: running baseUrl=http://127.0.0.1:14567
Isolation OK observedRoot=C:\Users\joaop\AppData\Local\Temp\yomu-gate-functional-1\data\suwayomi
About: v2.3.2238 / r2238
GQL OK: addExtensionStore
GQL OK: extensionStores
Stores total=1 nodes=1 detail=[{name: Keiyoushi, indexUrl: https://cdn.jsdelivr.net/gh/keiyoushi/extensions@repo/index.pb, isLegacy: false}]
GQL OK: fetchExtensions
fetchExtensions returned 1353 extensions
GQL OK: extensions
extensions totalCount=1353 nodes=1353
Trying install pkg=eu.kanade.tachiyomi.extension.all.mangadex name=MangaDex
GQL OK: install-eu.kanade.tachiyomi.extension.all.mangadex
Installed OK: {pkgName: eu.kanade.tachiyomi.extension.all.mangadex, name: MangaDex, isInstalled: true, versionName: 1.4.211, lang: all}
GQL OK: sources
Sources total=62 nodes=62
Using source id=2499283573021220255 name=MangaDex lang=en
SEARCH query="berserk"
GQL OK: fetchSourceManga-SEARCH-berserk
SEARCH "berserk" → 19 titles
Trying manga id=1 title=VRMMO Chronicles of a Solo Cleric ~Surprise! I’m Actually a Berserker!~
GQL OK: fetchMangaAndChapters-1
GQL OK: manga-chapters-1
Manga 1 chapters mutation=3 query=3
Details: {id: 1, title: VRMMO Chronicles of a Solo Cleric ~Surprise! I’m Actually a Berserker!~, description: ~ No matter how you look at it, It’s a berserker! Thank you so much~
The high schooler Ryuu has started playing the popular VRMMORPG [Fantasic Epoch Online] FEO. He choose to be a priest because of their ability to heal themselves and hence won’t require a party. Even though he was just enjoying the game in his own way, he equips 2 maces and is even able to defeat monsters with his bare hands. His playstyle has made other players to be terrified of him! There’s no way we can take our eyes of this priest! The start of the Solo Player Priest (LUL) Journey!, author: Digishoku, artist: Digishoku, status: ONGOING, thumbnailUrl: /api/v1/manga/1/thumbnail, sourceId: 2499283573021220255, chapters: {nodes: [{id: 1, name: Ch.1, chapterNumber: 1.0, pageCount: -1, sourceOrder: 1, scanlator: Lyra Scans}, {id: 2, name: Ch.2, chapterNumber: 2.0, pageCount: -1, sourceOrder: 2, scanlator: Lyra Scans}, {id: 3, name: Ch.3, chapterNumber: 3.0, pageCount: -1, sourceOrder: 3, scanlator: Lyra Scans}], totalCount: 3}}
Selected manga id=1 title=VRMMO Chronicles of a Solo Cleric ~Surprise! I’m Actually a Berserker!~ chapters=3
Selected chapter id=1 name=Ch.1
GQL OK: fetchChapterPages
Pages count=93 sample=[/api/v1/manga/1/chapter/1/page/0, /api/v1/manga/1/chapter/1/page/1, /api/v1/manga/1/chapter/1/page/2] chapterMeta={id: 1, name: Ch.1, pageCount: 93}
Page GET /api/v1/manga/1/chapter/1/page/0 → HTTP 200 bytes=465941 content-type=image/jpeg
GATE: real page image payload confirmed (465941 bytes)
```

## Errors

```
(none)
```

## Criterion

Gate is green only if at least one real chapter page URL/payload is returned. pagesGatePassed=true.

## Out of scope (not run)

- Rich UI
- Maya
- Full PWA
- Source Builder
