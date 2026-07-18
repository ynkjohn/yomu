# Yomu Architecture

The replaceable internal reading-engine boundary is defined by
[`adr/0001-yomu-reading-engine.md`](adr/0001-yomu-reading-engine.md). Suwayomi
is the current adapter implementation, not a product surface.

## Verdict

| Concern | Owner |
|---------|--------|
| Tachiyomi/Mihon/Keiyoushi extensions | **Suwayomi-Server** (managed process) |
| Own sources from a pasted URL | **Yomu Source Builder** (complementary, dual catalog) |
| Native UI, Maya, PWA, proxy, auth | **Yomu** |

## Processes

1. **Yomu Desktop** (Flutter native executable)
2. **Suwayomi-Server** (Java), spawned by Yomu, bound to **127.0.0.1 only**
3. **Yomu Core HTTP** (Shelf), loopback por padrão; bind LAN somente após
   opt-in, com autenticação e proxy para o Suwayomi

iPhone Safari/PWA talks **only** to Yomu Core.

## Offline engine distribution

Profile/Release resolve the unified `engine_manifest.json` only beside the
executable, execute only the packaged Temurin JRE and seed only the packaged
Suwayomi JAR. There is no system-Java or network fallback in publishable
builds. The bundle retains upstream JRE legal/notice files and Yomu third-party
notices.

Temurin redistribution uses GPLv2 section 3(a). The exact OpenJDK source,
Temurin build-source archive and official build provenance must be released as
separate assets in the same download location as every verified Yomu portable
ZIP containing that JRE. The exact Suwayomi source archive accompanies the
release under MPL-2.0. Installer formats fail closed until a content-aware gate
can inspect them. Binary and source archives are release inputs, never Git
contents.

## Migrated reading-engine capabilities

R3 migrates the first real desktop consumer: `LibraryScreen` receives only
`LibraryGateway`, `EngineMediaGateway`, `EngineReadinessSnapshot` and Yomu
models. The Suwayomi adapter maps protocol DTOs to `LibraryManga`, converts
process status to sanitized product readiness and represents covers with an
opaque `MediaReference`. Cover bytes are fetched only through the adapter with
an explicit 8 MiB consumer limit and redirects disabled.

R4 migrates Yomu Core/PWA reading routes to Yomu-owned details, reader,
progress, catalog and media gateways. `yomu_local_server` no longer imports or
depends directly on `yomu_suwayomi`; `HomeShell` composes the concrete adapter,
the existing library/readiness adapters and the SSRF-safe external fetcher.
The authenticated `/api/v1` paths, methods and JSON remain compatible.
`engineReady` is the product readiness key while `suwayomiReady` and
`suwayomi` remain temporary wire aliases.

Chapter-page and ticket identities stay opaque. Core media responses are
bounded at 40 MiB, external media at 25 MiB, relative redirects are refused and
external redirects are revalidated by the pinned-IP SSRF-safe fetcher. Provider
exceptions cross the HTTP boundary only as sanitized `upstream_error` 502
responses. Source id `0` is filtered inside the adapter.

R5 moves the remaining read-only desktop consumers to the same boundary.
`HomeScreen`, `MangaDetailScreen`, `ExploreScreen` and `ExtensionsScreen`
receive only Yomu gateways and models. Search, popular and latest catalogs
share a normalized `CatalogPage` with explicit pagination and `hasNextPage`;
source icons, covers and extension identities remain opaque. Desktop media is
rendered from bounded adapter bytes, never from an engine URL.

Repository trust, the recommended extension and supplier package identifiers
are private policy of `SuwayomiExtensionsAdapter`. Chapter refresh and the
temporary reader/download callbacks are composed only by `HomeShell`. The
reader, progress, downloads and Maya mutation surfaces remain the R6 slice;
R5 does not move data ownership or change SQLite schema v5.

## Dual catalog (Source Builder)

- Extension sources: runtime = Suwayomi; appear in Suwayomi UI/API.
- SourceSpec sources: runtime = Yomu; **do not** appear in Suwayomi in the MVP.
- Spec Bridge Extension = future evolution.

## Dual database

- Suwayomi: library, chapters, pages, downloads, main progress, extensions.
- Yomu SQLite implementado: meta do app, sessões, histórico/propostas da Maya e
  configuração não secreta de provider da Maya, incluindo o perfil de endpoint
  OpenAI-compatible no schema v5.
- Extras futuros do Yomu, como status pessoal, SourceSpecs e analytics, exigem
  ownership confirmado e schema bump próprio antes de serem persistidos.

Modelo conceitual candidato para status pessoal: Suwayomi = facts; Yomu =
intention; conflitos seriam visíveis. Ownership e persistência dependem de
auditoria e aprovação futura.

## Maya e providers opcionais

A Maya permanece local-first. Providers cloud são adapters opcionais do
desktop Flutter nativo; eles não passam pelo Yomu Core, pela PWA ou pelo banco
Suwayomi. OpenAI, Anthropic e Gemini usam HTTPS para destinos fixos e chaves no
Windows Credential Manager. Ollama usa somente
`http://127.0.0.1:11434/api/chat` e não possui credencial. A P2C adiciona um
único perfil OpenAI-compatible via Chat Completions, com endpoint e modelo
explícitos e API key opcional.

O SQLite Yomu guarda apenas provider, modelo explícito, estado habilitado,
flags de contexto e consentimento. Contexto é montado por requisição dentro de
limites e vinculado por lease opaco à configuração que o autorizou; contexto
obsoleto é rejeitado antes do adapter. Falha de provider volta explicitamente
ao engine local. Tool calls remotos são dados
não confiáveis e só podem resultar em `ActionProposal` local pendente, ainda
sujeito à confirmação explícita e à barreira at-most-once da P2A.

O perfil custom é persistido separadamente no singleton não secreto
`maya_custom_provider_settings`. HTTPS aceita apenas destinos públicos; HTTP é
restrito a IP loopback literal. DNS é validado em cada requisição, o socket
conecta ao IP aprovado e TLS usa o hostname original para SNI/certificado.
Queries, fragmentos, userinfo, redirects, proxies, headers e bodies arbitrários
são bloqueados. Chaves custom são vinculadas ao SHA-256 do endpoint canônico no
WinCred.

Não há streaming, memória nova, autonomia ou integração PWA. Os contratos
detalhados estão em `docs/p2b-maya-providers.md` e
`docs/p2c-maya-custom-provider.md`.

## Hard gates (done)

1. Suwayomi start/health/stop
2. Keiyoushi → install extension → search → details → chapters → pages
3. Desktop reader + progress save/resume
4. Library / downloads (hard gate)
5. PWA mínima (LAN opt-in + pairing + library/reader)
6. Maya persistente + providers opcionais + ActionProposal — **done**
7. P2C custom OpenAI-compatible, schema v5 — **published in `eda852b`**

P2B concluída no código: schema v4 e providers compostos no bootstrap desktop.
O controlador usa a factory real, é injetado no
`MayaService` e na `MayaScreen`, e permanece opcional por
`OptionalMayaProviderBootstrap`. Se o WinCred não carregar, um store
indisponível mantém local/Ollama e bloqueia credenciais cloud sem fallback
inseguro. A prova live de compatibilidade com cada serviço externo não faz
parte dos gates certificados desta fase.

A P2C foi concluída e publicada no commit separado `eda852b`, com o único bump
`4 → 5`; o handoff pós-P2C foi publicado em `673734b`. Source Builder permanece
reservado para a última fase.
