# Status

## Gates

| Gate | Estado |
|------|--------|
| Funcional #1 — extensão → páginas | ✅ |
| Hard — biblioteca / progresso / downloads | ✅ |
| 1.5 — isolamento Suwayomi | ✅ |
| PWA iPhone mínima | ✅ |
| Maya mínima | ✅ |
| 2D — hardening lifecycle / LAN / Maya | ✅ |
| 2D.1 — reliability | ✅ |
| **2D.2 — JRE bundle + lifecycle/LAN/PWA edges** | ✅ código |
| **P0 — storage foundation (schema v1 `app_meta`)** | ✅ HEAD `941c4e8` |
| **Pós-P0 — promoção visual desktop + correções funcionais** | ✅ conteúdo deste checkpoint |
| **P1 — sessões/Auth no SQLite (schema v2)** | ✅ commit `c9d51d3` |
| **P2A — histórico/propostas Maya no SQLite (schema v3)** | ✅ commit `d200521` |
| **P2B — providers Maya (schema v4)** | ✅ gates aprovados |

## Phases

| Fase | Estado |
|------|--------|
| 2B–2C leitura + library | ✅ |
| PWA + Maya | ✅ |
| 2D / 2D.1 hardening | ✅ |
| P0 storage foundation | ✅ |
| Pós-P0 desktop visual + reader/explore/repos fixes | ✅ conteúdo deste checkpoint |
| P1 sessions/auth schema bump | ✅ commit `c9d51d3` |
| P2A Maya persistence schema bump | ✅ commit `d200521` |
| P2B Maya providers schema bump | ✅ validada |
| Source Builder | bloqueado |
| Histórico / settings / backup completos | placeholders |

## P2B — providers da Maya (2026-07-16, validada)

- Baseline separado: `master` / `d200521aa2735c9c245fe53123afe66208fc7404`
  (`feat(maya): persist history in SQLite`). A P2B contém somente o bump
  `3 → 4` e não mistura outra área de persistência.
- Drift migra explicitamente `3 → 4` e adiciona somente o singleton
  `maya_provider_settings`. A row contém modo, provider, modelo, flags e
  consentimento; nenhuma credencial entra no SQLite.
- A allowlist atual é OpenAI, Anthropic, Gemini e Ollama. A UI e os adapters
  exigem modelo explícito e usam endpoints fixos. OpenAI, Anthropic e Gemini
  guardam chaves no Windows Credential Manager; Ollama usa apenas
  `127.0.0.1:11434` sem credencial.
- Mensagem corrente exige consentimento cloud. Histórico recente e contexto da
  biblioteca possuem flags independentes e limites próprios. Falha de cofre,
  adapter, transporte ou provider não expõe erro cru e retorna ao engine local
  com fallback explícito.
- Intenções remotas são validadas contra o snapshot compartilhado e viram
  somente `ActionProposal` pendente. A confirmação explícita e a barreira
  durável at-most-once da P2A permanecem obrigatórias.
- A implementação inclui storage, WinCred, controlador, codecs/transport,
  adapters, UI e wiring do desktop. O `home_shell` cria o controlador com a
  factory real, injeta-o em `MayaService.llm` e `MayaScreen`, e o fecha pelo
  teardown da Maya. `OptionalMayaProviderBootstrap` preserva a Maya local se a
  camada opcional falhar.
- Falha ao carregar WinCred usa `UnavailableMayaCredentialStore`: modo local e
  Ollama continuam disponíveis, enquanto operações de chave cloud falham
  fechadas sem store alternativo inseguro. Trocas bloqueiam novas admissões
  antes de qualquer await; falhas de save restauram a chave anterior quando
  possível, e a remoção verifica todos os targets cloud antes de persistir o
  modo local.
- Validação atual: controller 22/22; conjunto de controller, adapters, codecs,
  transporte e WinCred 82/82; regressões promovidas da UI 17/17; `yomu_ai`
  62/62; `yomu_storage` 36/36; local server/Auth 38/38; desktop 171/171.
  Analyzer integral e `git diff --check` passaram. O
  `tool\verify_workspace.ps1` foi aprovado em 227,5 s e gerou o build Windows
  Debug em
  `apps/yomu_desktop/build/windows/x64/runner/Debug/yomu_desktop.exe`.
- `cmdkey /list` não encontrou target `app.yomu/maya/provider/*`. A auditoria
  adicional de 49 arquivos de DB/WAL/SHM/log/JSON e temporários de teste não
  encontrou padrões de API key plaintext; os testes direcionados também
  verificam bytes conhecidos no SQLite, WAL, SHM, lock e logs.
- Evidência visual externa:
  `%USERPROFILE%\Downloads\yomu-sol-final\2026-07-16\01-p2b-maya-provider-dialog.png`.
  É uma captura determinística do diálogo Flutter real antes de inserir chave;
  comprova layout, campos protegidos e separação dos consentimentos. O binding
  usa fonte de teste, portanto o PNG não é alegado como screenshot runtime com
  tipografia legível; o conteúdo textual é coberto pelas 17 regressões de UI.
- A referência desktop permaneceu imutável, SHA-256
  `8DCF41D7283CB16A70A9FA2E0F9D1CE05591F7165AB1AB4FB560D9246A387AC9`.
- Não houve chamada live a conta ou modelo externo. A validação dos providers
  usa transports determinísticos; disponibilidade, cobrança e política de
  retenção de contas reais não são certificadas por esta fase.
- Memória nova, autonomia, streaming, PWA/mobile e endpoints customizados
  permanecem fora desta subfase. O contrato factual completo está em
  `docs/p2b-maya-providers.md`.

## P2A — persistência da Maya (2026-07-15)

- Baseline separado: `master` / `9d17320d6dffaf61aeaf6ff40e5a476d48f8fb6d`
  (`docs: record completed P1 checkpoint`). Esta implementação integra somente
  o bump `2 → 3` e o escopo de persistência da Maya descrito abaixo.
- Drift migra explicitamente `2 → 3` e adiciona somente `maya_messages` e
  `maya_action_proposals`. Histórico, estado das propostas e ordenação são
  persistidos no SQLite Yomu; catálogo, capítulos e fatos de leitura continuam
  pertencendo exclusivamente ao Suwayomi.
- A confirmação é uma barreira durável at-most-once: o estado `confirmed` é
  persistido antes do efeito externo. Resultado ambíguo é exibido como não
  verificado e nunca sofre retry automático. Mutações e limpeza são
  serializadas; propostas já confirmadas impedem limpeza destrutiva por stores
  obsoletos.
- `maya_chat.json` é importado com transação, marker e fingerprint SHA-256. A
  leitura é limitada a 4 MiB + 1 byte; arquivos inválidos permanecem
  preservados. Captura, publicação, compatibilidade pré-nonce e restore usam
  move atômico no-replace no Windows; restart retoma estados intermediários sem
  sobrescrever destinos nem duplicar mensagens.
- Prova runtime atual sobre cópia temporária do JSON real: schema v3, quatro
  mensagens e zero propostas; archive com o mesmo SHA-256 do original; segundo
  open manteve marker e contagens sem duplicação. O original permaneceu byte a
  byte e com metadata inalterada. Todos os temporários criados para a prova
  foram removidos.
- Validação atual: `yomu_ai` 54/54, `yomu_storage` 33/33, local server/Auth
  38/38, desktop 84/84, core 3/3 e Suwayomi 42/42. Analyzer completo, PWA
  preload/reader race e `git diff --check` passaram; o
  `tool\verify_workspace.ps1` foi aprovado em 144 s e gerou o build Windows
  Debug em
  `apps/yomu_desktop/build/windows/x64/runner/Debug/yomu_desktop.exe`.
- Evidência visual atual:
  `%USERPROFILE%\Downloads\yomu-sol-final\2026-07-15`, cobrindo histórico
  disponível com engine offline, confirmação não verificada sem retry e
  migração bloqueada com mensagem sanitizada.
- A referência desktop permaneceu imutável, SHA-256
  `8DCF41D7283CB16A70A9FA2E0F9D1CE05591F7165AB1AB4FB560D9246A387AC9`.
- P2A não transforma o engine heurístico em LLM nem adiciona providers. Essa
  capacidade permanece em subfase posterior própria, com plano e aprovação
  separados.

## P1 — sessões e autenticação (2026-07-15)

- Baseline separado: `master` / `3615126762a07427930d5579774d6b7941780baa`
  (`feat: finalize post-p0 desktop checkpoint`), filho direto do P0. P1 foi
  commitada separadamente em `c9d51d3`.
- Drift migra explicitamente `1 → 2`, preserva `app_meta` e adiciona somente
  `device_sessions`. `session_id` é a primary key; `token_hash` é `NOT NULL`,
  `UNIQUE` e protegido no próprio SQLite por `CHECK` de SHA-256 lowercase.
- O bearer de 256 bits é retornado apenas no claim. `DeviceSession`, UI,
  revogação e tickets de mídia usam um `sessionId` aleatório independente;
  token plaintext não é persistido nem incluído em erros Auth.
- `device_sessions.json` é validado e importado com marker e inserts na mesma
  transação. A fonte tem limite de 4 MiB, fingerprint SHA-256 e só é removida
  após commit/readback. JSON ausente, vazio, malformado, duplicado e residual
  após crash possuem políticas conservadoras documentadas em
  `docs/p1-session-persistence.md`.
- Mutações Auth são serializadas. Pairing/restart, revogação individual e total,
  expiração, concorrência e `close()` com writes pendentes têm regressão. O
  bootstrap executa storage → Auth → serviços; teardown executa HTTP → Auth
  drain → Suwayomi → SQLite.
- Validação atual: storage 27/27, local server/Auth 38/38, desktop 77/77,
  analyzer completo limpo e `tool\verify_workspace.ps1` aprovado em 197,4 s.
  O verifier também aprovou core 3/3, Suwayomi 42/42, Maya 8/8, PWA e o build
  Windows Debug em
  `apps/yomu_desktop/build/windows/x64/runner/Debug/yomu_desktop.exe`.
- O executável não foi iniciado contra `%APPDATA%` real: isso dispararia a
  migração e remoção deliberada do JSON legado. A prova runtime desta fase usa
  bancos e diretórios temporários. Não houve alteração visual de layout que
  exigisse nova evidência por screenshot.
- A referência desktop permaneceu imutável, SHA-256
  `8DCF41D7283CB16A70A9FA2E0F9D1CE05591F7165AB1AB4FB560D9246A387AC9`.

## Checkpoint pós-P0 (2026-07-14)

- Baseline de origem: `master` / `941c4e84efc78f5e082abd817d9790b8694dd12a` (`feat: complete p0 persistent storage foundation`). Este commit encerra separadamente o checkpoint pós-P0; P1 não integra este conteúdo.
- P0 permanece o baseline committed: bootstrap storage-first, schema Drift v1 somente com `app_meta`, lock exclusivo e fronteira dual-DB intacta. P1, P2+, Android, redesign PWA e Source Builder não foram iniciados.
- Leitor: a fila de progresso separa pendências por capítulo e mantém high-water monotônico, inclusive em A→B→A com save lento; snapshots capturam `chapterId`, página, total e estado lido; a ordem usa `sourceOrder`; transições duplicadas são bloqueadas; double-page usa spreads sobrepostos e página seguinte à esquerda; vertical/webtoon determinam a página visível por posições reais de `RenderBox`.
- Explore/extensões: fontes, catálogo, busca e paginação têm ownership/gates independentes; respostas antigas e load-more duplicado são rejeitados; fontes são recarregadas após instalação; stores e catálogo carregam de forma independente; confiança Keiyoushi usa URLs oficiais.
- Lifecycle/Auth/Suwayomi: callbacks de health/teardown rejeitam estado obsoleto; persistência de sessões é serializada; `stop()` preserva identidade/handle até saída confirmada e sinaliza estado não saudável quando a saída não é comprovada.
- Saída Windows: a auditoria reproduziu um fechamento normal que encerrou o Yomu, mas deixou o Java Suwayomi de ownership comprovado vivo por mais de 75 s. A causa preexistia no P0: `detached`/`dispose` iniciavam teardown assíncrono sem handshake aguardável. A correção estreita autorizada implementa `didRequestAppExit()` e segura `AppExitResponse.exit` até o teardown serializado terminar; pedidos repetidos compartilham a mesma operação.
- Status Core/Motor: o rodapé deriva a disponibilidade do servidor Yomu realmente vinculado; se o HTTP estiver ausente após falha de restart, informa Core indisponível mesmo que o Suwayomi continue `running`. Um teste de regressão cobre os estados disponível e ausente.
- Validação de fechamento executada em 2026-07-14: `flutter analyze` e `dart analyze` limpos; `tool\verify_workspace.ps1` aprovado em 168,7 s; core 3/3, Suwayomi 42/42, local server/Auth 27/27, Maya 8/8, `yomu_storage` 23/23, PWA preload/reader race aprovados e desktop 74/74; build Windows Debug gerado em `apps\yomu_desktop\build\windows\x64\runner\Debug\yomu_desktop.exe`; `git diff --check` aprovado.
- Prova runtime no bundle final: Yomu PID 24440 iniciou Java PID 41760 (`runId=c61ce4843ac65fd8`) somente em `127.0.0.1:14567`; `CloseMainWindow()` encerrou ambos em 9,028 s, liberou `14567`/`8787` e removeu a identidade. Nenhum processo foi encerrado à força.
- Evidência visual atual: `C:\Users\joaop\Downloads\yomu-sol-final\2026-07-14`. Não usar `03-server-after-start.png`, contaminada por terminal. `23-final-build-server-running.png` registra o bundle final com Suwayomi real ativo; `24-core-unavailable-widget-proof.png` registra a prova widget externa do estado Core indisponível, sem manipular processos ou portas.
- O leitor foi comprovado com dados reais na página 5/48, incluindo resume, menu de modo, vertical, double-page e webtoon. O painel de fim tem prova widget determinística, mas não foi forçado em runtime para evitar alterar progresso/`isRead` do usuário.
- A referência desktop permaneceu imutável, SHA-256 `8DCF41D7283CB16A70A9FA2E0F9D1CE05591F7165AB1AB4FB560D9246A387AC9`.

## Validação

```powershell
powershell -ExecutionPolicy Bypass -File tool/verify_workspace.ps1
```

## Limitações restantes

- Ownership via PowerShell/CIM (command line ilegível → não mata)
- DNS rebinding TOCTOU residual entre resolve e TCP connect
- PWA HTTP só em LAN confiável (HTTPS na fase PWA final)
- A evidência visual atual cobre telas e modos principais, mas não todos os estados de loading/erro, menus, tooltips, foco e animações; não há alegação de fidelidade 1:1.
- O painel de fim do leitor tem prova widget, não prova runtime atual; evitou-se alterar progresso/`isRead` real apenas para produzir screenshot.
- Cada autenticação persiste `last_seen_at_ms` em uma fila serial; comportamento
  correto, com custo de write a observar em uso LAN intenso.
- Source Builder permanece fora de escopo e na última fase.
