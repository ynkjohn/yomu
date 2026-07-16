# Yomu — handoff atual

Snapshot factual preparado em 2026-07-16 para retomada em uma nova conversa.
Toda nova sessão deve revalidar o estado; código, diff e comportamento atual
prevalecem sobre este documento.

## Retomada obrigatória

Execute primeiro:

```powershell
Set-Location 'C:\Users\joaop\Projetos\yomu'
git rev-parse --show-toplevel
Get-Content -Raw AGENTS.md
Get-Content -Raw docs\current-handoff.md
git status --short --untracked-files=all
```

Não acesse `C:\Users\joaop\Projetos\multiyomi`.

## Repositório e baseline

- Repositório: `C:\Users\joaop\Projetos\yomu`.
- Branch: `master`.
- Remoto: `https://github.com/ynkjohn/yomu.git`.
- HEAD local, `origin/master` e `ls-remote origin master` na auditoria:
  `7a35094b80b9359327c49e198258fc3c3d255571`.
- Divergência auditada: zero ahead, zero behind.
- P0 `941c4e84efc78f5e082abd817d9790b8694dd12a` é ancestral do HEAD.

Commits após P0, em ordem:

1. `3615126762a07427930d5579774d6b7941780baa` —
   `feat: finalize post-p0 desktop checkpoint`;
2. `c9d51d3e94589ddb72a5d099d208cb66d25a0572` —
   `feat(auth): persist device sessions in SQLite`;
3. `9d17320d6dffaf61aeaf6ff40e5a476d48f8fb6d` —
   `docs: record completed P1 checkpoint`;
4. `d200521aa2735c9c245fe53123afe66208fc7404` —
   `feat(maya): persist history in SQLite`;
5. `7a35094b80b9359327c49e198258fc3c3d255571` —
   `feat(maya): add provider integrations`.

P0, checkpoint pós-P0, P1, P2A e P2B estão separados e publicados em
`origin/master`. Não reimplementar nem combinar essas fases.

## Working tree auditada antes deste handoff

- Staged: zero.
- Diff material unstaged: zero.
- Tracked status-only/EOL: 16.
- Untracked: 180, todos em áreas protegidas.
- Outros untracked: zero.

Classificação dos 180 untracked:

- 28 em `.playwright-cli/**`;
- 146 em `design_prod/**`;
- 6 em `mcps/tasks/tools/**`.

Os 16 tracked status-only/EOL são:

- `apps/yomu_desktop/.gitignore`;
- `apps/yomu_desktop/README.md`;
- `apps/yomu_desktop/analysis_options.yaml`;
- `apps/yomu_desktop/assets/vendor/manifest.json`;
- `apps/yomu_desktop/windows/.gitignore`;
- `apps/yomu_desktop/windows/CMakeLists.txt`;
- `apps/yomu_desktop/windows/flutter/CMakeLists.txt`;
- `apps/yomu_desktop/windows/runner/CMakeLists.txt`;
- `apps/yomu_desktop/windows/runner/Runner.rc`;
- `apps/yomu_desktop/windows/runner/flutter_window.cpp`;
- `apps/yomu_desktop/windows/runner/flutter_window.h`;
- `apps/yomu_desktop/windows/runner/resource.h`;
- `apps/yomu_desktop/windows/runner/runner.exe.manifest`;
- `apps/yomu_desktop/windows/runner/utils.cpp`;
- `apps/yomu_desktop/windows/runner/utils.h`;
- `packages/yomu_suwayomi/vendor/manifest.json`.

Eles não possuíam diff material e não devem entrar em allowlist apenas para
normalizar EOL.

Esta sessão de handoff altera somente documentação de contexto:
`AGENTS.md`, `README.md`, `apps/yomu_desktop/README.md`, `docs/status.md`,
`docs/architecture.md`, `docs/data-model.md`,
`docs/suwayomi-integration.md`, `docs/iphone-runbook.md`,
`docs/phase-maya-minima.md` e este arquivo. Essas mudanças permanecem
uncommitted até autorização explícita de staging e commit.

Relatórios de P1, P2A, P2B e fases anteriores são registros históricos e não
devem ser reescritos para fingir que recursos posteriores já existiam naquela
época. Para estado corrente, use primeiro este handoff e `docs/status.md`.

Estado esperado imediatamente após esta atualização documental:

- zero staged;
- nove tracked com diff material, todos documentação;
- 15 tracked status-only/EOL preservados;
- 181 untracked: os 180 artefatos protegidos originais mais este handoff;
- nenhum outro arquivo material.

Allowlist nominal proposta para um futuro commit exclusivamente documental:

- `AGENTS.md`;
- `README.md`;
- `apps/yomu_desktop/README.md`;
- `docs/architecture.md`;
- `docs/current-handoff.md`;
- `docs/data-model.md`;
- `docs/iphone-runbook.md`;
- `docs/phase-maya-minima.md`;
- `docs/status.md`;
- `docs/suwayomi-integration.md`.

Não stagear essa allowlist sem nova autorização explícita. Os 15 arquivos
status-only/EOL e os 180 artefatos protegidos ficam fora.

## Referências e runtime no snapshot

- `design_prod/**`, `.playwright-cli/**` e `mcps/tasks/tools/**` permanecem
  intocados e fora de qualquer commit.
- Referência desktop:
  `design_prod\design em producao.html`.
- SHA-256 confirmado:
  `8DCF41D7283CB16A70A9FA2E0F9D1CE05591F7165AB1AB4FB560D9246A387AC9`.
- Evidência P2B externa:
  `C:\Users\joaop\Downloads\yomu-sol-final\2026-07-16\01-p2b-maya-provider-dialog.png`.

Na auditoria deste handoff havia processos ativos, portanto não assuma portas
livres e não execute build sem revalidar:

- `yomu_desktop.exe` PID 44076, do build Debug deste repo, em
  `127.0.0.1:8787`;
- `java.exe` PID 39264, filho do Yomu, em `127.0.0.1:14567`;
- nenhum listener em `11434`;
- nenhum Dart, Flutter ou `flutter_tester` detectado.

Nenhum processo foi encerrado. PIDs são voláteis; confirme ownership novamente
antes de qualquer ação.

## Arquitetura que não pode ser alterada sem produto

- Desktop Flutter Windows nativo; sem Electron, WebView ou Python UI.
- Suwayomi-Server é o engine local e fica somente em `127.0.0.1:14567`.
- Yomu Core fica por padrão em `127.0.0.1:8787`; LAN/PWA é opt-in.
- Desktop é a fonte de verdade; iPhone usa PWA LAN; Android é futuro.
- Suwayomi DB é dono de catálogo, mangas, capítulos, páginas, downloads,
  progresso, read flags e fatos de leitura.
- Yomu SQLite guarda apenas dados específicos do app.
- Maya é opcional e local-first. Ações sensíveis exigem `ActionProposal` e
  confirmação explícita.
- Não usar Docker. Source Builder é a última fase.
- Versões fixas: Flutter 3.32.5, Dart 3.8.1, Drift 2.28.0 e sqlite3 2.9.4;
  sem `sqlite3_flutter_libs` e sem upgrades automáticos.

## Persistência concluída

O schema atual do SQLite Yomu é v4:

| Versão | Fase | Dados adicionados |
|--------|------|-------------------|
| v1 | P0 | `app_meta` |
| v2 | P1 | `device_sessions`, somente `token_hash` |
| v3 | P2A | `maya_messages`, `maya_action_proposals` |
| v4 | P2B | `maya_provider_settings`, sem credenciais |

P1 migra `device_sessions.json` de forma transacional, idempotente e
conservadora. P2A migra `maya_chat.json`, preserva estados ambíguos contra
reexecução e mantém a barreira durável at-most-once de `ActionProposal`.
Detalhes normativos estão em `docs/p1-session-persistence.md` e
`docs/p2a-maya-persistence.md`.

## P2B concluída — Maya com providers reais

A Maya não é mais somente o engine heurístico: o desktop pode usar OpenAI,
Anthropic, Gemini ou Ollama como providers opcionais. O fallback local continua
explícito e obrigatório diante de falha ou configuração inválida.

Propriedades implementadas:

- endpoints fixos para os quatro providers;
- OpenAI, Anthropic e Gemini via HTTPS;
- Ollama somente em `127.0.0.1:11434`;
- API keys cloud somente no Windows Credential Manager;
- nenhuma credencial plaintext no SQLite, WAL, SHM, JSON, logs ou erros;
- modelo explícito e consentimentos separados para mensagem, histórico e
  biblioteca;
- lease opaco invalida contexto preparado sob configuração antiga;
- tools remotas restritas a `openManga` e `downloadChapter`;
- toda tool call vira `ActionProposal` pendente e nunca executa automaticamente;
- falha opcional do provider não derruba Auth, Core, Suwayomi nem a Maya local.

Validação certificada no fechamento da P2B:

- controller: 22/22;
- controller/adapters/codecs/transport/WinCred: 82/82;
- regressões promovidas da UI: 17/17;
- `yomu_ai`: 62/62;
- `yomu_storage`: 36/36;
- local server/Auth: 38/38;
- desktop: 171/171;
- analyzer integral limpo;
- `tool\verify_workspace.ps1` aprovado em 227,5 s;
- build Windows Debug em
  `apps/yomu_desktop/build/windows/x64/runner/Debug/yomu_desktop.exe`;
- `git diff --check` limpo;
- hash da referência protegido preservado.

Limitações certificadas:

- nenhuma chamada live a conta ou modelo externo foi executada;
- disponibilidade, cobrança e retenção de providers externos não foram
  certificadas;
- Ollama em loopback não autentica a identidade do processo local;
- não há streaming, autonomia, memória nova, integração PWA/mobile ou provider
  personalizado no schema/código v4.

Contrato completo: `docs/p2b-maya-providers.md`.

## Próxima subfase solicitada — P2C

Necessidade de produto registrada: permitir **provider personalizado
OpenAI-compatible**. A P2C ainda não começou e não deve ser misturada com P2B.

Escopo preliminar para auditoria e plano na próxima conversa:

- endpoint/URL e modelo explícitos;
- API key opcional, sempre no Windows Credential Manager quando existir;
- HTTPS obrigatório para destinos remotos;
- HTTP somente para IP loopback literal;
- redirects desativados;
- proteção contra SSRF, DNS rebinding e destinos privados indevidos;
- consentimento exibindo o destino exato;
- fallback local preservado;
- tools continuam passando por `ActionProposal`;
- sem headers, templates ou bodies arbitrários na primeira versão.

O desenho provável exige um único bump `4 → 5`, migração forward e commit
próprio, mas schema e formato ainda precisam de auditoria e aprovação. Não
reserve tabela ou coluna antes disso.

Decisões que a próxima conversa deve fechar antes de implementar:

1. um único perfil customizado ou múltiplos perfis;
2. protocolo `chat/completions`, `responses` ou ambos;
3. API key opcional em todos os casos ou política por endpoint;
4. política exata para hosts LAN privados além de loopback.

Compatibilidade desejada a avaliar: OpenRouter, Groq, Together, vLLM,
LM Studio e LocalAI. Essa lista é objetivo de interoperabilidade, não prova de
compatibilidade atual.

## Próximo fluxo seguro

1. Revalidar repo, HEAD, status, hash, processos e portas.
2. Confirmar que apenas a documentação deste handoff está materialmente suja.
3. Se solicitado, revisar o diff documental e pedir autorização separada para
   staging seletivo e commit desse handoff.
4. Depois de baseline limpa, auditar somente leitura schema v4, controller,
   adapters, transport, WinCred e UI para P2C.
5. Produzir plano de schema `4 → 5`, política de endpoint/SSRF, migração e
   testes.
6. Pedir aprovação explícita para iniciar a implementação P2C.
7. Após implementação, executar gates completos e pedir autorizações separadas
   para staging, commit e push.

Não iniciar settings, memória, estado pessoal, Android, redesign PWA ou Source
Builder junto com P2C.
