# Fase Maya mínima

> Estado histórico: esta fase introduziu a Maya com persistência JSON e engine
> heurístico local. A P2A migrou o histórico para o SQLite Yomu schema v3 e a
> P2B adicionou providers opcionais no schema v4 e a P2C implementou o perfil
> OpenAI-compatible no schema v5. Consulte `docs/p2a-maya-persistence.md`,
> `docs/p2b-maya-providers.md`, `docs/p2c-maya-custom-provider.md` e
> `docs/current-handoff.md`.

## Objetivo

Assistente **local-first** no desktop que consulta a biblioteca Suwayomi e só executa ações mutáveis após **confirmação explícita** (ActionProposal).

## Escopo

- Chat UI na aba **Maya**
- Motor heurístico PT-BR offline (sem API key)
- Propostas: abrir obra, baixar capítulo
- Persistência originalmente em `…/yomu/maya_chat.json`; fonte migrada pela
  P2A para o SQLite Yomu
- Port `MayaLibraryPort` → Suwayomi loopback (nunca LAN)

## Fora do escopo daquela fase

- Providers eram posteriores; OpenAI, Anthropic, Gemini e Ollama foram
  implementados na P2B, sempre opcionais
- Múltiplas conversas e memória continuam não implementadas
- Provider OpenAI-compatible personalizado foi implementado na P2C; naquela
  fase histórica ainda não existia
- Maya no PWA iPhone
- Source Builder

## Comandos úteis

| Mensagem | Efeito |
|----------|--------|
| ajuda | lista comandos |
| biblioteca | lista obras |
| continuar | propostas para abrir obras em progresso |
| busca &lt;título&gt; | busca na biblioteca + propostas |
| baixar | propõe download do capítulo de retomada |

## Segurança

- Nenhuma ação mutável sem cartão **Confirmar**
- Suwayomi só via process manager (loopback)
