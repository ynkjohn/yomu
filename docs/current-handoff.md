# Yomu — handoff atual

Snapshot factual atualizado em 2026-07-18 na abertura de R0 do Motor Interno
Transparente. Código, Git, processos e comportamento atual prevalecem sobre
este documento.

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

## Goal ativa — Motor Interno Transparente

O usuário autorizou a execução autônoma de R0–R8, sem “Novidades desktop”, com
revisão independente ao fim de cada subfase, staging nominal, um commit próprio
por subfase e push normal somente após o `PASS` integrado final. A autorização
inclui testes, analyzers, verificadores, build e provas runtime isoladas, além de
processos criados pela própria goal com ownership comprovada.

As subfases R0–R8 são arquiteturais. O SQLite Yomu deve permanecer no schema
v5; não haverá bump ou migração artificial. Persistência nova, atualização de
JAR/JRE/SDK/dependência, processo estrangeiro, ownership inconclusiva, licença
não resolvida, mudança das portas ou qualquer outra stop condition do prompt e
do `AGENTS.md` continuam bloqueantes.

Na abertura de R0, Git local, upstream e remoto estavam sincronizados em
`31c6764314ee52d5a9c30efe0b5b291e840f50e9`, divergência zero. As portas 8787 e
14567 estavam livres e não havia Yomu, Java, Dart ou Flutter preexistente.

## Autorizações históricas da P2C

O usuário autorizou a implementação P2C e o único schema bump `4 → 5`.
Também autorizou encerrar somente processos órfãos criados pelas tentativas de
captura visual P2C, sempre após ownership exato, e executar a prova runtime com
perfil isolado. A prova runtime autorizada já foi concluída. Em 2026-07-17, o
usuário autorizou e foi concluído o staging seletivo da allowlist nominal de 32
arquivos. O commit P2C também foi autorizado e concluído:
`eda852bcc17f1b04c5045e32388bf6c78a6945fb`.
O staging seletivo do checkpoint documental pós-P2C, limitado aos seis arquivos
registrados adiante, também foi autorizado. O commit documental foi concluído
em `673734b742c9b0fac99f4090ba0eb14a4d15f175`; o push normal dos dois commits
foi autorizado e concluído. Qualquer nova operação de staging, commit ou push
exige autorização própria. Nunca use `git add .`.

## Repositório e baseline committed

- Repositório: `C:\Users\joaop\Projetos\yomu`.
- Branch: `master`.
- Remoto: `https://github.com/ynkjohn/yomu.git`.
- Na abertura de R0 em 2026-07-18, HEAD local, `origin/master` e
  `ls-remote origin master` estavam em
  `31c6764314ee52d5a9c30efe0b5b291e840f50e9`, divergência zero. Revalide o
  estado efetivo em qualquer retomada.
- O commit P2C é `eda852bcc17f1b04c5045e32388bf6c78a6945fb`
  (`feat(maya): add OpenAI-compatible provider`).
- O handoff pós-P2C é `673734b742c9b0fac99f4090ba0eb14a4d15f175`
  (`docs: record post-P2C handoff`).
- A sincronização factual de publicação é
  `1e195c28e769f1896a32e91016db6afa722134ba`
  (`docs: record P2C publication`).
- O checkpoint posterior do chrome Windows é
  `31c6764314ee52d5a9c30efe0b5b291e840f50e9`
  (`fix(desktop): integrate Windows window chrome`).
- P0, checkpoint pós-P0, P1, P2A, P2B, P2C e seus handoffs estão publicados.
- O schema publicado do SQLite Yomu é v5.

Commits de persistência publicados, em ordem:

1. `941c4e84efc78f5e082abd817d9790b8694dd12a` — P0 schema v1;
2. `c9d51d3e94589ddb72a5d099d208cb66d25a0572` — P1 schema v2;
3. `d200521aa2735c9c245fe53123afe66208fc7404` — P2A schema v3;
4. `7a35094b80b9359327c49e198258fc3c3d255571` — P2B schema v4;
5. `eda852bcc17f1b04c5045e32388bf6c78a6945fb` — P2C schema v5.

Checkpoint documental publicado após P2C:

`673734b742c9b0fac99f4090ba0eb14a4d15f175` — handoff pós-P2C.

A P2C formou um único checkpoint/commit próprio com o bump v5 e não foi
misturada com outra fase de persistência.

## Working tree e proteções

Na abertura da goal atual havia zero staged, 13 arquivos tracked apenas com
status/EOL e hash igual ao índice, 180 untracked protegidos e uma alteração
material preexistente em `AGENTS.md`: a seção “Subagentes e revisão delegada”.
Essa alteração pertence ao working tree inicial e deve ser preservada fora dos
commits da goal; os commits podem incluir somente os hunks produzidos pela goal.

Antes da implementação P2C, o baseline material estava limpo e preservava:

- zero staged;
- 15 tracked status-only/EOL;
- 180 untracked protegidos.

Imediatamente após o commit P2C, a auditoria confirmou zero staged, zero diff
material, os mesmos 15 tracked status-only/EOL e os mesmos 180 untracked
protegidos. Este checkpoint documental pós-P2C altera somente os seis documentos
listados adiante, sem tocar código ou schema.

Os 180 protegidos são:

- 28 em `.playwright-cli/**`;
- 146 em `design_prod/**`;
- 6 em `mcps/tasks/tools/**`.

Essas áreas permanecem intocadas e devem ficar fora de qualquer allowlist.
`pubspec.lock` não mudou. O `crypto: ^3.0.6` foi declarado diretamente no
desktop, mas já estava resolvido e travado no workspace; nenhum SDK ou pacote
foi atualizado.

SHA-256 preservado de
`design_prod\design em producao.html`:

`8DCF41D7283CB16A70A9FA2E0F9D1CE05591F7165AB1AB4FB560D9246A387AC9`

## P2C implementada — contrato

A P2C adiciona um único perfil personalizado `openai-compatible`:

- somente protocolo Chat Completions;
- endpoint e modelo explícitos;
- API key opcional no Windows Credential Manager;
- URL canônica terminando exatamente em `/chat/completions`;
- query, fragmento, userinfo, percent-encoding ambíguo e redirects bloqueados;
- portas aceitas somente em `1..65535`;
- HTTPS somente para endereços públicos;
- HTTP somente para IPv4/IPv6 loopback literal;
- `localhost`, LAN, RFC1918, ULA, link-local, CGNAT, multicast, documentação,
  benchmark e ranges especiais bloqueados;
- DNS resolvido a cada request; resposta privada, vazia ou mista rejeitada;
- conexão TCP no IP validado, sem segunda resolução;
- HTTPS promovido com `SecureSocket.secure(host: hostname)`, preservando SNI e
  validação de certificado;
- proxy forçado a `DIRECT`; nenhum bypass de certificado;
- único header custom possível: `Authorization: Bearer`;
- body fixo com `messages`, tools limitadas, `max_tokens: 1024`,
  `stream: false` e `parallel_tool_calls: false`;
- model ID custom é opaco e limitado, aceita `/` e espaço, mas rejeita
  caracteres de controle;
- tools continuam gerando apenas `ActionProposal` pendente;
- fallback local, lease, cancelamento e shutdown permanecem fail-closed.

O provider OpenAI built-in continua separado em `/v1/responses`.

## Schema v5

O bump v4→v5 adiciona somente
`maya_custom_provider_settings`:

- `settings_id = 1`;
- `endpoint_url` canônica e não secreta;
- `use_api_key`;
- `updated_at_ms`.

A migração é aditiva, cria a tabela vazia, preserva a row P2B e não inventa
perfil custom. O perfil ativo deve ter `updated_at_ms` igual ao
`consented_at_ms` da row geral. Ausência, corrupção ou mismatch não criam
adapter.

Snapshots Drift v1–v5 estão em `packages/yomu_storage/drift_schemas` e
`packages/yomu_storage/test/generated`.

## Credencial e lifecycle

Target custom fixo:

`app.yomu/maya/provider/openai-compatible`

O username WinCred contém `sha256:<digest-do-endpoint-canônico>`. Uma chave só
é lida quando o binding coincide. Alterar endpoint e deixar a chave vazia não
reutiliza o credential anterior. `use_api_key = false` remove e verifica a
ausência do target antes de ativar.

O controller persiste atomicamente o perfil e um snapshot geral disabled antes
de mudar o cofre. Modo local preserva o perfil. Limpeza explícita remove todos
os credentials cloud, apaga o perfil e finaliza local/unset. Falhas deixam
restart duravelmente desativado ou degradado.

## Auditoria arquitetural e de segurança

A revisão confirmou:

- desktop continua Flutter Windows nativo;
- nenhuma mudança em `MayaService`, `ActionProposal`, Core, Suwayomi ou PWA;
- nenhum fato de leitura foi duplicado no Yomu SQLite;
- não há header/body/template arbitrário;
- credencial não entra no SQLite, WAL, SHM, JSON, logs ou erro;
- o achado crítico de TCP puro sob `HttpClient.connectionFactory` foi corrigido
  com promoção TLS explícita e teste de hostname/SNI;
- respostas remotas permanecem não confiáveis e sem autoridade autônoma.

Contrato completo: `docs/p2c-maya-custom-provider.md`.

## Validação atual

- segurança + transporte + adapters: 36/36;
- controller + transporte após hardening: 45/45;
- `packages/yomu_storage`: 39/39;
- Auth afetado pelo schema v5: 16/16;
- desktop completo: 196/196;
- analyzer desktop: limpo;
- analyzer da raiz: limpo;
- `tool\verify_workspace.ps1`: aprovado em 213,6 s;
- build Windows Debug:
  `apps/yomu_desktop/build/windows/x64/runner/Debug/yomu_desktop.exe`;
- `git diff --check`: limpo após o fechamento documental;
- commit P2C `eda852b`: 32 arquivos, parent `d4d6d5b`, committed diff check
  limpo;
- nenhuma chamada live a provider externo foi realizada.

O verificador inicialmente detectou dois problemas reais, ambos corrigidos:

1. snapshot Drift v5 gerado sem data classes tipadas; foi regenerado pela
   ferramenta Drift 2.28.0 com `drift_schema_v5.json`;
2. teste Auth ainda esperava `user_version = 4`; agora comprova migração até v5.

## Evidência visual e processos

A regressão Flutter comprova seleção OpenAI-compatible, destino exato, chave
opcional, consentimento e persistência. Três tentativas de rasterização externa
via `flutter_tester` ficaram presas; todos os PIDs foram revalidados e somente
os runners pertencentes ao teste P2C foram encerrados. O teste temporário foi
removido.

A prova runtime posterior iniciou o build Windows com `APPDATA` e
`LOCALAPPDATA` sob
`C:\Users\joaop\AppData\Local\Temp\yomu-p2c-runtime-53d6bcbf43ca42878ef365da016bbd42`.
O PID 31504 teve executable path e command line confirmados antes da interação.
No diálogo real, foram selecionados/preenchidos:

- provider `OpenAI-compatible`;
- endpoint `http://127.0.0.1:1234/v1/chat/completions`;
- modelo `local-compatible`;
- `Usar API key` desativado.

A captura direta do HWND, sem conteúdo de outras janelas, foi inspecionada e
gravada em
`C:\Users\joaop\Downloads\yomu-sol-final\2026-07-16\02-p2c-maya-custom-provider-dialog.png`,
SHA-256 `182A544A1CA21ADE28C03C1FB16A1B8FCB3D42C84FDA50DEA2F4877E6EF0F0DC`.
O PID 31504 aceitou `CloseMainWindow()` e saiu normalmente. Depois do teardown:

- nenhum Yomu, Java, Dart, Flutter ou `flutter_tester` permaneceu;
- não havia listener em 8787, 14567 ou 11434;
- o runtime root foi verificado como diretório comum, filho direto do Temp
  autorizado, e removido.

Evidência P2B preservada:
`C:\Users\joaop\Downloads\yomu-sol-final\2026-07-16\01-p2b-maya-provider-dialog.png`.

Não abra o build contra o `%APPDATA%` real: isso aplicaria o schema v5 ao banco
real e impediria rollback simples para um binário v4.

## Allowlist nominal usada no commit P2C

O commit `eda852b` contém exatamente esta allowlist de 32 arquivos:

- `README.md`;
- `apps/yomu_desktop/README.md`;
- `apps/yomu_desktop/lib/screens/maya_screen.dart`;
- `apps/yomu_desktop/lib/services/maya_credential_store.dart`;
- `apps/yomu_desktop/lib/services/maya_custom_provider_security.dart`;
- `apps/yomu_desktop/lib/services/maya_provider_adapters.dart`;
- `apps/yomu_desktop/lib/services/maya_provider_codecs.dart`;
- `apps/yomu_desktop/lib/services/maya_provider_controller.dart`;
- `apps/yomu_desktop/lib/services/maya_provider_transport.dart`;
- `apps/yomu_desktop/lib/services/windows_maya_credential_store.dart`;
- `apps/yomu_desktop/pubspec.yaml`;
- `apps/yomu_desktop/test/maya_credential_store_test.dart`;
- `apps/yomu_desktop/test/maya_custom_provider_security_test.dart`;
- `apps/yomu_desktop/test/maya_provider_adapters_test.dart`;
- `apps/yomu_desktop/test/maya_provider_codecs_test.dart`;
- `apps/yomu_desktop/test/maya_provider_controller_test.dart`;
- `apps/yomu_desktop/test/maya_provider_transport_test.dart`;
- `apps/yomu_desktop/test/promoted_regressions_test.dart`;
- `apps/yomu_desktop/test/windows_maya_credential_store_test.dart`;
- `docs/architecture.md`;
- `docs/current-handoff.md`;
- `docs/data-model.md`;
- `docs/p2c-maya-custom-provider.md`;
- `docs/phase-maya-minima.md`;
- `docs/status.md`;
- `packages/yomu_local_server/test/device_auth_test.dart`;
- `packages/yomu_storage/drift_schemas/drift_schema_v5.json`;
- `packages/yomu_storage/lib/src/yomu_database.dart`;
- `packages/yomu_storage/lib/src/yomu_database.g.dart`;
- `packages/yomu_storage/test/generated/schema.dart`;
- `packages/yomu_storage/test/generated/schema_v5.dart`;
- `packages/yomu_storage/test/yomu_database_test.dart`.

Ficam explicitamente fora:

- `design_prod/**`;
- `.playwright-cli/**`;
- `mcps/tasks/tools/**`;
- os 15 tracked status-only/EOL;
- qualquer build, `.dart_tool`, banco, WAL, SHM, log ou artefato temporário.

## Allowlist da sincronização factual de publicação

Esta sincronização pós-push altera somente:

- `README.md`;
- `apps/yomu_desktop/README.md`;
- `docs/architecture.md`;
- `docs/current-handoff.md`;
- `docs/p2c-maya-custom-provider.md`;
- `docs/status.md`.

Qualquer staging desta allowlist de seis documentos exige nova autorização
explícita. Não amplie a lista. Antes de pedir commit ou push, mostre os diffs
correspondentes e revalide hash, processos/portas, status e remoto.

## Limitações e próximo passo

- sem streaming, Responses API custom, múltiplos perfis ou capability
  negotiation;
- sem headers adicionais, templates, proxy do sistema ou certificados custom;
- LAN custom deliberadamente bloqueada;
- OpenRouter, Groq, Together, vLLM, LM Studio e LocalAI não foram testados live;
- PWA/mobile, memória nova, autonomia e Source Builder permanecem fora.

O ciclo P2C está publicado. Esta sincronização factual final permanece separada
de código e schema; staging, commit e eventual push exigem autorizações próprias.

## Checkpoint — chrome da janela Windows

Em 2026-07-17/18, sobre o baseline `master`/`origin/master`
`1e195c28e769f1896a32e91016db6afa722134ba`, o chrome da janela desktop foi
substituído por uma barra Flutter integrada ao app:

- removidos da área visível o ícone nativo e o título `yomu_desktop`;
- título `Yomu` centralizado com `Segoe UI Variable Display`, discreto e
  independente das regiões de drag;
- controles fechar, minimizar e maximizar/restaurar movidos para a barra do app;
- controles renderizam círculos de 12 px, com centros separados por 20 px e
  alvos transparentes de 20 x 40 px, sem caixas ou bordas visíveis;
- a área cliente ocupa toda a janela via `WM_NCCALCSIZE`, removendo a faixa
  cinza superior do frame nativo;
- oito regiões Flutter de 6 px nas bordas e 12 px nos cantos iniciam
  `WM_SYSCOMMAND / SC_SIZE`, preservando resize sem hit-test nativo concorrente;
- a janela continua overlapped, sem `WS_CAPTION`, preservando o ciclo nativo de
  minimizar/restaurar pelo botão da barra de tarefas;
- maximização respeita exatamente a work area do monitor;
- DWM usa dark mode, `DWMWA_COLOR_NONE` para suprimir a moldura e a preferência
  de cantos arredondados do Windows 11;
- fechar pela barra ou por solicitação nativa passa por confirmação explícita;
  cancelar mantém o app aberto, confirmações concorrentes compartilham uma
  única operação e o shutdown coordenado só começa após `Fechar Yomu`.

Validação atual:

- teste direcionado `apps/yomu_desktop/test/widget_test.dart`: 8/8;
- lifecycle direcionado: 17/17;
- suíte desktop: 197/197;
- analyzers da raiz e do desktop: limpos;
- `tool\verify_workspace.ps1`: aprovado em 174,2 s;
- build Windows Debug aprovado em
  `apps/yomu_desktop/build/windows/x64/runner/Debug/yomu_desktop.exe`;
- o usuário confirmou manualmente barra, controles, resize, comportamento da
  barra de tarefas e ausência da moldura branca; o último build com confirmação
  de saída foi aberto antes da autorização deste checkpoint, sem nova regressão
  reportada;
- nenhuma prova visual foi executada pelo agente no monitor 1;
- `git diff --check` limpo e SHA-256 de `design_prod\design em producao.html`
  preservado em
  `8DCF41D7283CB16A70A9FA2E0F9D1CE05591F7165AB1AB4FB560D9246A387AC9`.

Allowlist nominal deste checkpoint:

- `apps/yomu_desktop/lib/services/windows_window_chrome.dart`;
- `apps/yomu_desktop/lib/shell/desktop_lifecycle.dart`;
- `apps/yomu_desktop/lib/shell/home_shell.dart`;
- `apps/yomu_desktop/test/desktop_lifecycle_test.dart`;
- `apps/yomu_desktop/test/widget_test.dart`;
- `apps/yomu_desktop/windows/runner/flutter_window.cpp`;
- `apps/yomu_desktop/windows/runner/flutter_window.h`;
- `apps/yomu_desktop/windows/runner/main.cpp`;
- `apps/yomu_desktop/windows/runner/win32_window.cpp`;
- `apps/yomu_desktop/windows/runner/win32_window.h`;
- `packages/yomu_ui/lib/src/theme/yomu_tokens.dart`;
- `packages/yomu_ui/lib/src/widgets/app_shell.dart`;
- `docs/current-handoff.md`.

Ficam fora todos os demais arquivos status-only/EOL, `design_prod/**`,
`.playwright-cli/**`, `mcps/tasks/tools/**`, builds e artefatos temporários. O
usuário autorizou explicitamente staging nominal, um commit e push normal deste
checkpoint; o resultado efetivo deve ser revalidado no Git após cada operação.

## Checkpoint R1 — fronteira mínima do motor

R1 registra o ADR aceito “Yomu owns a replaceable reading-engine boundary” e
introduz somente a primeira vertical de contratos no `yomu_core`:

- readiness de produto sem PID, Java, porta, URL ou fornecedor;
- falha e exceção tipadas com mensagem sanitizada;
- biblioteca read-only com `LibraryManga` e `LibraryResumePoint`;
- `MediaReference` opaca e fetch de mídia limitado por bytes;
- nenhum catálogo, detalhes, reader, progresso, downloads ou extensões ainda;
- nenhum agregador criado antes do composition root real;
- `SuwayomiStatus` legado permanece temporariamente para consumidores ainda não
  migrados.

R1 não altera dependências, persistência ou ownership. O SQLite permanece no
schema v5. O analyzer inicialmente detectou colisão entre o DTO legado
`MangaSummary` e um nome de domínio igual; o contrato foi estreitado para
`LibraryManga`, eliminando a ambiguidade sem editar consumidores existentes.

Validação de R1:

- `yomu_core`: analyzer limpo e 8/8 testes;
- `yomu_storage`: 39/39;
- analyzer da raiz: limpo;
- `tool\verify_workspace.ps1`: aprovado em 180,7 s;
- desktop completo: 197/197;
- build Windows Debug aprovado;
- `design_prod` preservado;
- nenhuma prova runtime ou processo persistente foi necessário.

## Checkpoint R2 — distribuição offline determinística

R2 parte do commit R1 `98ddc91` e não altera schema, persistência, ownership,
portas, JAR, JRE, SDK ou dependências. O SQLite Yomu permanece no schema v5.

O pin de distribuição agora possui uma única fonte de verdade em
`packages/yomu_suwayomi/vendor/engine_manifest.json`. Os manifests antigos e o
asset Flutter duplicado foram removidos. O manifest tipado rejeita schema,
hash, commit, URL, filename e path relativo inválidos.

Em Profile/Release:

- o manifest é resolvido somente em `{exeDir}/engine`;
- Java é resolvido somente em `{exeDir}/jre`;
- o JAR é aceito somente do bundle, verificado antes da cópia e promovido ao
  runtime gerenciado por temporário + rename;
- não há download de JAR nem fallback para `YOMU_JAVA_HOME`, `JAVA_HOME`, PATH,
  monorepo ou Java arbitrário do sistema;
- CMake inclui JRE, JAR, manifest, PWA e notices e executa o gate offline.

Debug preserva os overrides de desenvolvimento e pode omitir os inputs offline.
`tool\verify_workspace.ps1` continua utilizável nesse modo; o gate completo é
ativado nominalmente por `-VerifyOfflineEngineBundle`.

### GPLv2 §3(a) e MPL-2.0

Cada release que contenha Temurin 21.0.11+10 deve publicar, como assets
separados no mesmo local do binário Yomu:

- `OpenJDK21U-jdk-sources_21.0.11_10.tar.gz` —
  `891a3dd2341c37580fb81b56c4262f135e90c8f2acb059adb6ff0fdd76ae4385`;
- `temurin-build-a612825ee82a20ac872d60958c349854c1f29a8e.tar.gz` —
  `1c0cdcec98d7f43652ad26b7a54f33172089018ca58759ffc6d6fc0ee18ebd3f`;
- `OpenJDK21U-jre_x64_windows_hotspot_21.0.11_10.zip.json` —
  `7fff112ea1f3f24f92113f0626440deb08b9d0f28e73d9fda3a5ef3a5596665c`;
- `Suwayomi-Server-a1770cb0553e37c1f660a88c23afd7badde11328.tar.gz` —
  `d43dd41e2cd86ece24df1ad42c8495edc2729af1ef292f1c3d68ffb509ac4f86`.

O source OpenJDK é vinculado pela proveniência oficial ao commit
`254494ad7d75b37f1c033245fb4dbd460d0347b5`; os scripts Temurin são vinculados
ao commit `a612825ee82a20ac872d60958c349854c1f29a8e`. O gate confirma hashes,
versão, SCM refs, argumentos de build, `configure`, árvore `make/`, documentação
de build, certdata, scripts de certificados, o `NOTICE` do temurin-build e textos
GPLv2, Classpath Exception, Apache-2.0 e MPL-2.0. O JRE conserva `NOTICE` e toda
a árvore `legal/`.

Esses quatro assets e os binários permanecem ignorados pelo Git. Os sources não
entram no instalador. Não existe oferta escrita de três anos; a política adotada
é GPLv2 §3(a). `tool\verify_engine_release.ps1` inspeciona o ZIP publicado e
impede o gate se ele não contiver o bundle pinado ou se o ZIP e o source set não
estiverem diretamente na mesma pasta de release. Instaladores `.exe` permanecem
bloqueados até existir um verificador específico do formato.

### Validação R2

- analyzer do `yomu_suwayomi`: limpo;
- testes direcionados de manifest, Java e distribuição: 12/12 na validação
  inicial e 9/9 na revalidação pós-review;
- `tool\verify_workspace.ps1 -VerifyOfflineEngineBundle`: aprovado;
- `yomu_core`: 8/8;
- `yomu_suwayomi`: 51/51;
- `yomu_local_server`: 38/38;
- `yomu_ai`: 62/62;
- `yomu_storage`: 39/39;
- desktop: 197/197;
- PWA preload e reader races: aprovados;
- build Windows Debug e gate offline: aprovados;
- build Windows Release: aprovado, bundle medido em 338,8 MiB;
- build Windows Profile: aprovado inicialmente e recompilado após a correção do
  gate, bundle medido em 345,8 MiB;
- fetch e verificadores executados com Windows PowerShell 5.1: aprovados;
- gate positivo de release ZIP: aprovado com inspeção direta do executável,
  árvore JRE completa e idêntica ao input canônico, JAR, manifest, notices e PWA
  contidos no arquivo;
- gates negativos falharam fechados para source OpenJDK ausente, build source
  ausente, proveniência ausente, source Suwayomi ausente, hash adulterado e
  material obrigatório ausente;
- revalidação pós-review também rejeitou instalador não inspecionável, build
  source ausente, o antigo parâmetro `BundleRoot` externo e entrada de diretório
  ZIP-slip `../outside/`.

O primeiro install Release revelou que `Get-FileHash` não estava disponível no
Windows PowerShell iniciado pelo CMake. Os verificadores passaram a calcular
SHA-256 diretamente por `System.Security.Cryptography.SHA256`; o mesmo build
Release passou depois da correção.

Nenhum Yomu ou Suwayomi foi iniciado. Somente processos transitórios de build,
teste, PowerShell e `java -version` pertencentes aos gates foram executados. O
bundle Release gerado foi removido após registrar a evidência para liberar
espaço; o Profile permanece como artefato ignorado. `AGENTS.md` continua com a
alteração inicial do usuário e fica fora do commit R2.
