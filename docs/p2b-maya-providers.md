# P2B — providers da Maya

## Estado atual

A implementação P2B contém schema v4, cofre WinCred, controlador, adapters,
codecs/transport, UI de configuração e composição no bootstrap desktop. O
`home_shell` cria o `MayaProviderController` com a factory HTTP real, injeta-o
em `MayaService.llm` e o expõe à `MayaScreen`.

Essa camada permanece opcional: `OptionalMayaProviderBootstrap` impede que uma
falha ao abrir o controlador derrube o histórico ou o engine local da Maya. A
compatibilidade live com contas e modelos reais de cada provider ainda não foi
certificada. Este documento não alega disponibilidade de serviço externo.

## Ownership e escopo

A P2B adiciona providers opcionais à Maya do desktop nativo. O modo local
continua sendo o comportamento seguro quando não há configuração cloud válida
ou quando uma chamada ao provider falha.

Esta subfase eleva o SQLite Yomu de `3` para `4` somente para persistir a
configuração não secreta do provider. Ela não altera o banco Suwayomi nem
transfere para o Yomu ownership de catálogo, capítulos, downloads, progresso
ou fatos de leitura.

## Schema v4

O schema v4 preserva `app_meta`, `device_sessions`, `maya_messages` e
`maya_action_proposals` e adiciona a tabela singleton
`maya_provider_settings`, cuja única chave válida é `settings_id = 1`.

A row armazena:

- modo `local` ou `cloud`;
- estado habilitado/desabilitado da configuração cloud;
- ID do provider, com allowlist aplicada pelo controlador;
- política e ID do modelo;
- consentimentos separados para histórico recente e contexto da biblioteca;
- versão e timestamp do consentimento cloud;
- timestamp da última atualização.

Ausência da row significa “nunca configurado” e é diferente de uma row
explícita em modo `local`. O modo local exige `is_enabled = 0`, provider,
modelo e consentimentos nulos, além das flags cloud desativadas. O modo cloud
exige provider, política de modelo, versão positiva de consentimento e
timestamp coerente; `is_enabled = 0` representa uma barreira durável
fail-closed durante falha, cleanup ou recuperação.

A migração `3 → 4` é aditiva e cria somente essa tabela. Não existe arquivo
JSON de provider a importar. Instalações em schemas anteriores executam os
passos forward `1 → 2 → 3 → 4` em ordem. Não há downgrade automático.

Credenciais, prompts completos, respostas remotas cruas e snapshots da
biblioteca não pertencem a essa tabela.

## Providers, modelos e destinos

Somente estes providers são aceitos:

| Provider | Destino fixo | Credencial |
|----------|--------------|------------|
| OpenAI | `https://api.openai.com/v1/responses` | API key no WinCred |
| Anthropic | `https://api.anthropic.com/v1/messages` | API key no WinCred |
| Gemini | `https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent` | API key no WinCred |
| Ollama | `http://127.0.0.1:11434/api/chat` | nenhuma |

Não existe campo para endpoint arbitrário. HTTPS é obrigatório para os
providers externos; HTTP é permitido somente para o IP loopback literal do
Ollama. Redirects não são seguidos.

A UI da P2B exige o ID exato do modelo e grava política `explicit`. Os adapters
concretos também rejeitam `provider_default`; o enum permanece no schema como
estado tipado, mas não seleciona modelo automaticamente nesta implementação.
O Yomu não escolhe modelo, preço ou capacidade em nome do usuário.

As chamadas são não streaming, limitam a saída a 1024 tokens pelo campo nativo
de cada provider e usam uma resposta JSON com limite de bytes. Não há conexão
persistente, execução em background ou continuação autônoma.

## Credenciais

OpenAI, Anthropic e Gemini usam exclusivamente o Windows Credential Manager,
com target `app.yomu/maya/provider/{providerId}`. A chave plaintext não é
gravada no SQLite, JSON, variáveis de ambiente, argumentos de processo, logs ou
mensagens de erro.

Ao ativar cloud, o controlador primeiro persiste no SQLite o snapshot candidato
com `is_enabled = 0` e fecha o adapter anterior. Só depois captura a credencial
anterior e faz write/readback do WinCred. O snapshot muda para
`is_enabled = 1` somente após a credencial estar verificada. Se o readback ou o
commit ativo falhar, ele tenta restaurar e verificar a credencial anterior, ou
remover o target quando antes não existia; independentemente do resultado da
compensação, o snapshot durável continua desabilitado e o adapter não é
reativado automaticamente.
A factory recebe apenas um callback de leitura: a chave é buscada just-in-time
dentro de uma requisição já admitida, usada nos headers e descartada do estado
do adapter ao final. Buffers nativos são sobrescritos antes de serem liberados
quando tecnicamente possível; strings gerenciadas pelo Dart não oferecem
apagamento garantido.

WinCred e SQLite não possuem transação distribuída. Um encerramento abrupto
entre o write do cofre e o commit ativo ainda pode deixar uma credencial retida
no target determinístico, mas o snapshot candidato já está desabilitado e não
é carregado como provider ativo no restart. A remoção explícita percorre todos
os targets cloud conhecidos para oferecer cleanup idempotente desse estado.

Ollama ignora qualquer chave fornecida, não consulta o WinCred e usa somente o
loopback fixo.

O loopback reduz a superfície de rede, mas não autentica a identidade do
processo que ocupa `127.0.0.1:11434`. Um processo local hostil poderia se passar
pelo Ollama e receber somente o contexto que o usuário autorizou compartilhar.
Esse risco local residual não habilita ações automáticas: tool calls continuam
passando por `ActionProposal` e confirmação explícita.

Se o Windows Credential Manager não puder ser carregado, o composition root
injeta `UnavailableMayaCredentialStore`. Essa implementação não redireciona
segredos para disco ou memória persistente: operações de chave falham fechadas,
enquanto modo local e Ollama continuam disponíveis. Uma configuração externa
já persistida é apresentada como cofre indisponível e segue para fallback
local, sem tentativa de rede sem credencial.

## Consentimento e contexto

Ativar cloud exige consentimento da versão atual para enviar a mensagem
corrente. Compartilhar histórico recente e compartilhar contexto da biblioteca
são escolhas independentes, desativadas por padrão e persistidas na row v4.

Os limites atuais são:

- mensagem corrente: até 32 KiB;
- histórico: até 12 mensagens e 32 KiB;
- biblioteca: até 30 itens e 48 KiB.

Mensagens `system` persistidas nunca entram no histórico enviado. O snapshot
da biblioteca é transitório, limitado e não copia o banco Suwayomi para o
SQLite Yomu.

Consentimento com versão antiga desabilita cloud até nova confirmação. Se a
configuração possui consentimento atual, mas a credencial ou o adapter está
indisponível, nenhum transporte recebe o contexto: a tentativa falha de forma
tipada e o `MayaService` registra uma resposta explícita em modo local
`fallback`. Falhas remotas, timeout, resposta inválida e cancelamento também
não expõem corpos, prompts ou credenciais em erros.

Cada policy cloud habilitada contém ainda um lease opaco e não persistível da
configuração ativa. O `MayaService` copia esse lease por identidade para o
request depois de montar o contexto. Qualquer troca de provider, modelo,
consentimento, remoção ou shutdown invalida o lease antes de qualquer `await`;
um request preparado sob a configuração anterior é rejeitado antes de chegar
ao adapter novo, inclusive se estava aguardando o snapshot da biblioteca.

## `ActionProposal` e ausência de autonomia

O provider nunca executa uma ação. Ele pode retornar somente intenções
estruturadas allowlisted. Nesta subfase, as intenções cloud possíveis são abrir
uma obra e propor o download do último capítulo presente no snapshot exato que
foi compartilhado.

O `MayaService` valida cada intenção contra esse snapshot, descarta IDs e tools
incompatíveis e cria localmente um `ActionProposal` canônico em estado
`pending`. A execução continua exigindo confirmação explícita e respeita a
barreira durável at-most-once da P2A: nenhuma resposta de provider contorna
`ActionProposal`, executa efeitos automaticamente ou repete resultado ambíguo.

## Retenção e remoção

A configuração v4 é substituída como snapshot completo. Escolher modo local
mantém uma row local e não apaga credenciais. Trocar de provider também não
apaga automaticamente a chave do provider anterior; as credenciais são
mantidas separadamente por provider no WinCred.

"Limpar credenciais cloud" permanece disponível mesmo em modo local ou sem
configuração, para alcançar chaves retidas por trocas e falhas anteriores. A
ação cancela e drena requisições, fecha o adapter e percorre os targets de
OpenAI, Anthropic e Gemini, verificando que todos ficaram ausentes. Antes do
cleanup, uma configuração cloud é persistida com `is_enabled = 0`; o provider
atualmente configurado é limpo por último. Somente depois do cleanup o
controlador persiste modo local; o reset interno persiste ausência da row. Se
qualquer delete/readback ou a persistência final falhar, o adapter não é
reativado e o snapshot cloud desabilitado fica disponível para uma nova
tentativa. O restart respeita esse marker sem criar adapter. O cleanup é
idempotente e também alcança chaves retidas por trocas ou falhas anteriores.

Se a própria gravação inicial do marker falhar, nenhuma garantia durável pode
ser criada naquele banco indisponível. Nesse caso o controlador fecha o adapter
e tenta limpar as credenciais conhecidas antes de retornar erro; a operação não
é declarada concluída e deve ser repetida depois que o storage voltar.

Remover ou trocar provider não apaga `maya_messages` nem
`maya_action_proposals`. O histórico segue a política de retenção e limpeza
explícita da P2A. Contextos montados para uma chamada não ganham uma store
própria; a resposta aceita é persistida apenas como a mensagem normal da
conversa. Retenção realizada pelo serviço externo, após envio consentido, é
regida pela conta e pelos termos do respectivo provider, não pelo SQLite Yomu.

## Fora de escopo

A P2B não adiciona:

- memória inferida ou memória de longo prazo;
- múltiplas conversas ou perfis da Maya;
- streaming de tokens;
- agentes, tarefas autônomas ou execução em background;
- endpoints personalizados ou providers fora da allowlist;
- providers, configuração ou chat da Maya na PWA;
- alterações no Yomu Core, no banco Suwayomi ou no Source Builder.

O painel de “Memória da Maya” continua explicitamente não implementado e seu
controle de exclusão permanece desabilitado.
