# Yomu — handoff atual

Snapshot factual preparado em 2026-07-16 durante o fechamento da P2C. Código,
diff e comportamento atual prevalecem sobre este documento.

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

## Autorizações e stop conditions

O usuário autorizou a implementação P2C e o único schema bump `4 → 5`.
Também autorizou encerrar somente processos órfãos criados pelas tentativas de
captura visual P2C, sempre após ownership exato, e executar a prova runtime com
perfil isolado. A prova runtime autorizada já foi concluída. Em 2026-07-17, o
usuário autorizou e foi concluído o staging seletivo da allowlist nominal de 32
arquivos. O commit P2C também foi autorizado e concluído:
`eda852bcc17f1b04c5045e32388bf6c78a6945fb`.
O staging seletivo do checkpoint documental pós-P2C, limitado aos seis arquivos
registrados adiante, também foi autorizado. Essa autorização não inclui o
commit documental nem o push.

Ainda não há autorização para:

- push.

Não faça push sem autorização explícita própria. Nunca use `git add .`; qualquer
novo staging deve seguir uma allowlist nominal revisada.

## Repositório e baseline committed

- Repositório: `C:\Users\joaop\Projetos\yomu`.
- Branch: `master`.
- Remoto: `https://github.com/ynkjohn/yomu.git`.
- A linha local contém o commit P2C
  `eda852bcc17f1b04c5045e32388bf6c78a6945fb` e este checkpoint documental
  posterior; revalide o HEAD efetivo no Git.
- `origin/master` e `ls-remote origin master`:
  `d4d6d5bcb2a6f5ff884adaf000240471e6f87a9a`.
- Nenhum push foi autorizado; revalide a divergência local/remota.
- O commit P2C é `feat(maya): add OpenAI-compatible provider`; o checkpoint
  documental pós-P2C é o commit seguinte e deve ter o hash lido do Git.
- P0, checkpoint pós-P0, P1, P2A, P2B e o handoff pós-P2B estão publicados.
- A P2C está commitada apenas localmente; o schema local é v5 e o remoto ainda
  aponta para o checkpoint pós-P2B/schema v4.

Commits de persistência em ordem; os quatro primeiros estão publicados e o
quinto ainda é local:

1. `941c4e84efc78f5e082abd817d9790b8694dd12a` — P0 schema v1;
2. `c9d51d3e94589ddb72a5d099d208cb66d25a0572` — P1 schema v2;
3. `d200521aa2735c9c245fe53123afe66208fc7404` — P2A schema v3;
4. `7a35094b80b9359327c49e198258fc3c3d255571` — P2B schema v4;
5. `eda852bcc17f1b04c5045e32388bf6c78a6945fb` — P2C schema v5.

A P2C formou um único checkpoint/commit próprio com o bump v5 e não foi
misturada com outra fase de persistência.

## Working tree e proteções

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

## Allowlist proposta para o checkpoint documental pós-P2C

Este fechamento factual altera somente:

- `README.md`;
- `apps/yomu_desktop/README.md`;
- `docs/architecture.md`;
- `docs/current-handoff.md`;
- `docs/p2c-maya-custom-provider.md`;
- `docs/status.md`.

O staging desta allowlist de seis documentos foi autorizado em 2026-07-17. Não
amplie o índice sem nova autorização explícita. Antes de pedir o commit, mostre
o staged diff e revalide hash, processos/portas, `git diff --check` e status.

## Limitações e próximo passo

- sem streaming, Responses API custom, múltiplos perfis ou capability
  negotiation;
- sem headers adicionais, templates, proxy do sistema ou certificados custom;
- LAN custom deliberadamente bloqueada;
- OpenRouter, Groq, Together, vLLM, LM Studio e LocalAI não foram testados live;
- PWA/mobile, memória nova, autonomia e Source Builder permanecem fora.

Staging, commit e push permanecem operações com autorizações próprias. Após o
staging documental, mostre o staged diff antes de pedir o commit; push exige
autorização posterior própria.
