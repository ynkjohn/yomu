# F0 — reconciliação factual e contratos de produto

**Status:** decisões de contrato aprovadas pelo usuário e documentadas em F0.
F0 é somente uma reconciliação factual: não cria schema, não implementa F1,
não altera código, UI, processos ou dados do usuário.

**Baseline committed:** master em
0a5a0c5db130e0c51f48eb27dcd75d063c0670c6
(feat(engine): add diagnostics and guard), que concluiu R8. O schema Yomu
publicado continua v5.

## Limites e evidências da auditoria

- Desktop continua Flutter Windows nativo; não há Electron, WebView, Docker nem
  alteração das portas fixas.
- O motor continua dono de biblioteca, capítulos, progresso, isRead,
  lastReadAt, downloads, extensões e repositórios. SQLite Yomu guarda apenas
  estado próprio do app; não duplica esses fatos.
- Yomu Core fica em 127.0.0.1:8787 por padrão e o motor em
  127.0.0.1:14567; LAN/PWA continua opt-in e fail-closed.
- Maya continua local-first, e toda mutação continua passando por
  ActionProposal e confirmação explícita.
- A auditoria de capacidade usou somente leitura: introspecção GraphQL e
  GET /api/v1/settings/about no motor já aberto do usuário. Não consultou
  biblioteca, capítulos, sessões ou conteúdo pessoal e não executou mutações.
  A instância informou v2.3.2238, r2238, Stable, compatível com o JAR pinado.
- Na abertura da F0 não havia alterações staged. O working tree inicial já
  continha o diff material de AGENTS.md, arquivos Windows somente com
  status/EOL e áreas protegidas untracked. As mudanças desta sessão são
  exclusivamente documentação; YOMU_PLAN_POS_R8.md continua untracked e
  explicitamente fora de qualquer checkpoint.
- design_prod/**, .playwright-cli/** e mcps/tasks/tools/** permanecem
  intocados. O SHA-256 de design_prod/design em producao.html é
  8DCF41D7283CB16A70A9FA2E0F9D1CE05591F7165AB1AB4FB560D9246A387AC9.

## Matriz factual das superfícies atuais

| Superfície | Fatos/capacidades atuais | Situação contratual F0 |
|---|---|---|
| Home | não lidos e última leitura via motor | não é a rota de Novidades; preserva fatos do motor |
| Biblioteca, detalhe e leitor | biblioteca, capítulos, páginas, progresso e mídia | funcional; não duplicar fatos de leitura |
| Novidades | placeholder, sem estado próprio | F3 futura, conforme contrato de watermark abaixo |
| Histórico | placeholder, sem estado próprio | F2 futura; consulta pode derivar do motor, ocultação será apenas Yomu |
| Explorar/fontes | catálogo, busca, popular, recentes e extensões instaladas | troca de fonte assistida é futura; não há migração nativa |
| Downloads | fila, estados, pause/resume e clear | motor é o dono; métricas/remoção física não estão autorizadas |
| Maya | conversa, providers opcionais e propostas confirmadas | mantém as fronteiras já publicadas |
| Configurações e Backup | placeholders | F1/F7 futuras; F0 só fixa contratos |
| Servidor e Diagnóstico | LAN, pareamento/sessões e detalhes do motor | superfícies R8 atuais; a nova organização de navegação ainda não foi implementada |
| PWA | biblioteca, leitura, progresso, logout e busca | LAN opt-in; não ganha Histórico, Novidades, Settings ou Backup em F0 |
| Criador de fontes | placeholder visível | sai da interface V1; F0 não o remove da UI atual |

## Capacidades verificadas no motor

### Histórico e marcadores

chapters aceita paginação/filtros e ordenação por LAST_READ_AT. ChapterType
expõe, entre outros, id, lastReadAt, lastPageRead, isRead, isBookmarked,
mangaId e manga; MangaType expõe latestReadChapter. Assim, uma consulta de
retomada pode vir do motor sem copiar progresso ao Yomu.

O patch de capítulo aceita apenas lastPageRead, isRead e isBookmarked. Não há
mutação auditada para limpar ou ocultar lastReadAt.

### Novidades

O motor expõe atualização explícita de biblioteca, libraryUpdateStatus,
lastUpdateTimestamp, identidades estáveis de manga/capítulo, fetchedAt,
uploadDate, chaptersLastFetchedAt, latestFetchedChapter,
latestUploadedChapter e unreadCount. Não há, contudo, log de “já visto pelo
Yomu”; essa semântica precisa de estado de apresentação mínimo do Yomu.

### Fontes, repositórios e downloads

O motor expõe updateExtension com install, uninstall e update, além de
addExtensionStore e removeExtensionStore. Não existe migrateManga, e
UpdateMangaPatchInput aceita somente inLibrary.

Downloads têm fila/status e as ações enqueue, dequeue, pause, resume, clear e
deleteDownloadedChapter(s). O contrato atual não expõe tamanho, espaço
disponível ou root seguro de arquivos; métricas ou remoção física exigem
capacidade específica e validação futura de ownership/root.

## Contratos de produto aprovados

### Histórico — apresentação agrupada, fatos preservados

A apresentação principal pode agrupar entradas por obra. Mesmo nesse formato,
o contrato entre query, gateway e UI preservará o par do fato de origem:
chapterId e lastReadAt. A obra agrupada aponta para o capítulo mais recente
que a representa, sem transformar esse resumo em novo fato de leitura do Yomu.

Ocultar uma entrada ou usar “limpar Histórico” significa criar somente uma
supressão de apresentação local do Yomu. A futura supressão/tombstone precisa
guardar a identidade estável do seu escopo (obra ou capítulo) e o lastReadAt
**observado** quando o usuário a ocultou. Ela nunca pode escrever progresso,
isRead ou lastReadAt no motor.

- Para uma entrada por capítulo, ela reaparece quando o mesmo capítulo tiver
  lastReadAt mais novo que o valor observado.
- Para uma entrada agrupada por obra, ela reaparece quando qualquer leitura
  pertinente àquela obra produzir lastReadAt mais novo que o valor observado.
- Timestamp igual ou anterior mantém a ocultação; a limpeza não apaga nem
  reinicializa os fatos pertencentes ao motor.

F2 deverá introduzir um gateway/modelo próprio para esses campos e, se a
persistência for necessária, avaliar uma tabela Yomu própria em sua fase. F0
não cria essa tabela nem reserva schema.

### Configurações — schema v6 tipado, mas não nesta fase

As configurações de produto aprovadas para F1 usarão o futuro schema v6 com
campos e tipos explícitos, defaults, validação e tratamento de corrupção. Não
se usará app_meta como JSON genérico ou saco de configurações. app_meta
continua limitado a flags e markers de migração reconhecidos.

F0 não cria schema, migração, snapshot Drift, tabela, UI ou implementação de
F1. A implementação de F1 começará em uma fase própria, com o schema v6 e os
gates aplicáveis.

### Novidades — watermark mínimo por obra e identidade estável

Novidades é uma visão de detecção, não uma cópia do catálogo. F3 persistirá
apenas um cursor/watermark mínimo por obra e identidade estável do
motor, incluindo a identidade opaca da obra e as identidades de capítulo
necessárias na fronteira. Um timestamp global único é proibido.

O cursor por obra deverá manter somente a fronteira de observação e um conjunto
limitado de identidades estáveis necessário para desempatar a fronteira ou
retomar uma sincronização. Ele não pode armazenar metadados de catálogo nem a
lista integral de capítulos. A ordenação de exibição é derivada novamente do
motor; a posição de um capítulo na lista nunca é sua identidade.

- **Primeira sincronização:** após leitura completa e bem-sucedida da obra/fonte
  coberta, grava a baseline sem transformar o acervo já existente em uma onda
  de novidades. Até isso ocorrer, o estado é “sincronização inicial”, não zero
  enganoso.
- **Capítulo retroativo:** uma identidade de capítulo antes não observada após a
  baseline pode ser nova mesmo que uploadDate seja antigo. A detecção usa a
  identidade estável e a observação por obra, não apenas ordem cronológica.
- **Reordenação:** mover capítulos, alterar paginação ou empatar timestamps não
  cria novidade nem perde detecção; o desempate é feito pelas identidades na
  fronteira.
- **Remoção:** o desaparecimento de uma entrada não é novidade e não reseta nem
  avança o watermark. Estado só pode ser descartado por política explícita
  futura, nunca como efeito de uma resposta incompleta.
- **Fonte parcialmente indisponível:** a cobertura parcial é exibida como tal;
  não avança watermark, não conclui baseline e não faz prune da obra/fonte
  afetada. Obras/fontes verificadas com sucesso podem avançar de forma
  independente.

F0 não cria persistência de Novidades. F3 deverá definir a forma tipada mínima,
migração e testes antes de qualquer write.

### Troca de fonte assistida — sem promessa de migração

F5 usará somente a expressão **troca de fonte assistida**. Ela poderá ajudar a
localizar uma obra de destino, verificar que a fonte está acessível e apresentar
ao usuário título/identidade/capítulos disponíveis para validação. Não há
migrateManga no motor auditado, portanto ela não prometerá transferir
progresso, Histórico ou downloads.

A obra original permanece intacta durante descoberta, validação e escolha do
destino. Somente depois da validação do destino e de uma confirmação final
explícita poderá haver uma ação separada sobre a obra original; a remoção nunca
é automática nem antecede essas duas condições.

### Backup e restauração — privacidade e fail-closed

Backup Yomu nunca inclui banco do motor, biblioteca, capítulos, progresso,
downloads, extensões ou credenciais do Windows Credential Manager. O arquivo de
backup aceita somente dados Yomu reconhecidos; não importa JSON arbitrário em
app_meta.

| Área | Regra aprovada |
|---|---|
| Sessões/PWA | excluídas por padrão; uma inclusão futura exige opt-in explícito |
| Credenciais WinCred | nunca exportadas |
| Conversas e memória Maya | mensagens/propostas e qualquer memória futura ficam excluídas salvo opt-in explícito |
| Provider Maya | pode restaurar somente configuração não secreta; sem uma nova configuração e credencial, cloud permanece desabilitada |
| LAN | permanece desativada após toda restauração, independentemente do arquivo |

F7 deverá usar preflight, snapshot SQLite consistente, staging, promoção
atômica e rollback. Cópia crua de banco ativo não é contrato aceitável.

### Navegação V1 — contrato para F1, sem mudança em F0

Os únicos destinos principais da V1 serão: **Home, Biblioteca, Novidades,
Histórico, Explorar, Maya, Downloads e Configurações**.

Dentro de **Configurações** ficarão Backup/restauração, Diagnósticos,
sessões/PWA e Motor interno; Conexões e acesso agrupará LAN, pareamento e
sessões. Esses são destinos internos, não itens principais adicionais. O status
comum pode levar à seção apropriada, e detalhes técnicos pertencem apenas a
Diagnósticos.

O Criador de fontes sai da interface V1. F0 apenas registra essa organização:
a UI R8 atual não é movida, removida nem reimplementada agora. A navegação e as
Configurações começam junto da implementação de F1.

## Persistência e sequência de fases

O schema publicado continua v5. As decisões acima não reservam schemas além da
aprovação explícita de Settings em v6 para F1:

| Fase futura | Estado Yomu possível | Limite já fixado |
|---|---|---|
| F1 — Configurações | schema v6 tipado | nunca app_meta JSON genérico |
| F2 — Histórico | supressões locais vinculadas a lastReadAt | não altera fatos de leitura do motor |
| F3 — Novidades | watermark mínimo por obra/fronteira estável | não copia catálogo ou capítulos integrais |
| F5 — fontes | nenhum fato transferido | troca assistida e confirmada |
| F7 — Backup | snapshot Yomu selecionado | sem WinCred; LAN off após restore |

Cada persistência nova continua exigindo seu próprio escopo, decisão de
migração, snapshot e validação. F0 não autoriza essas implementações.

## Documentação factual ativa

Após este contrato, a documentação de uso corrente deve refletir que R0–R8
está concluída e que o motor é iniciado/supervisionado pelo Yomu. Ela não deve
mais instruir início manual do motor nem apresentar Source Builder como produto
V1. Documentos e relatórios históricos continuam preservados como registro de
sua época.

## Próximo gate

O próximo trabalho implementável é F1, em escopo próprio. F0 não autoriza por
si só schema, UI, código ou controle de processos; operações Git continuam
dependendo de autorização explícita separada.
