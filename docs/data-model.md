# Data Model (dual DB)

## Suwayomi

Library membership, manga metadata from sources, chapters, pages, downloads, main reading progress, installed extensions, extension repos (as configured in motor).

## Yomu SQLite

| Area | Tables | Estado |
|------|--------|--------|
| Meta | `app_meta` | schema v1; flags e markers de migração |
| Sessions | `device_sessions` | schema v2; somente hash do bearer |
| Maya | `maya_messages`, `maya_action_proposals` | schema v3; P2A |
| Settings | `app_settings` | candidato P2+; não aprovado |
| Intention | `personal_status_overrides` | candidato P2+; não aprovado |
| Specs | `source_specs`, `source_revisions` | Source Builder; fase posterior |
| Analytics | `reading_analytics`, `history_extras` | candidato P2+; não aprovado |
| Links | `suwayomi_link` | candidato P2+; não aprovado |

O schema v3 da Maya persiste somente o histórico atual e o estado auditável de
`ActionProposal`. Ele não cria conversas múltiplas, memória, provider settings
ou logs genéricos. Os demais nomes continuam candidatos históricos, não
autorização de persistência, e exigem nova subfase com schema bump separado.

## Personal status reconciliation

- **Facts** (unread/read chapters): Suwayomi only.
- **Intention** (`wantToRead`…`dropped`): Yomu; may be manual override.
- If override = `completed` and unread chapters remain → show both + warning.
- Never auto-mark Suwayomi chapters read from Yomu status alone.
