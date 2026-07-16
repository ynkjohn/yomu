# Data Model (dual DB)

## Suwayomi

Library membership, manga metadata from sources, chapters, pages, downloads, main reading progress, installed extensions, extension repos (as configured in motor).

## Yomu SQLite

| Area | Tables | Estado |
|------|--------|--------|
| Sessions | `device_sessions` | schema v2; somente hash do bearer |
| Settings | `app_settings` | candidato P2+; não aprovado |
| Maya | `maya_conversations`, `maya_messages`, `maya_memories` | candidato P2+; não aprovado |
| Safety | `action_proposals`, `audit_logs` | candidato P2+; não aprovado |
| Intention | `personal_status_overrides` | candidato P2+; não aprovado |
| Specs | `source_specs`, `source_revisions` | Source Builder; fase posterior |
| Analytics | `reading_analytics`, `history_extras` | candidato P2+; não aprovado |
| Links | `suwayomi_link` | candidato P2+; não aprovado |

Exceto por `device_sessions`, os nomes acima são candidatos históricos, não
autorização de persistência. P2+ exige auditoria de ownership e subfases com
schema bump separado antes de criar qualquer outra tabela.

## Personal status reconciliation

- **Facts** (unread/read chapters): Suwayomi only.
- **Intention** (`wantToRead`…`dropped`): Yomu; may be manual override.
- If override = `completed` and unread chapters remain → show both + warning.
- Never auto-mark Suwayomi chapters read from Yomu status alone.
