# P1 — persistência de sessões e autenticação

## Ownership e schema

Sessões de dispositivos são dados específicos do Yomu. Elas ficam no SQLite
do Yomu; nenhum dado é escrito no banco do Suwayomi.

O P1 migra o schema Drift explicitamente de `1` para `2`. O schema v2 preserva
`app_meta` e adiciona `device_sessions`:

| Coluna | Tipo | Regra |
|--------|------|-------|
| `session_id` | `TEXT` | primary key; identificador opaco e aleatório |
| `token_hash` | `TEXT` | `NOT NULL`, `UNIQUE`, SHA-256 lowercase de 64 caracteres |
| `device_name` | `TEXT` | `NOT NULL` |
| `created_at_ms` | `INTEGER` | `NOT NULL`, epoch em milissegundos |
| `expires_at_ms` | `INTEGER` | `NOT NULL`, epoch em milissegundos |
| `last_seen_at_ms` | `INTEGER` | nullable, epoch em milissegundos |

O bearer entregue no pareamento possui 256 bits aleatórios. Somente seu
SHA-256 lowercase chega à camada de storage. O `session_id` é gerado de forma
independente e é usado pela UI, pela revogação e pelos tickets de mídia.

O token em texto puro existe apenas durante o claim e na resposta HTTP desse
claim. Ele não faz parte de `DeviceSession`, não é persistido e não deve ser
incluído em logs, mensagens de erro ou diagnósticos.

## Migração de `device_sessions.json`

O formato legado efetivamente produzido pelo Yomu é um objeto com a lista
`sessions`. Cada entrada contém `token`, `deviceName`, `createdAt`, `expiresAt`
e `lastSeenAt`. A migração usa o marker
`migration.device_sessions_json.v1` em `app_meta`.

Fluxo:

1. Abre/migra primeiro o SQLite Yomu para o schema v2.
2. Lê os bytes do JSON e calcula seu fingerprint SHA-256.
3. Rejeita fontes maiores que 4 MiB e valida o arquivo inteiro antes de iniciar
   qualquer insert.
4. Descarta sessões expiradas; entre duplicatas ativas do mesmo token, a
   última entrada válida vence.
5. Insere as sessões, já com `token_hash`, e grava o marker na mesma transação.
6. Confirma o marker por readback após o commit.
7. Remove o JSON somente se ele ainda possuir o mesmo fingerprint.

O arquivo não é arquivado: um archive manteria tokens utilizáveis em texto
puro. A remoção só ocorre depois de a transação e o readback comprovarem a
persistência.

Estados conservadores:

- arquivo ausente: grava marker `absent` e não cria sessões;
- lista vazia válida: grava marker `empty`;
- arquivo acima de 4 MiB, malformado, UTF-8 inválido ou entrada inválida:
  aborta, não grava o marker e preserva o arquivo;
- crash dentro da transação: inserts e marker sofrem rollback, permitindo nova
  tentativa;
- crash depois do commit e antes da remoção: o marker impede reimportação e a
  próxima inicialização apenas conclui a remoção do mesmo arquivo;
- arquivo com fingerprint diferente após um marker: bloqueia e preserva o
  arquivo;
- arquivo que aparece depois de marker `absent`: bloqueia e preserva o arquivo.

Essas regras impedem que uma sessão já revogada seja recriada por um JSON
residual.

## Concorrência e lifecycle

`issue`, autenticação/`last_seen`, expiração e revogações usam uma única fila de
mutações. O cache em memória só é atualizado depois de a operação SQLite
correspondente concluir.

O bootstrap segue a ordem:

1. lock exclusivo e SQLite;
2. migração/carga do Auth;
3. Maya, Suwayomi e Yomu Core.

Se o Auth ou a migração falhar, os demais serviços não iniciam. No teardown, o
HTTP para primeiro; depois `DeviceAuthStore.close()` deixa de aceitar novas
mutações e drena as já admitidas; só então Suwayomi e SQLite são encerrados.

Revogar uma sessão, um dispositivo ou todas as sessões remove os registros do
SQLite. Sessões expiradas são rejeitadas e removidas. Nenhuma dessas operações
altera catálogo, capítulos, progresso ou qualquer outro fato pertencente ao
Suwayomi.
