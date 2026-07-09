# Suwayomi API Matrix

Pinned: `Suwayomi-Server-v2.3.2238.jar` (`v2.3.2238-r2238`,  
sha256 `9ee45c37dac659a284e4a1885dcddec54a7018ead2f18620bcb1fd29751c9786`).

Probed on **isolated** Yomu-managed Suwayomi (`127.0.0.1:14567`,  
`-Dsuwayomi.tachidesk.config.server.rootDir=<managed>`).  
Tools: `tool/smoke_suwayomi.dart`, `tool/probe_store2.dart`, `tool/probe_suwayomi_api.dart`.

**Hard rules:** never patch `%LOCALAPPDATA%\Tachidesk`. Do not build rich UI for rows still `unsupported` without a documented fallback.

## Summary table

| Capability | Status | Endpoint / probe | Notes | Fallback |
|------------|--------|------------------|-------|----------|
| Health / about | `supported` | `GET /api/v1/settings/about` | version + revision | GraphQL `{ aboutServer }` also exists |
| Extension repositories / stores list | `supported` | `query { extensionStores { nodes { name indexUrl isLegacy } } }` | Mihon **Extension Store** model (not only legacy repos) | — |
| Extension repositories / stores add | `supported` | `mutation addExtensionStore(input: { indexUrl })` | Keiyoushi URL accepted; server may rewrite to `index.pb` CDN | Legacy: `setSettings.extensionRepos` still works but **does not populate catalog alone** |
| Refresh extension catalog | `supported` | `mutation fetchExtensions(input: {})` | Returns full list (1353 with Keiyoushi) | — |
| List extensions | `supported` | `query { extensions { nodes { pkgName name isInstalled … } totalCount } }` | **No `id` field** on `ExtensionType`; identity is `pkgName` | REST `GET /api/v1/extension/list` |
| Install extension | `supported` | `mutation updateExtension(input: { id: pkgName, patch: { install: true } })` | `id` is **String** (pkgName). Confirmed: MangaDex installed | — |
| Update extension | `supported` | `updateExtension(..., patch: { update: true })` | Same mutation family (`UpdateExtensionPatchInput`) | — |
| Uninstall / remove extension | `supported` | `updateExtension(..., patch: { uninstall: true })` | Same mutation family | — |
| Sources list | `supported` | `query { sources { nodes { id name lang } } }` | After install, MangaDex sources appear | REST `GET /api/v1/source/list` |
| Source by id | `supported` | `query source(id: LongString!)` | — | — |
| Source preferences | `supported` | `source { preferences { __typename … } }` | Field names differ from older forks | Defer advanced UI if needed |
| Search / catalog | `supported` | **`mutation`** `fetchSourceManga(input: { source, type: SEARCH\|POPULAR\|LATEST, query, page })` | Confirmed SEARCH returns mangas with ids | Not a Query field in this build |
| Manga details | `supported` | `query manga(id: Int!)` | Confirmed E2E Gate #1 | — |
| Chapters | `supported` | `mutation fetchMangaAndChapters` then `manga { chapters { nodes { id name … } totalCount } }` | Confirmed: 3 chapters on MangaDex EN work; some titles return "No chapters found" | Skip empty titles; try next search hit |
| Pages | `supported` | `mutation fetchChapterPages` → list of `/api/v1/manga/{m}/chapter/{c}/page/{i}` | Confirmed: 93 page URLs; GET page/0 → `image/jpeg` ~466KB | — |
| Progress get/set | `supported` | `mutation updateChapter(input: { id, patch: { lastPageRead, isRead } })`; `query chapter(id)` | Used in Phase 2C reader resume/save | — |
| Library list | `supported` | `query mangas(condition: { inLibrary: true })` | Fallback: list all + filter | — |
| Library add/remove | `supported` | `mutation updateManga(input: { id, patch: { inLibrary } })` | Phase 2C detail screen | — |
| Downloads | `supported` | `query downloadStatus`; `enqueueChapterDownloads` / dequeue / clear / start / stop | Phase 2C downloads UI | — |

## Confirmed GraphQL patterns (v2.3.2238)

### Add Keiyoushi store

```graphql
mutation($url: String!) {
  addExtensionStore(input: { indexUrl: $url }) {
    extensionStore { name indexUrl isLegacy }
  }
}
```

Trusted URL:

```text
https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json
```

Server may normalize to protobuf index, e.g.  
`https://cdn.jsdelivr.net/gh/keiyoushi/extensions@repo/index.pb`.

### Fetch + list + install

```graphql
mutation { fetchExtensions(input: {}) {
  extensions { pkgName name isInstalled lang }
}}

query { extensions {
  nodes { pkgName name isInstalled versionName lang apkName }
  totalCount
}}

mutation($id: String!) {
  updateExtension(input: { id: $id, patch: { install: true } }) {
    extension { pkgName isInstalled name }
  }
}
# patch: { update: true } | { uninstall: true }
```

### Search

```graphql
mutation($source: LongString!) {
  fetchSourceManga(input: {
    source: $source
    type: SEARCH
    query: "one"
    page: 1
  }) {
    mangas { id title }
    hasNextPage
  }
}
```

## REST notes

| Path | Result |
|------|--------|
| `GET /api/v1/extension/list` | 200 (empty until stores fetched) |
| `GET /api/v1/source/list` | 200 |
| `GET /api/v1/update/recentChapters/1` | 200 |
| `GET /api/v1/manga/list` | 404 (use GraphQL library queries) |
| `GET /api/v1/extension/install/{pkg}` | 404 (use GraphQL install) |

## Isolation (prerequisite)

| Item | Value |
|------|--------|
| JVM property | `suwayomi.tachidesk.config.server.rootDir` **before** `-jar` |
| Port | `14567` loopback |
| Data | `{appSupport}/yomu/data/suwayomi` only |
| Global AppData | **never** patched |

Gate 1.5: `dart run tool/smoke_suwayomi.dart`  
Aggressive: `dart run tool/smoke_suwayomi.dart --aggressive-rename`

## Re-probe

```powershell
$env:Path = "C:\src\flutter\bin;" + $env:Path
cd C:\Users\joaop\Projetos\yomu
dart run tool/probe_store2.dart
```

## Gate funcional #1

See `docs/functional-gate-1.md` and `dart run tool/gate_functional_1.dart`.

**Status: GREEN** — MangaDex EN → search → chapters → pages → real JPEG bytes.

Notes from gate:
- Prefer multi-hit search (`berserk`, etc.); some MangaDex hits have zero chapters.
- `fetchMangaAndChapters` may error with `No chapters found` for empty titles — try next manga.
- Page list is relative API paths under loopback; GET returns `image/jpeg`.
