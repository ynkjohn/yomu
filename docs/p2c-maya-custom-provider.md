# P2C — provider personalizado OpenAI-compatible

## Estado

A P2C está concluída e publicada no commit
`eda852bcc17f1b04c5045e32388bf6c78a6945fb`, sobre o parent
`d4d6d5bcb2a6f5ff884adaf000240471e6f87a9a`. Ela contém um único bump Drift
`4 → 5`. O handoff pós-P2C foi publicado em
`673734b742c9b0fac99f4090ba0eb14a4d15f175`.

O escopo permanece exclusivamente no desktop Flutter nativo, no boundary de
provider da Maya e no SQLite específico do Yomu. `MayaService`,
`ActionProposal`, Yomu Core, Suwayomi e PWA não foram alterados.

## Decisões de produto

- existe um único perfil OpenAI-compatible personalizado;
- o protocolo aceito é somente Chat Completions;
- modelo e endpoint são sempre explícitos;
- API key é opcional e, quando usada, fica somente no Windows Credential
  Manager;
- HTTPS é obrigatório para destinos remotos e só aceita endereços públicos;
- HTTP é permitido somente para IPv4 ou IPv6 loopback literal;
- hosts LAN, `localhost`, destinos privados e respostas DNS mistas são
  bloqueados;
- não existem headers, templates, bodies ou redirects configuráveis;
- toda tool call continua virando apenas `ActionProposal` pendente, sem
  execução automática.

## Schema v5

O schema v5 adiciona somente o singleton não secreto
`maya_custom_provider_settings`:

| Coluna | Contrato |
|--------|----------|
| `settings_id` | sempre `1`; primary key |
| `endpoint_url` | URL canônica, trimmed, 1–2048 caracteres |
| `use_api_key` | indica se a ativação exige chave |
| `updated_at_ms` | timestamp não negativo do snapshot |

O singleton geral `maya_provider_settings` continua sendo a fonte de modo,
provider, modelo, consentimentos e estado habilitado. Para uma ativação custom,
`provider_id = openai-compatible`, o modelo é explícito e
`maya_custom_provider_settings.updated_at_ms` deve coincidir com
`maya_provider_settings.consented_at_ms`. Ausência, corrupção ou mismatch
falham fechados antes de criar o adapter.

A migração v4→v5 é aditiva: cria a tabela vazia, preserva integralmente a row
P2B e não inventa um perfil custom. Os snapshots Drift v1–v5 permanecem no
verificador de migração.

## URL, SSRF e TLS

O endpoint é canonicalizado e deve terminar exatamente em
`/chat/completions`. São rejeitados userinfo, query, fragmento, percent-encoding
ambíguo, segmentos vazios ou relativos, portas fora de `1..65535` e qualquer
outro protocolo.

Para cada requisição:

1. o hostname é resolvido novamente;
2. resposta vazia, privada, especial ou mista é rejeitada;
3. o TCP conecta diretamente ao IP validado, sem segunda resolução;
4. em HTTPS, o socket é promovido explicitamente com
   `SecureSocket.secure(host: hostname)`, preservando SNI e validação normal de
   certificado;
5. proxy é forçado a `DIRECT` e certificados inválidos não possuem bypass;
6. redirects permanecem desativados e a origem não pode mudar.

A política pública bloqueia loopback, link-local, multicast, RFC1918, ULA,
CGNAT, ranges de documentação/benchmark e formas IPv4-mapped ou tunneling que
encubram destinos não públicos.

## Credencial

O target WinCred é fixo:

`app.yomu/maya/provider/openai-compatible`

O SHA-256 lowercase da URL canônica é gravado como metadata no username do
credential (`sha256:<digest>`). Uma chave só é retornada quando o binding
pedido coincide. Assim, alterar o endpoint e deixar o campo de chave vazio
nunca reutiliza a chave anterior.

Ao desativar `Usar API key`, o controller remove o target e verifica sua
ausência antes de ativar o perfil. A limpeza cloud remove e verifica todos os
targets conhecidos, apaga o perfil custom e só então finaliza modo local ou
unset. API key não entra no SQLite, WAL, SHM, JSON, logs, linha de comando ou
mensagens de erro.

## Protocolo Chat Completions

O body é fixo e limitado:

- `model` explícito, tratado como identificador opaco de até 200 caracteres;
- `messages` com prompt de sistema confiável, histórico autorizado e contexto
  atual encapsulado como JSON não confiável;
- `tools` somente para `open_manga` e `download_chapter`;
- `max_tokens: 1024`;
- `stream: false`;
- `parallel_tool_calls: false`.

O único header custom possível é `Authorization: Bearer <key>` quando
`use_api_key = true`. O codec Chat Completions é separado do codec OpenAI
Responses; o provider built-in OpenAI continua em `/v1/responses`.

Respostas aceitam texto e tool calls no formato Chat Completions. Nomes,
schemas, argumentos, quantidade e IDs são revalidados localmente. Conteúdo
remoto não ganha autoridade de execução.

## UI e lifecycle

O diálogo da Maya inclui provider OpenAI-compatible, endpoint, modelo, chave
opcional e consentimento que mostra o destino canônico exato. Editar o endpoint
invalida o checkbox de consentimento. Trocar para modo local preserva o perfil;
a limpeza explícita informa e remove perfil e credencial.

Mutações continuam serializadas. Um snapshot disabled é persistido antes de
alterar o cofre; falhas deixam restart fail-closed. Lease de contexto,
cancelamento, fallback local e shutdown permanecem os mesmos da P2B.

## Validação atual

- testes direcionados de segurança, transporte e adapters: 36/36;
- controller + transporte após hardening: 45/45;
- `packages/yomu_storage`: 39/39, incluindo migrações reais v1/v2/v3/v4→v5;
- teste Auth afetado pelo schema v5: 16/16;
- desktop completo: 196/196;
- analyzer da raiz e do desktop: limpos;
- `tool\verify_workspace.ps1`: aprovado em 213,6 s;
- build Windows Debug:
  `apps/yomu_desktop/build/windows/x64/runner/Debug/yomu_desktop.exe`;
- `design_prod\design em producao.html` permaneceu com SHA-256
  `8DCF41D7283CB16A70A9FA2E0F9D1CE05591F7165AB1AB4FB560D9246A387AC9`.

Nenhuma chamada live a provider externo foi realizada. A regressão de UI
comprova seleção custom, destino exato, chave opcional, consentimento e
persistência. A prova runtime foi executada com `APPDATA` e `LOCALAPPDATA`
isolados: o diálogo real mostrou `OpenAI-compatible`, endpoint
`http://127.0.0.1:1234/v1/chat/completions`, modelo `local-compatible` e API key
desativada. A captura somente da janela está em
`C:\Users\joaop\Downloads\yomu-sol-final\2026-07-16\02-p2c-maya-custom-provider-dialog.png`
(SHA-256 `182A544A1CA21ADE28C03C1FB16A1B8FCB3D42C84FDA50DEA2F4877E6EF0F0DC`).
O PID iniciado foi fechado normalmente, o perfil temporário isolado foi removido
e não restaram processos Yomu/Java/Dart/Flutter nem listeners em 8787, 14567 ou
11434.

## Limitações

- não há streaming, Responses API custom, múltiplos perfis ou capability
  negotiation;
- não há headers adicionais, body template, proxy do sistema ou certificado
  customizado;
- instâncias em outro host LAN são deliberadamente bloqueadas;
- OpenRouter, Groq, Together, vLLM, LM Studio e LocalAI são alvos de
  interoperabilidade, não serviços certificados por teste live;
- disponibilidade, cobrança, retenção e políticas de cada provider externo não
  são certificadas;
- PWA/mobile, memória nova, autonomia e Source Builder permanecem fora da P2C.
