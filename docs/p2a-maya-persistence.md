# P2A — persistência da Maya

## Ownership e escopo

Mensagens da Maya e `ActionProposal` são dados específicos do Yomu. O P2A
migra esses dados do arquivo legado `maya_chat.json` para o SQLite Yomu e
eleva o schema explicitamente de `2` para `3`.

Esta fase não adiciona providers, credenciais, memória de longo prazo,
múltiplas conversas ou novas capacidades da Maya. Catálogo, capítulos,
downloads, progresso e demais fatos de leitura continuam pertencendo ao
Suwayomi.

## Schema v3

O schema v3 preserva integralmente `app_meta` e `device_sessions` e adiciona
somente:

- `maya_messages`: mensagens ordenadas do histórico atual;
- `maya_action_proposals`: propostas vinculadas opcionalmente à mensagem que
  as apresentou.

Roles, tipos de ação e estados possuem `CHECK` no SQLite. A relação com a
mensagem usa foreign key com cascade. A ordem das mensagens e das propostas é
explícita, sem depender de timestamps iguais ou da ordem incidental de uma
consulta.

O payload de uma proposta é um snapshot da intenção confirmável. IDs de manga
ou capítulo nele contidos não transformam o SQLite Yomu em fonte de verdade
para dados do Suwayomi.

## Migração de `maya_chat.json`

O formato legado produzido pelo Yomu é um objeto sem campo de versão:

```json
{
  "messages": [],
  "proposals": []
}
```

Cada mensagem contém `id`, `role`, `text`, `createdAt` e `proposalIds`. Cada
proposta contém `id`, `kind`, `title`, `description`, `payload`, `status`,
`createdAt` e `error`.

A migração usa o marker `migration.maya_chat_json.v1` em `app_meta`:

1. limita a fonte a 4 MiB e exige UTF-8 válido;
2. valida o snapshot inteiro antes de qualquer insert;
3. rejeita enums desconhecidos, datas inválidas, IDs duplicados, referências
   inconsistentes e payload incompatível com o tipo de ação;
4. grava mensagens, propostas e marker na mesma transação;
5. confirma por readback integral e semântico o marker, conteúdo, ordem,
   vínculos, payloads e estados persistidos;
6. captura a fonte inalterada com nome imprevisível e somente então publica o
   archive `maya_chat.json.migrated-v1.<sha256>.<archiveNonce>.bak` por move
   atômico sem substituição no Windows.

Um arquivo de zero bytes é malformado. Um objeto válido com as duas listas
vazias representa uma fonte vazia.

O marker commitado sempre vence um arquivo residual. Após crash, o arquivo só
pode concluir o archive quando seu fingerprint ainda for o mesmo; ele nunca é
reimportado. Antes de concluir um archive residual, o restart repete o parsing
da captura e a validação integral do SQLite contra a fonte. Markers antigos sem
`archiveNonce` continuam reconhecidos e são finalizados pelo mesmo protocolo
atômico.

O publish usa `MoveFileExW` sem `REPLACE_EXISTING` nem cópia entre volumes. Um
arquivo que apareça no destino durante a corrida nunca é sobrescrito: destino
e captura são preservados e a migração falha fechada. Leituras de fonte,
captura, archive ou caminho reaparecido são limitadas a 4 MiB por handle, sem
alocação ilimitada. Uma fonte diferente após o marker é preservada e
sinalizada, sem sobrescrever o SQLite.

Capturas interrompidas de archive ou limpeza possuem padrões reconhecíveis.
Se o banco/marker desaparecer enquanto uma captura ainda retém o único
histórico, o bootstrap não grava um marker `absent`: ele bloqueia a migração e
preserva o arquivo para recuperação conservadora.

No código legado, `downloadChapter` e `setInLibrary` executavam o efeito antes
de gravar o novo status no JSON. Assim, uma proposta mutável ainda marcada como
`pending` não prova que o efeito nunca aconteceu. A migração coloca essas
propostas em `confirmed`, com resultado incerto e sem possibilidade de nova
execução automática. `openManga` pode continuar `pending`, pois a navegação da
UI só ocorria depois de um save bem-sucedido.

Como o JSON legado não possui `confirmedAt` nem `completedAt`, a migração usa
`createdAt` como timestamp sintético nos campos exigidos pelo estado
normalizado. Esses valores preservam as invariantes do schema, mas não
representam o instante histórico real de confirmação ou conclusão.

JSON malformado não é ignorado nem convertido parcialmente. O arquivo original
permanece intacto, a Maya fica indisponível com erro sanitizado e os serviços
obrigatórios — Auth, Core e Suwayomi — continuam inicializando. Falha do SQLite
ou do schema não é tratada como opcional e continua fatal para o bootstrap.
Exceções cruas gravadas por versões antigas em `ActionProposal.error` ou nas
mensagens `m-err-*`/`m-fail-*` são substituídas antes da persistência; seu
conteúdo não entra no SQLite nem em mensagens da UI.

## Segurança de `ActionProposal`

O Suwayomi não oferece uma idempotency key compartilhada com o SQLite Yomu.
Portanto, a garantia possível é **at-most-once**, não exactly-once:

1. somente `pending` pode consumir uma confirmação explícita;
2. `pending → confirmed` é persistido antes de qualquer efeito externo;
3. somente depois do commit o port Suwayomi pode ser chamado;
4. sucesso confirmado persiste `confirmed → executed`;
5. uma proposta que permaneça `confirmed` após crash ou resultado ambíguo
   nunca é executada automaticamente de novo.

`confirmed` é uma barreira durável: pode significar que a tentativa foi
admitida, mas seu resultado final não pôde ser comprovado. A UI não oferece um
segundo botão de execução para esse estado. Falhas comprovadamente anteriores
ao efeito podem terminar como `failed`; detalhes crus de exceções externas não
são persistidos nem exibidos.

## Concorrência e lifecycle

Envio, confirmação, rejeição e limpeza usam uma única fila de mutações. O cache
em memória só muda depois do commit correspondente. Confirmações concorrentes
da mesma proposta podem produzir no máximo uma chamada ao port.

`close()` bloqueia novas mutações e drena as operações já admitidas. O teardown
segue a ordem:

1. subscription de status;
2. Yomu Core HTTP;
3. Maya e seus writes pendentes;
4. Auth e seus writes pendentes;
5. Suwayomi;
6. SQLite Yomu.

Assim, a Maya não perde o banco antes de persistir e uma confirmação já em voo
não perde o port Suwayomi antes de terminar.

## Retenção e exclusão

O histórico permanece local e é retido até a limpeza explícita já confirmada
pela UI. Limpar o histórico remove mensagens e propostas em uma transação e
também remove a fonte/archive legado correspondente. Não existe memória
inferida ou envio para provider nesta fase. Capturas temporárias só permanecem
quando uma corrida, crash ou divergência impede provar uma exclusão segura; o
restart as reconhece e nunca as trata como histórico ausente.

A guarda contra propostas `confirmed`, a limpeza legada e o delete do SQLite
ficam serializados na mesma transação SQLite. Fonte e archive são primeiro
movidos para captures aleatórias, verificados por fingerprint e só então
apagados. Restores usam move atômico sem substituição; um caminho reaparecido
igual permite descartar a captura, enquanto um caminho divergente, ilegível ou
acima de 4 MiB preserva a captura. Se o write do SQLite falhar, banco e cache
continuam com o histórico autoritativo, embora um backup legado já validado
possa ter sido removido; repetir a limpeza é seguro.

Por recuperabilidade, o archive é uma cópia byte-exata da fonte e pode manter
texto bruto gravado por versões antigas até a limpeza explícita. Ele permanece
local sob as mesmas permissões do diretório Yomu e nunca é enviado a provider.
A exclusão usa `DELETE` no SQLite e remoção normal de arquivo; não promete
apagamento forense dos blocos físicos.

## Validação exigida

- criação limpa de schema v3;
- migrações reais `1 → 2 → 3` e `2 → 3`;
- preservação de `app_meta` e `device_sessions`;
- JSON válido, vazio, ausente, malformado e acima do limite;
- duplicatas, enums/datas/payloads inválidos e referências inconsistentes;
- rollback dentro da transação e restart após commit antes do archive;
- idempotência, readback integral/semântico, fingerprint divergente e conflito
  de archive;
- corrida de publish sem overwrite, restart pré/pós-publish e compatibilidade
  com marker/archive anterior ao nonce;
- captures de limpeza com marker ausente/`absent`, destino reaparecido e limite
  de 4 MiB;
- quarentena sem redispatch de ações mutáveis `pending` do JSON legado;
- confirmação, rejeição, resultado ambíguo e não reexecução após crash;
- concorrência, limpeza, close e teardown com writes pendentes;
- regressões completas de storage, Maya e desktop.
