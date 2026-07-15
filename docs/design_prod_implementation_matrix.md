# Contrato visual `design_prod`

Referencias imutaveis lidas em 2026-07-10:

- Desktop: `design_prod/design em producao.html` (preview 1320 x 940; janela interna 1240 x 800)
- Mobile: `design_prod/Yomu Mobile.dc.html` (preview 1200 x 980; aparelho 402 x 874)
- O HTML de referencia nao deve ser alterado para acomodar a implementacao.

## Tokens globais desktop

| Elemento | Valor no HTML | Valor Flutter antes da correcao | Valor Flutter corrigido |
|---|---|---|---|
| Fundo | `#07090e` + radial `rgba(81,104,207,.14)` | `#07090e` + radial aproximado | `YomuTokens.bg #07090e` + radial no shell |
| Surface | `#0f131b` | `#0f131b` | `YomuTokens.surface #0f131b` |
| Surface 2 | `#161b25` | `#161b25` | `YomuTokens.surface2 #161b25` |
| Surface 3 | `#1c2330` | `#1c2330` | `YomuTokens.surface3 #1c2330` |
| Surface raised | `#222a39` | `#222a39` | `YomuTokens.surfaceRaised #222a39` |
| Texto | `#f4f6fb` | `#f4f6fb` | `YomuTokens.text #f4f6fb` |
| Texto muted | `#a9b2c4` | `#a9b2c4` | `YomuTokens.textMuted #a9b2c4` |
| Texto subtle | `#818ca1` | `#818ca1` | `YomuTokens.textSubtle #818ca1` |
| Borda | `#293141` | `#293141` | `YomuTokens.border #293141` |
| Borda forte | `#3c475d` | `#3c475d` | `YomuTokens.borderStrong #3c475d` |
| Accent | `#91a5ff` | `#91a5ff` | `YomuTokens.accent #91a5ff` |
| Accent forte | `#5068cf` | `#5068cf` | `YomuTokens.accentStrong #5068cf` |
| Sucesso | `#65d19e` | `#65d19e` | `YomuTokens.success #65d19e` |
| Aviso | `#f2bd67` | `#f2bd67` | `YomuTokens.warning #f2bd67` |
| Perigo | `#ff7f8b` | `#ff7f8b` | `YomuTokens.danger #ff7f8b` |
| Focus | `#b5c2ff`, outline 2 px, offset 2 px | foco Material | `YomuTokens.focus #b5c2ff`, borda focada 1.5 px; foco de teclado preservado |
| Raios | `9 / 13 / 18 / 24 px` | `9 / 13 / 18 / 24` | `radiusSm/Md/Lg/Xl` iguais ao HTML |
| Duracoes | `140 / 240 / 420 ms` | nao centralizadas | `durationFast/Medium/Slow` |
| Curva de saida | `cubic-bezier(.16,1,.3,1)` | Material default | `Curves.easeOutCubic` (Flutter mais proximo disponivel) |
| Fonte de corpo | `-apple-system, BlinkMacSystemFont, SF Pro Text, system-ui, sans-serif` | `Segoe UI` | fonte do sistema Windows (`Segoe UI`) por ser o fallback efetivo no desktop Windows |
| Fonte display | `SF Pro Display, system-ui, sans-serif` | `Segoe UI` | fonte do sistema Windows; pesos/tamanhos/letter-spacing reproduzidos por componente |
| Fonte mono | `ui-monospace, SFMono-Regular, Consolas, monospace` | default | `Consolas` onde o design pede mono |

## Estrutura desktop

| Elemento | Valor no HTML | Valor Flutter antes da correcao | Valor Flutter corrigido |
|---|---|---|---|
| Largura da sidebar | `208px` | `208` | `208` |
| Fundo da sidebar | `oklch(13% 0.016 268)` | `#0f131b` | `#0d1017` (conversao sRGB usada na implementacao) |
| Padding sidebar | `14px 10px 12px` | header `18px`, lista `10px` | `14, 10, 12` |
| Semaforos | 3 circulos de `12px`, gap `7px` | ausentes | presentes, nas cores `#ff5f57/#febc2e/#28c840` |
| Marca Yomu | `26x26`, raio `8`, titulo `15px` | `30x30`, raio `9`, titulo `16px` | `26x26`, raio `8`, titulo `15px` |
| Item principal | padding `7x10`, raio `9`, fonte `13/600`, icone `18` | altura fixa `36` | padding/altura minima e tipografia do HTML |
| Item de sistema | padding `6x10`, fonte `12.5/500` | mesmo estilo por indice | grupo explicito e estilo proprio |
| Grupo Sistema | padding `16 10 6`, `10px/700`, tracking `.06em` | aparecia depois do indice 5 incorreto | antes de Configuracoes |
| Rodape sidebar | borda superior, status Core e perfil local | status rail horizontal sob o conteudo | rodape persistente na sidebar; disponibilidade do Core deriva do servidor HTTP vinculado e o estado do motor permanece separado |
| Header padrao | `22px 28px 14px`, titulo `24px`, kicker `10.5px` | proximo, mas nem todas telas usavam | componente compartilhado exato |
| Scroll principal | `18px 28px 30px` | variavel por tela | primitiva compartilhada |

## Navegacao desktop

| Elemento | Valor no HTML | Valor Flutter antes da correcao | Valor Flutter corrigido |
|---|---|---|---|
| Principais | Home, Biblioteca, Novidades, Historico, Explorar, Maya, Downloads | Servidor, Extensoes, Explorar, Biblioteca, Downloads, Historico, Maya... | Home, Biblioteca, Novidades, Historico, Explorar, Maya, Downloads |
| Sistema | Configuracoes, Servidor e Motor, Backup, Diagnostico | Criador, Configuracoes; demais ausentes/mal posicionados | Configuracoes, Servidor e Motor, Backup, Diagnostico |
| Explorar | Fontes, Extensoes, Repositorios, Migracao, Criador de fontes | busca de fontes em tela separada; Extensoes na sidebar | cinco segmentos na ordem do HTML; destinos pendentes usam placeholder explicito |
| Placeholder | texto exigido pelo escopo | mensagens variadas | `Esta funcao ainda nao foi implementada.` + fase quando aplicavel |

## Mobile/PWA — separada da promoção desktop

| Elemento | Estado atual no working tree | Preservação externa | Regra de promoção |
|---|---|---|---|
| `apps/yomu_mobile_pwa/index.html` | baseline material do HEAD | incluído integralmente no patch PWA | não incluir no futuro commit desktop |
| `apps/yomu_mobile_pwa/test_reader_races.mjs` | baseline material do HEAD; `reader race logic OK` | incluído integralmente no patch PWA | não confundir esse teste com o leitor Flutter |
| Patch PWA | não reaplicado | `C:\tmp\yomu-pwa-preservada-20260711.patch` | reaplicar e auditar somente na fase PWA |

As diferenças e decisões mobile anteriores permanecem preservadas no patch, mas não descrevem o working tree desktop promovível desta fase.

## Estados interativos extraidos

- Hover de navegacao: deslocamento horizontal `2px`; texto `#dce2ff`; icone `scale(1.06)`.
- Selecionado: trilho esquerdo `2px x 18px`, accent; fundo accent translucido.
- Pressed: escala `0.975` em cards/botoes segmentados/primarios/secundarios/icones.
- Focus visible: outline accent claro de `2px`, offset `2px`.
- Disabled: nunca deve executar operacao falsa; controles reais usam callback nulo e aparencia desabilitada.
- Reduced motion: animacoes e transicoes reduzidas para `.01ms` no HTML; Flutter respeita `disableAnimations` onde aplicavel.
- Animacoes relevantes: reveal de tela `420ms`, itens `360ms` escalonados em `45ms`, reader controls `180ms`, paineis `190ms`, fim de capitulo `240ms`.


## Correções funcionais e visuais da rodada final

| Elemento | Valor no HTML | Valor Flutter antes da correção | Valor Flutter corrigido |
|---|---|---|---|
| Home — grade | seis capas em uma linha no viewport desktop | quatro capas grandes | seis colunas responsivas com dados reais |
| Home — saúde | card lateral compacto | largura variável e conteúdo deslocado | largura de 300 px e estados reais do motor |
| Explorar — catálogo | destino Fontes abre conteúdo navegável | tela dependia de busca e podia ficar vazia | `POPULAR`, `LATEST` e `SEARCH` reais, com paginação |
| Obra — hero | capa, metadados e ações em bloco compacto | página técnica com lista Material | hero de 256 px, capa de 212 px, ações e capítulos progressivos |
| Leitor — painel | palco dedicado, controles e drawer | leitura sem estrutura visual completa | palco, scrubber, capítulos, modos, ajuste, zoom e progresso reais |
| Maya — layout | conversa e memória em duas colunas | tela vazia de coluna única | conversa real, ActionProposal e painel lateral de 300 px; memória indisponível explícita |

## Gate de promoção desktop

| Elemento | Estado auditado | Correção aplicada | Evidência |
|---|---|---|---|
| PWA | alterações materiais misturadas ao worktree desktop | preservadas em `C:\tmp\yomu-pwa-preservada-20260711.patch` e restauradas materialmente ao HEAD | SHA-256 `5EA845336F1643867E172CE8C68917904120746F53E25BEC7A22AA06B9254E00`; `git apply --check --cached` = 0 |
| Leitor Flutter — carga | `getChapter` podia mutar capítulo antes do gate | chave imutável por geração e `chapterId`; validação antes de toda mutação | 2 testes de cargas fora de ordem/troca de capítulo |
| Leitor Flutter — progresso | save pendente podia misturar capítulo novo e páginas antigas | snapshot imutável `chapterId/page/pageCount`, fila serializada e callbacks destacados no dispose | 4 testes de troca durante save, associação, falha e dispose |
| Explorar | respostas antigas podiam substituir ou concatenar consultas diferentes | request key por `sourceId/fetchType/query/página/geração` e bloqueio de duplicata | 5 testes determinísticos |
| Identidade do shell | `JP` e `João · perfil local` hardcoded | identidade neutra `Perfil local` | widget test |
| Janela Windows | 1240 × 800 era tratado como tamanho externo | 1240 × 800 é área cliente lógica; moldura calculada por DPI com `AdjustWindowRectExForDpi` | análise e build Windows |

A promoção permanece parcial. Material Icons ainda substituem os SVGs do HTML; página da obra, leitor, Downloads, Extensões e Repositórios ainda possuem diferenças estruturais; e faltam evidências de loading, erro, menus, tooltips e outros estados. O HTML permanece referência obrigatória para telas ainda não promovidas e aprovadas. Não há afirmação de fidelidade integral.

## Addendum de implementação — 2026-07-14

As linhas anteriores registram a rodada histórica. Para o estado atual, prevalece esta atualização:

| Área | Estado atual verificado | Evidência | Limitação |
|---|---|---|---|
| Saída Windows | `didRequestAppExit()` aguarda teardown serializado; pedidos repetidos compartilham a resposta | teste determinístico com `Completer`; runtime final encerrou Yomu e Java em 9,028 s e liberou `14567`/`8787` | encerramentos forçados não participam do handshake cancelável do Flutter |
| Leitor — progresso | pendências por capítulo, snapshots imutáveis e high-water monotônico impedem perda/regressão do save final, inclusive em A→B→A | testes de fila, troca de capítulo, retorno a A, falha, dispose e estado lido | runtime não substitui cobertura de todas as falhas de I/O |
| Leitor — modos | double-page avança uma página por vez e mostra a seguinte à esquerda; vertical/webtoon usam posições reais de viewport/`RenderBox` | widget com offset que diverge do fallback linear + capturas `08`–`12` com dados reais | painel de fim: widget proof apenas; sem screenshot runtime atual |
| Explore | ownership separado para fontes/catálogo, rejeição de resposta obsoleta, spinner/grid/load-more e refresh após instalação | testes determinísticos e `06-explore-real.png` | nem todos os estados de erro/loading têm par visual atual |
| Extensões/stores | catálogo e stores carregam independentemente; instalação serializa ações e recarrega fontes; Keiyoushi usa allowlist oficial | testes de tela e revisão de código | publicação real de uma nova fonte após instalação depende do comportamento do Suwayomi |
| Ícones e controles | sistema SVG próprio e sem referências `Icons.` nos paths promovidos; semântica/hit targets reforçados | código + widgets promovidos | não comprova equivalência geométrica integral ao HTML |
| Obra | hero usa `IntrinsicHeight`, eliminando `Spacer` em altura ilimitada | regressão widget | não é mais correto descrevê-lo como bloco fixo de 256 px |
| Fundo do shell | cor sólida atual | `app_shell.dart` | a linha histórica que menciona radial não descreve o estado atual |
| Evidência visual | `C:\Users\joaop\Downloads\yomu-sol-final\2026-07-14` | telas/estados principais com dados reais; `23-final-build-server-running.png` no bundle final; `24-core-unavailable-widget-proof.png` como prova widget externa do estado Core indisponível | sem alegação 1:1; estados interativos incompletos |

Gate de fechamento executado em 2026-07-14: `flutter analyze` e `dart analyze` limpos; `tool\verify_workspace.ps1` aprovado em 168,7 s; core 3/3, Suwayomi 42/42, local server/Auth 27/27, Maya 8/8, `yomu_storage` 23/23, PWA preload/reader race aprovados e desktop 74/74; build Windows Debug concluído; `git diff --check` aprovado. `design_prod/**` permaneceu imutável; este commit encerra o checkpoint pós-P0 sem iniciar P1, P2+, Android, redesign PWA ou Source Builder.
