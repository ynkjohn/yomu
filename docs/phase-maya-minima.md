# Fase Maya mínima

> Estado histórico: esta fase introduziu a Maya com persistência JSON. A P2A
> substitui esse placeholder pelo SQLite Yomu schema v3; consulte
> `docs/p2a-maya-persistence.md`.

## Objetivo

Assistente **local-first** no desktop que consulta a biblioteca Suwayomi e só executa ações mutáveis após **confirmação explícita** (ActionProposal).

## Escopo

- Chat UI na aba **Maya**
- Motor heurístico PT-BR offline (sem API key)
- Propostas: abrir obra, baixar capítulo
- Persistência originalmente em `…/yomu/maya_chat.json`; fonte migrada pela
  P2A para o SQLite Yomu
- Port `MayaLibraryPort` → Suwayomi loopback (nunca LAN)

## Fora de escopo (agora)

- LLM cloud obrigatório (hook `MayaLlmProvider` existe, sem provider default)
- Múltiplas conversas, memória e configurações de provider
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
