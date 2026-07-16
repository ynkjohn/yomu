# Yomu — regras operacionais

## Inicialização obrigatória

- Trabalhe somente em `C:\Users\joaop\Projetos\yomu`. Rejeite explicitamente
  `C:\Users\joaop\Projetos\multiyomi`.
- Os primeiros comandos devem ser:

  ```powershell
  Set-Location 'C:\Users\joaop\Projetos\yomu'
  git rev-parse --show-toplevel
  Get-Content -Raw AGENTS.md
  Get-Content -Raw docs\current-handoff.md
  ```

- Pare se a raiz não for exatamente o repositório Yomu.
- Revalide branch, HEAD, working tree, staged state, referência protegida,
  processos e portas. O handoff é um snapshot, não substitui evidência atual.

## Baseline atual

- Branch esperada: `master`.
- HEAD remoto/local auditado em 2026-07-16:
  `7a35094b80b9359327c49e198258fc3c3d255571`
  (`feat(maya): add provider integrations`).
- P0, checkpoint pós-P0, P1, P2A e P2B estão concluídos e commitados
  separadamente. O SQLite Yomu está no schema v4.
- A próxima necessidade de produto registrada é **P2C — provider personalizado
  OpenAI-compatible**. Ela ainda não foi implementada. Primeiro faça auditoria
  e plano; implementação, schema bump, staging e commit exigem aprovações
  explícitas próprias.
- O estado completo e a ordem dos commits estão em
  `docs/current-handoff.md`. Documentos de fases antigas preservam o estado
  histórico da época e não prevalecem sobre código, diff e o handoff atual.

## Arquitetura imutável

- Desktop é Flutter Windows nativo; não usar Electron, WebView, Python UI ou
  browser como desktop.
- Suwayomi-Server é o engine local de extensões e só pode usar
  `127.0.0.1:14567`.
- Yomu Core usa por padrão `127.0.0.1:8787`. LAN/PWA exige opt-in explícito.
- Desktop é a fonte de verdade. iPhone usa PWA LAN; Android permanece futuro.
- Suwayomi DB é dono de catálogo, mangas, capítulos, downloads, progresso,
  read flags e demais fatos de leitura.
- Yomu SQLite guarda somente dados específicos do app: hoje `app_meta`, hashes
  de sessões, histórico/propostas da Maya e configuração não secreta de
  provider. Não duplicar fatos do Suwayomi.
- Maya é opcional e local-first. Toda ação sensível continua exigindo
  `ActionProposal` e confirmação explícita; provider algum pode executar ação
  automaticamente.
- Não usar Docker. Source Builder continua reservado para a última fase.

## Versões fixas

- Flutter 3.32.5; Dart 3.8.1; Drift 2.28.0; sqlite3 2.9.4.
- Não usar `sqlite3_flutter_libs`.
- Não atualizar SDK ou dependências sem aprovação explícita.

## Proteções de arquivos e Git

- `design_prod/**` é referência imutável: nunca editar, mover, formatar,
  stagear ou commitar.
- Também não tocar nem incluir em commits: `.playwright-cli/**` e
  `mcps/tasks/tools/**`.
- SHA-256 esperado de `design_prod\design em producao.html`:
  `8DCF41D7283CB16A70A9FA2E0F9D1CE05591F7165AB1AB4FB560D9246A387AC9`.
- Preserve integralmente a working tree suja. Não use reset, clean, restore,
  checkout destrutivo ou rebase.
- Nunca use `git add .`. Staging deve usar allowlist nominal e precisa de
  autorização explícita. Mostre o staged diff antes de pedir autorização de
  commit.
- Não faça stage, commit, amend, push ou force-push sem autorização explícita
  para aquela operação.
- Nunca misture duas fases de persistência no mesmo checkpoint ou commit. Cada
  subfase P2+ exige exatamente um schema bump forward e commit próprio.

## Processos, validação e stop conditions

- Nunca encerre Yomu, Java, Dart, Flutter ou libere portas sem ownership
  comprovada e autorização. Em `LNK1168`, pare e peça ao usuário para fechar o
  Yomu normalmente.
- Gates de fase: testes direcionados, `packages/yomu_storage`, packages
  afetados, desktop quando aplicável, analyzer, `tool\verify_workspace.ps1`,
  build Windows seguro, prova runtime proporcional, `git diff --check`, status,
  diff integral, documentação e evidência visual externa quando a UI mudar.
- Confirme o hash de `design_prod` antes e depois de cada fase.
- Pare para perda/transformação irreversível de dados, mudança de ownership,
  arquitetura ou produto, upgrade, Git destrutivo, processos/portas, início de
  nova subfase, staging, commit ou push.
- Relatórios devem separar baseline committed, working tree inicial, mudanças
  da sessão, validação atual e limitações.
