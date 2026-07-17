# Yomu Architecture

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
7. P2C custom OpenAI-compatible, schema v5 — **implemented; commit pending**

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
