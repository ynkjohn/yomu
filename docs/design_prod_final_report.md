# Relatório factual — correção `design_prod`

Data da validação: 2026-07-11 (America/Sao_Paulo)

## Identificação e estado Git

- HEAD inicial: `941c4e84efc78f5e082abd817d9790b8694dd12a`
- HEAD final: `941c4e84efc78f5e082abd817d9790b8694dd12a`
- Branch: `master`
- Git status inicial: sujo; já havia modificações rastreadas no desktop, PWA e `yomu_ui`, além de `design_prod/` não rastreado. O estado inicial completo não foi salvo em arquivo, portanto este relatório não inventa uma listagem retrospectiva.
- Git status final: sujo; 42 arquivos rastreados marcados e 8 caminhos não rastreados: `.playwright-cli/`, `apps/yomu_desktop/lib/screens/home_screen.dart`, `apps/yomu_desktop/test/explore_race_test.dart`, `apps/yomu_desktop/test/reader_race_test.dart`, `design_prod/`, `docs/design_prod_final_report.md`, `docs/design_prod_implementation_matrix.md` e `packages/yomu_ui/lib/src/widgets/screen_primitives.dart`.
- Commit criado: não.
- Processos encerrados nesta promoção desktop: sim, exclusivamente duas árvores órfãs de validação criadas por execuções concorrentes do verificador (PowerShell/cmd/Dart/Flutter tester). A propriedade e os descendentes foram inspecionados antes do encerramento; nenhum processo Yomu ou Java integrou essas árvores ou foi encerrado.
- Resultado geral: **parcial**.
- Correção de escopo posterior: a promoção atual é exclusivamente desktop. A PWA foi preservada em patch externo, restaurada ao baseline do HEAD e não pertence ao futuro commit desktop.

O resultado não pode ser classificado como concluído: há pares visuais desktop para Home, Biblioteca, Explorar, Servidor, Maya, página da obra, leitor e ajustes do leitor, mas os overlays ainda mostram diferenças e não há evidência equivalente para todos os estados, menus, tooltips e telas desktop.

## Separação e preservação da PWA

- Patch externo: `C:\tmp\yomu-pwa-preservada-20260711.patch`.
- Tamanho: 54.194 bytes.
- SHA-256: `5EA845336F1643867E172CE8C68917904120746F53E25BEC7A22AA06B9254E00`.
- Paths contidos: `apps/yomu_mobile_pwa/index.html` e `apps/yomu_mobile_pwa/test_reader_races.mjs`.
- `git apply --check --cached` retornou exit code 0 antes da restauração.
- Os dois arquivos foram restaurados individualmente ao HEAD. `git diff --exit-code -- <dois paths>` retornou 0 e `reader race logic OK` passou no baseline.
- Após a atualização do índice estatístico, os dois paths da PWA deixaram de aparecer tanto no `status` quanto no diff material.
- O patch não foi reaplicado nem apagado.

## Git status final completo

```text
 M apps/yomu_desktop/.gitignore
 M apps/yomu_desktop/README.md
 M apps/yomu_desktop/analysis_options.yaml
 M apps/yomu_desktop/assets/vendor/manifest.json
 M apps/yomu_desktop/lib/screens/downloads_screen.dart
 M apps/yomu_desktop/lib/screens/explore_screen.dart
 M apps/yomu_desktop/lib/screens/extensions_screen.dart
 M apps/yomu_desktop/lib/screens/library_screen.dart
 M apps/yomu_desktop/lib/screens/manga_detail_screen.dart
 M apps/yomu_desktop/lib/screens/maya_screen.dart
 M apps/yomu_desktop/lib/screens/placeholder_screen.dart
 M apps/yomu_desktop/lib/screens/reader_screen.dart
 M apps/yomu_desktop/lib/screens/server_screen.dart
 M apps/yomu_desktop/lib/shell/desktop_lifecycle.dart
 M apps/yomu_desktop/lib/shell/home_shell.dart
 M apps/yomu_desktop/pubspec.yaml
 M apps/yomu_desktop/test/widget_test.dart
 M apps/yomu_desktop/windows/.gitignore
 M apps/yomu_desktop/windows/CMakeLists.txt
 M apps/yomu_desktop/windows/flutter/CMakeLists.txt
 M apps/yomu_desktop/windows/runner/CMakeLists.txt
 M apps/yomu_desktop/windows/runner/Runner.rc
 M apps/yomu_desktop/windows/runner/flutter_window.cpp
 M apps/yomu_desktop/windows/runner/flutter_window.h
 M apps/yomu_desktop/windows/runner/main.cpp
 M apps/yomu_desktop/windows/runner/resource.h
 M apps/yomu_desktop/windows/runner/runner.exe.manifest
 M apps/yomu_desktop/windows/runner/utils.cpp
 M apps/yomu_desktop/windows/runner/utils.h
 M apps/yomu_desktop/windows/runner/win32_window.cpp
 M apps/yomu_desktop/windows/runner/win32_window.h
 M packages/yomu_suwayomi/lib/src/client/suwayomi_api.dart
 M packages/yomu_suwayomi/lib/src/client/suwayomi_models.dart
 M packages/yomu_suwayomi/test/suwayomi_api_test.dart
 M packages/yomu_suwayomi/vendor/manifest.json
 M packages/yomu_ui/lib/src/theme/yomu_theme.dart
 M packages/yomu_ui/lib/src/theme/yomu_tokens.dart
 M packages/yomu_ui/lib/src/widgets/app_shell.dart
 M packages/yomu_ui/lib/src/widgets/async_scaffold.dart
 M packages/yomu_ui/lib/src/widgets/status_pill.dart
 M packages/yomu_ui/lib/yomu_ui.dart
 M pubspec.lock
?? .playwright-cli/
?? apps/yomu_desktop/lib/screens/home_screen.dart
?? apps/yomu_desktop/test/explore_race_test.dart
?? apps/yomu_desktop/test/reader_race_test.dart
?? design_prod/
?? docs/design_prod_final_report.md
?? docs/design_prod_implementation_matrix.md
?? packages/yomu_ui/lib/src/widgets/screen_primitives.dart
```

`git diff --cached --name-only` está vazio: não há staging.

## Matriz de telas

As linhas Desktop descrevem o working tree promovível. As linhas PWA abaixo são apenas o inventário histórico das alterações preservadas no patch externo; não descrevem arquivos atualmente modificados no working tree e não pertencem ao futuro commit desktop.

| Tela | Desktop/PWA | Design reproduzido? | Função real conectada? | Placeholder usado? | Testes | Screenshot HTML | Screenshot app | Pendências |
|---|---|---|---|---|---|---|---|---|
| Home | Desktop | Parcial | Sim: biblioteca, progresso, retomada, health | Não | Analyze, widgets, verifier | `home-html.png` | `home-flutter.png` | Estrutura de 6 colunas, health de 300 px e card Maya corrigidos; dados reais e SVGs ainda diferem |
| Biblioteca | Desktop | Parcial | Sim: coleção, não lidos, abertura e refresh | Não | Widgets e verifier | `biblioteca-html.png` | `biblioteca-flutter.png` | 4 títulos reais; offline e sequência continuam `Indisponível` por ausência de fonte real |
| Novidades | Desktop | Parcial no shell | Não existe como tela real nesta fase | Sim | Navegação coberta indiretamente | — | — | Falta reprodução e par visual da tela; badge mostra indisponibilidade, sem métrica falsa |
| Histórico | Desktop | Parcial no shell | Não | Sim | Navegação coberta indiretamente | — | — | Falta reprodução e par visual |
| Explorar — Fontes | Desktop | Parcial | Sim: lista real, Popular, Recentes, pesquisa e paginação Suwayomi | Não | API 9/9, 5 testes determinísticos de corrida, desktop, verifier | `explorar-html.png` | `explorar-flutter.png` | Fonte real Manhastro; catálogo completo evidenciado em `explorar-catalogo-flutter.png`; referência usa fontes demonstrativas |
| Explorar — Extensões | Desktop | Parcial | Sim: extensões reais | Não | Widgets e verifier | — | — | Falta par visual específico |
| Explorar — Repositórios | Desktop | Parcial | Sim: repositórios e Keiyoushi reais | Não | Verifier | — | — | Falta par visual específico |
| Explorar — Migração | Desktop | Parcial | Não | Sim | Navegação coberta indiretamente | — | — | Implementação futura e par visual pendentes |
| Explorar — Criador de fontes | Desktop | Parcial | Não, conforme restrição da fase | Sim | Navegação coberta indiretamente | — | — | Source Builder funcional permanece para a última fase |
| Detalhes da obra | Desktop | Parcial | Sim: biblioteca, fonte, capítulos, leitura e downloads | Não | Kernel, desktop, verifier | `manga-html.png` | `manga-flutter.png` | Dados equivalentes exatos não existem entre demo Berserk e catálogo Manhastro; SVGs e microtipografia divergem |
| Capítulos | Desktop | Parcial | Sim: atualização progressiva, pesquisa, filtros, ordenação, leitura e download | Não | Kernel, desktop, verifier | `manga-html.png` | `manga-flutter.png` | Lista real com 291 capítulos; estados loading/erro/vazio implementados; comparação usa conteúdo diferente |
| Leitor | Desktop | Parcial | Sim: páginas, capítulos adjacentes, modos, zoom e progresso | Parcial: bookmark/fullscreen/persistência por obra indisponíveis | 6 testes determinísticos de corrida Flutter e verifier | `leitor-html.png` | `leitor-flutter.png` | Painel de ajustes também pareado; bookmark, fullscreen e persistência por obra ainda pendentes |
| Maya | Desktop | Parcial | Sim: chat local, biblioteca real e ActionProposal | Sim: memória de preferências | Maya 8/8 e verifier | `maya-html.png` | `maya-flutter.png` | Estrutura de duas colunas reproduzida; memória permanece com placeholder porque não existe backend |
| Downloads | Desktop | Parcial no shell | Sim | Não | Verifier | — | — | Reprodução visual e par pendentes |
| Configurações | Desktop | Parcial no shell | Não nesta fase | Sim | Navegação coberta indiretamente | — | — | Tela completa e par pendentes |
| Servidor e Motor | Desktop | Parcial | Sim: start, stop, restart, health, LAN, pairing, sessões/revogação | Não | Lifecycle, widgets e verifier | `servidor-html.png` | `servidor-flutter.png` | Conteúdo real (LAN desativada, duas sessões, versão/PID/caminho reais) difere da demonstração; detalhes visuais permanecem |
| Backup | Desktop | Parcial no shell | Não | Sim | Navegação coberta indiretamente | — | — | Tela completa e par pendentes |
| Diagnóstico | Desktop | Parcial no shell | Não | Sim | Navegação coberta indiretamente | — | — | Tela completa e par pendentes |
| Onboarding — introdução | PWA | Parcial | Fluxo visual antes do pareamento real | Não | Sintaxe e verifier | `onboarding-html.png` | `onboarding-pwa.png` | Referência inclui moldura/status bar de iPhone; PWA registra somente viewport; demais passos do onboarding não foram reproduzidos |
| Pareamento | PWA | Parcial | Sim: claim/autenticação reais | Não | Auth/server/verifier | — | — | Par visual específico pendente |
| Home | PWA | Parcial | Sim: biblioteca real | Não | PWA/verifier | — | — | Par visual pendente |
| Biblioteca | PWA | Parcial | Sim | Não | PWA/verifier | — | — | Par visual pendente |
| Novidades | PWA | Parcial | Derivada de dados reais disponíveis | Não | PWA/verifier | — | — | Par visual e comportamento completo pendentes |
| Histórico | PWA | Parcial | Não | Sim | PWA/verifier | — | — | Par visual pendente |
| Explorar — Fontes | PWA | Parcial | Estrutura presente; backend conforme sessão | Parcial | PWA/verifier | — | — | Par visual e fluxo completo pendentes |
| Explorar — Extensões | PWA | Parcial | Não exposto integralmente | Sim | PWA/verifier | — | — | Par visual pendente |
| Explorar — Repositórios | PWA | Parcial | Não exposto integralmente | Sim | PWA/verifier | — | — | Par visual pendente |
| Explorar — Migração | PWA | Parcial | Não | Sim | PWA/verifier | — | — | Par visual pendente |
| Explorar — Criador de fontes | PWA | Parcial | Não | Sim | PWA/verifier | — | — | Funcionalidade futura e par pendentes |
| Detalhes da obra | PWA | Não auditado visualmente nesta rodada | Sim | Não | PWA/verifier | — | — | Par visual pendente |
| Capítulos | PWA | Não auditado visualmente nesta rodada | Sim | Não | PWA/verifier | — | — | Par visual pendente |
| Leitor | PWA | Não auditado visualmente nesta rodada | Sim: tickets, progresso e proteções de corrida | Não | `preload logic OK`, `reader race logic OK` | — | — | Par visual e fluxos interativos completos pendentes |
| Downloads | PWA | Parcial no destino “Mais” | Não integralmente | Sim | PWA/verifier | — | — | Par visual pendente |
| Maya | PWA | Parcial na navegação inferior | Não integralmente | Sim | PWA/verifier | — | — | Par visual pendente |
| Configurações | PWA | Parcial no destino “Mais” | Não | Sim | PWA/verifier | — | — | Par visual pendente |
| Servidor | PWA | Parcial no destino “Mais” | Não exposto como controle administrativo | Sim | PWA/verifier | — | — | Par visual pendente |
| Backup | PWA | Parcial no destino “Mais” | Não | Sim | PWA/verifier | — | — | Par visual pendente |
| Diagnóstico | PWA | Parcial no destino “Mais” | Não | Sim | PWA/verifier | — | — | Par visual pendente |
| Logout | PWA | Funcional, visual não auditado | Sim | Não | Auth/verifier | — | — | Par visual pendente |
| Sessão expirada | PWA | Funcional, visual não auditado | Sim | Não | Auth/verifier | — | — | Par visual pendente |

## Arquivos criados nesta correção

- `apps/yomu_desktop/lib/screens/home_screen.dart`
- `docs/design_prod_implementation_matrix.md`
- `docs/design_prod_final_report.md`
- Evidências PNG sob `design_prod/prints/correcao_final/`
- `apps/yomu_desktop/test/reader_race_test.dart`
- `apps/yomu_desktop/test/explore_race_test.dart`

`.playwright-cli/`, `design_prod/` e `packages/yomu_ui/lib/src/widgets/screen_primitives.dart` aparecem como não rastreados no estado final. Nem todo esse conteúdo foi criado nesta correção; o worktree já estava sujo e `design_prod/` já era a referência fornecida.

## Arquivos modificados diretamente nesta correção

- `apps/yomu_desktop/lib/screens/home_screen.dart` (novo)
- `apps/yomu_desktop/lib/screens/explore_screen.dart`
- `apps/yomu_desktop/lib/screens/extensions_screen.dart`
- `apps/yomu_desktop/lib/screens/library_screen.dart`
- `apps/yomu_desktop/lib/screens/manga_detail_screen.dart`
- `apps/yomu_desktop/lib/screens/reader_screen.dart`
- `apps/yomu_desktop/lib/screens/maya_screen.dart`
- `apps/yomu_desktop/lib/screens/placeholder_screen.dart`
- `apps/yomu_desktop/lib/screens/server_screen.dart`
- `apps/yomu_desktop/lib/shell/home_shell.dart`
- `apps/yomu_desktop/pubspec.yaml`
- `pubspec.lock`
- `packages/yomu_suwayomi/lib/src/client/suwayomi_api.dart`
- `packages/yomu_suwayomi/lib/src/client/suwayomi_models.dart`
- `packages/yomu_suwayomi/test/suwayomi_api_test.dart`
- `apps/yomu_desktop/lib/shell/desktop_lifecycle.dart` (formatação automática durante a rodada)
- `apps/yomu_desktop/test/widget_test.dart`
- `apps/yomu_desktop/windows/runner/main.cpp`
- `apps/yomu_desktop/windows/runner/win32_window.cpp`
- `apps/yomu_desktop/windows/runner/win32_window.h`
- `apps/yomu_mobile_pwa/index.html`
- `packages/yomu_ui/lib/src/theme/yomu_tokens.dart`
- `packages/yomu_ui/lib/src/widgets/app_shell.dart`

O `git status` contém outros arquivos modificados que já integravam o worktree sujo; este relatório não os atribui automaticamente a esta correção.

## Tokens visuais implementados

- Fundo principal `#05060A`/equivalente Flutter opaco, sem o gradiente azul herdado.
- Sidebar de 208 px.
- Paleta de fundo, superfície, texto, texto secundário, borda, accent e estados extraída do CSS.
- Raios, durações e dimensões principais registrados em `docs/design_prod_implementation_matrix.md`.
- A janela declara uma área cliente lógica de 1240 × 800. `Win32Window::Create` escala essa área para o DPI do monitor e usa `AdjustWindowRectExForDpi` (com fallback compatível) para calcular title bar e bordas; não há compensação fixa dependente de máquina.
- Tokens mobile e estrutura inferior extraídos do HTML mobile.

## Componentes compartilhados e navegação

- Shell desktop com grupos principal/sistema, rodapé, status real e perfil.
- Suporte a grupos e badges no item de navegação; badges sem fonte real exibem indisponibilidade em vez de números fictícios.
- Primitivos de cabeçalho, cards, estados assíncronos e pills compartilhados.
- Navegação desktop preserva Home, Biblioteca, Novidades, Histórico, Explorar, Maya, Downloads, Configurações, Servidor e Motor, Backup e Diagnóstico.
- Explorar preserva Fontes, Extensões, Repositórios, Migração e Criador de fontes.
- O shell usa identidade neutra `Perfil local`; `JP` e `João · perfil local` hardcoded foram removidos.

## Funções reais preservadas e conectadas ao novo visual

- Suwayomi: start, stop, restart, health e identificação real.
- LAN, pareamento, sessões e revogação.
- Extensões, repositórios/Keiyoushi, fontes, busca e catálogo.
- Biblioteca, detalhes, capítulos, downloads, leitor e progresso.
- Maya mínima e `ActionProposal`.
- A PWA não integra esta promoção; suas alterações foram preservadas no patch externo e o working tree voltou ao baseline material.

Não houve transplante do JavaScript demonstrativo para Flutter e nenhum backend falso foi criado.

## Funções inexistentes e placeholders

- Desktop: Novidades, Histórico, Configurações, Backup, Diagnóstico, Migração e Criador de fontes usam o texto padronizado `Esta função ainda não foi implementada.` quando não há função real.
- PWA: destinos sem backend real permanecem visíveis e usam o mesmo contrato de indisponibilidade.
- Source Builder não foi implementado funcionalmente, conforme restrição.

## Diferenças visuais conhecidas

- Ícones desktop ainda usam `Material Icons`; os SVGs do design não foram reproduzidos integralmente.
- Tipografia depende da pilha Flutter/PWA disponível e ainda diverge da referência em peso e métricas.
- Página da obra, leitor, Downloads, Extensões e Repositórios ainda possuem diferenças estruturais em relação ao HTML.
- Home, Biblioteca, Explorar, Servidor, Maya, obra e leitor possuem overlays e diffs em 1226 × 793. Diferenças restantes incluem conteúdo real versus dados demonstrativos, SVGs, microtipografia e alguns estados sem backend.
- Explorar agora carrega o catálogo Popular completo da fonte real e não permanece vazio.
- A tela de obra e o leitor agora possuem estrutura dedicada do design e evidência; não são mais a lista técnica Material anterior.
- Biblioteca não possui fonte real para armazenamento offline e sequência; esses cards exibem `Indisponível`.
- Não existem pares visuais para todas as telas, estados, modais, drawers, menus, tooltips e animações.
- Nenhuma afirmação de correspondência integral ou percentual é feita.

## Regressões encontradas e corrigidas

- Home em branco por `Row` com `crossAxisAlignment.stretch` dentro de `ListView`; corrigido.
- Página da obra travada por `Spacer` em eixo vertical não limitado; hero fixado em 256 px e capítulos carregados progressivamente.
- Bootstrap Windows falhando com `MissingPluginException` de `path_provider`; substituído pelo mesmo caminho histórico `%APPDATA%\\app.yomu\\yomu_desktop`, sem alterar dados existentes.
- Explorar vazio por uso exclusivo de busca; contrato GraphQL ampliado para `POPULAR`, `LATEST` e `SEARCH`, com paginação real.
- Leitor Flutter: respostas antigas de `getChapter`/páginas agora são rejeitadas por geração e `chapterId` antes de qualquer mutação; saves usam snapshots imutáveis e fila serializada.
- Explorar: respostas antigas agora são rejeitadas por fonte, tipo, consulta normalizada, página e geração; páginas incompatíveis não são concatenadas e “Carregar mais” duplicado é bloqueado.
- Overflow do shell em largura estreita; corrigido e coberto por widget test.
- Badges demonstrativos `12` e `2` removidos como métricas falsas; o componente permanece visível com indisponibilidade.
- Fundo radial azul herdado removido para corresponder ao fundo quase preto do HTML.

## Testes e builds

Comando final:

```powershell
powershell -ExecutionPolicy Bypass -File tool\verify_workspace.ps1
```

Resultado final: `VERIFY_EXIT=1`, exclusivamente no build Windows por `LNK1168`; análise e todas as suítes anteriores ao build passaram.

O verificador executou:

- `dart pub get` — passou.
- `flutter analyze` — `No issues found`.
- Testes dos pacotes — passaram.
- Testes de lifecycle/processos — 35 passaram.
- Testes de autenticação, servidor, SSRF e sessões — 26 passaram.
- Testes Maya — 8 passaram.
- Testes de storage/DB/locks — 23 passaram.
- PWA preload — `preload logic OK`.
- PWA baseline — `reader race logic OK`; este resultado é exclusivo da PWA e não comprova o leitor Flutter.
- Leitor Flutter — 6 testes determinísticos próprios.
- Explorar — 5 testes determinísticos próprios.
- Testes desktop — 25 passaram, incluindo os 11 testes novos de corrida.
- `flutter build windows --debug` — compilação chegou ao linker, mas falhou com `LINK : fatal error LNK1168: cannot open ...\yomu_desktop.exe for writing` porque o aplicativo permaneceu aberto conforme a restrição.

Yomu e Java não foram encerrados por esta promoção. O Yomu estava aberto no momento do link, comprovado pelo `LNK1168`; na inspeção final o processo Yomu já não estava presente, sem ação de encerramento desta tarefa, enquanto o Java/Suwayomi permaneceu ativo no PID 35784 e em `127.0.0.1:14567`. Não existe build executável contendo estas correções finais até que um novo build possa substituir o arquivo.

## Evidências visuais

Diretório absoluto: `C:\Users\joaop\Projetos\yomu\design_prod\prints\correcao_final`

- `home-html.png`, `home-flutter.png`, `home-flutter-stopped.png`, `home-overlay.png`, `home-diff.png`
- `manga-html.png`, `manga-flutter.png`, `manga-overlay.png`, `manga-diff.png`
- `leitor-html.png`, `leitor-flutter.png`, `leitor-overlay.png`, `leitor-diff.png`
- `leitor-ajustes-html.png`, `leitor-ajustes-flutter.png`, `leitor-ajustes-overlay.png`, `leitor-ajustes-diff.png`
- `maya-html.png`, `maya-flutter.png`, `maya-overlay.png`, `maya-diff.png`
- `explorar-catalogo-flutter.png`
- `biblioteca-html.png`, `biblioteca-flutter.png`, `biblioteca-overlay.png`, `biblioteca-diff.png`
- `explorar-html.png`, `explorar-flutter.png`, `explorar-overlay.png`, `explorar-diff.png`
- `servidor-html.png`, `servidor-flutter.png`, `servidor-overlay.png`, `servidor-diff.png`
- `onboarding-html.png`, `onboarding-pwa.png`

Os pares desktop atuais são 1226 × 793, exatamente a área capturada da janela nativa. O par mobile é 402 × 874.

## Bloqueios e próximas fases

1. Substituir Material Icons pelos SVGs exatos da referência.
2. Reproduzir individualmente todas as telas ainda sem par visual.
3. Conectar métricas/filtros somente quando houver fontes reais.
4. Repetir screenshot, overlay e diff para cada estado interativo.
5. Implementar Source Builder funcionalmente apenas na fase final.

## Lista explícita proposta para futuro staging desktop

Nenhum destes paths foi stageado nesta tarefa. A lista proposta é:

O diff tracked material final possui 26 arquivos, 5.277 inserções e 1.596 remoções. Um desses 26 paths é `desktop_lifecycle.dart`, excluído abaixo por conter somente formatação. Os arquivos novos desktop/documentação aparecem separadamente como untracked no status completo.

- `apps/yomu_desktop/lib/screens/downloads_screen.dart`
- `apps/yomu_desktop/lib/screens/explore_screen.dart`
- `apps/yomu_desktop/lib/screens/extensions_screen.dart`
- `apps/yomu_desktop/lib/screens/home_screen.dart`
- `apps/yomu_desktop/lib/screens/library_screen.dart`
- `apps/yomu_desktop/lib/screens/manga_detail_screen.dart`
- `apps/yomu_desktop/lib/screens/maya_screen.dart`
- `apps/yomu_desktop/lib/screens/placeholder_screen.dart`
- `apps/yomu_desktop/lib/screens/reader_screen.dart`
- `apps/yomu_desktop/lib/screens/server_screen.dart`
- `apps/yomu_desktop/lib/shell/home_shell.dart`
- `apps/yomu_desktop/pubspec.yaml`
- `apps/yomu_desktop/test/explore_race_test.dart`
- `apps/yomu_desktop/test/reader_race_test.dart`
- `apps/yomu_desktop/test/widget_test.dart`
- `apps/yomu_desktop/windows/runner/main.cpp`
- `apps/yomu_desktop/windows/runner/win32_window.cpp`
- `apps/yomu_desktop/windows/runner/win32_window.h`
- `packages/yomu_suwayomi/lib/src/client/suwayomi_api.dart`
- `packages/yomu_suwayomi/lib/src/client/suwayomi_models.dart`
- `packages/yomu_suwayomi/test/suwayomi_api_test.dart`
- `packages/yomu_ui/lib/src/theme/yomu_theme.dart`
- `packages/yomu_ui/lib/src/theme/yomu_tokens.dart`
- `packages/yomu_ui/lib/src/widgets/app_shell.dart`
- `packages/yomu_ui/lib/src/widgets/async_scaffold.dart`
- `packages/yomu_ui/lib/src/widgets/screen_primitives.dart`
- `packages/yomu_ui/lib/src/widgets/status_pill.dart`
- `packages/yomu_ui/lib/yomu_ui.dart`
- `pubspec.lock`
- `docs/design_prod_final_report.md`
- `docs/design_prod_implementation_matrix.md`

`apps/yomu_desktop/lib/shell/desktop_lifecycle.dart` não integra a lista: seu diff é somente formatação nesta rodada e não há justificativa material para promovê-lo.

## Exclusões explícitas do futuro commit desktop

- `apps/yomu_mobile_pwa/index.html`
- `apps/yomu_mobile_pwa/test_reader_races.mjs`
- `.playwright-cli/**`
- `design_prod/**`, incluindo screenshots e evidências
- `C:\tmp\yomu-pwa-preservada-20260711.patch`
- `apps/yomu_desktop/lib/shell/desktop_lifecycle.dart`
- Arquivos marcados apenas por EOL/stat/metadata, sem diff material:
  - `apps/yomu_desktop/.gitignore`
  - `apps/yomu_desktop/README.md`
  - `apps/yomu_desktop/analysis_options.yaml`
  - `apps/yomu_desktop/assets/vendor/manifest.json`
  - `apps/yomu_desktop/windows/.gitignore`
  - `apps/yomu_desktop/windows/CMakeLists.txt`
  - `apps/yomu_desktop/windows/flutter/CMakeLists.txt`
  - `apps/yomu_desktop/windows/runner/CMakeLists.txt`
  - `apps/yomu_desktop/windows/runner/Runner.rc`
  - `apps/yomu_desktop/windows/runner/flutter_window.cpp`
  - `apps/yomu_desktop/windows/runner/flutter_window.h`
  - `apps/yomu_desktop/windows/runner/resource.h`
  - `apps/yomu_desktop/windows/runner/runner.exe.manifest`
  - `apps/yomu_desktop/windows/runner/utils.cpp`
  - `apps/yomu_desktop/windows/runner/utils.h`
  - `packages/yomu_suwayomi/vendor/manifest.json`

## Confirmações

- O HTML de referência não foi modificado nem simplificado para parecer com o Flutter.
- A arquitetura permaneceu Flutter Windows nativo e PWA, sem Electron ou WebView.
- Suwayomi permaneceu em loopback `127.0.0.1:14567`; Yomu Core permaneceu em `127.0.0.1:8787` por padrão.
- Nenhum commit foi criado.
- Nenhum staging foi realizado.
- P1 não foi iniciado.
- Source Builder não avançou e permanece reservado para a última fase.
- Nenhum processo Yomu ou Java foi encerrado nesta promoção. Somente processos auxiliares órfãos de validação foram encerrados. A inspeção final encontrou o Java/Suwayomi ativo; o Yomu deixou de existir após o momento do `LNK1168` sem comando de encerramento desta tarefa.

## Addendum — auditoria pós-P0 de 2026-07-14

Este addendum preserva o relatório de 2026-07-11 como registro histórico e o supersede somente quanto ao estado atual.

- O baseline de origem é `master` em `941c4e84efc78f5e082abd817d9790b8694dd12a`; este commit encerra separadamente o checkpoint pós-P0 e não inclui P1.
- `design_prod/**` permaneceu intocado. O HTML desktop tem SHA-256 `8DCF41D7283CB16A70A9FA2E0F9D1CE05591F7165AB1AB4FB560D9246A387AC9`.
- A exclusão histórica de `apps/yomu_desktop/lib/shell/desktop_lifecycle.dart` não vale para o estado atual: o arquivo agora contém a correção material `DesktopExitCoordinator`, e `HomeShell.didRequestAppExit()` aguarda o teardown antes de devolver `AppExitResponse.exit`.
- O defeito foi reproduzido com fechamento normal: Yomu PID 21800 encerrou, mas o Java PID 35808, filho do Yomu e identificado por `runId=b0dd3af53150afea`, continuou em `127.0.0.1:14567` por mais de 75 s. Com autorização explícita, uma nova instância Yomu reanexou ao processo e o comando “Parar” encerrou-o de forma controlada; nenhum processo foi encerrado à força.
- A causa era preexistente no P0: callbacks `detached`/`dispose` não podiam aguardar `_coordinatedShutdown()`. O handshake Windows via `didRequestAppExit()` agora mantém a resposta pendente até o teardown e compartilha a mesma future em pedidos repetidos; o teste usa `Completer` para provar ambos os requisitos.
- A revisão final encontrou e corrigiu uma segunda condição de corrida no Reader: em A→B→A com save lento, um snapshot stale podia reverter o save terminal de A. A fila agora mantém high-water monotônico por capítulo, nunca reduz página nem `isRead=true`; teste determinístico cobre o retorno a A. Um widget adicional usa um offset no qual o fallback linear escolheria a página 0 e prova que os `RenderBox` reais selecionam a página 1.
- A auditoria semântica final também eliminou um estado falso no rodapé: a disponibilidade do Yomu Core agora depende da presença real do servidor HTTP vinculado, enquanto o estado do motor Suwayomi permanece separado. Sem servidor, a UI informa Core indisponível mesmo que o motor esteja `running`; há regressão automatizada.
- A validação de fechamento passou em 2026-07-14: `flutter analyze` e `dart analyze` sem issues; verificador integral aprovado em 168,7 s; core 3/3, Suwayomi 42/42, local server/Auth 27/27, Maya 8/8, `yomu_storage` 23/23, PWA preload/reader race aprovados e desktop 74/74; build Windows Debug em `apps\yomu_desktop\build\windows\x64\runner\Debug\yomu_desktop.exe`; `git diff --check` aprovado.
- A prova no bundle final iniciou Yomu PID 24440 e Java filho PID 41760 (`runId=c61ce4843ac65fd8`), com listeners somente em `127.0.0.1:8787` e `127.0.0.1:14567`. Um `WM_CLOSE` normal encerrou ambos em 9,028 s, liberou as portas e removeu o arquivo de identidade; não houve kill ou terminação forçada.
- A evidência visual atual está fora do repositório em `C:\Users\joaop\Downloads\yomu-sol-final\2026-07-14`. Ela cobre Server, Home, Library, Explore, manga detail, Reader resume/modes/vertical/double/webtoon, Maya, Downloads, Extensions, Repositories e o placeholder de Source Builder. `03-server-after-start.png` não deve ser usada por conter uma janela de terminal; `23-final-build-server-running.png` registra o bundle final e `24-core-unavailable-widget-proof.png` registra externamente o estado sintético Core indisponível sem manipular processos ou portas.
- O leitor foi observado com dados reais na página 5/48. Double-page exibiu a página seguinte à esquerda; vertical e webtoon foram capturados. O painel de fim tem prova widget, não prova runtime atual, porque forçá-lo alteraria progresso/`isRead` do usuário.
- O sistema atual usa ícones SVG próprios (`YomuIconData`, `YomuIcons`, `YomuIcon`, `YomuIconButton`); isso supersede a observação histórica sobre Material Icons, mas não comprova que toda geometria seja idêntica ao HTML.
- O hero de detalhes usa `IntrinsicHeight`, não altura fixa de 256 px, após um teste revelar `Spacer` sob altura ilimitada. O shell atual usa fundo sólido. Essas notas supersedem somente as descrições de estado atual do relatório histórico.
- A comparação continua parcial: não há prova de todos os estados, menus, tooltips, foco e animações, nem alegação de fidelidade 1:1.
- P1, P2+, Android, redesign PWA e Source Builder não foram iniciados; Source Builder permanece por último.
- Este relatório integra o commit de encerramento do checkpoint pós-P0; qualquer trabalho de P1 exige baseline, plano, gates, staging e commit próprios.
