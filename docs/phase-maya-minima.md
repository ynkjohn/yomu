# Fase Maya mínima

## Objetivo

Assistente **local-first** no desktop que consulta a biblioteca Suwayomi e só executa ações mutáveis após **confirmação explícita** (ActionProposal).

## Escopo

- Chat UI na aba **Maya**
- Motor heurístico PT-BR offline (sem API key)
- Propostas: abrir obra, baixar capítulo
- Persistência JSON: `…/yomu/maya_chat.json`
- Port `MayaLibraryPort` → Suwayomi loopback (nunca LAN)

## Fora de escopo (agora)

- LLM cloud obrigatório (hook `MayaLlmProvider` existe, sem provider default)
- Drift SQLite (`maya_conversations` tables) — JSON placeholder
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
