# Data Model (dual DB)

## Suwayomi

Library membership, manga metadata from sources, chapters, pages, downloads, main reading progress, installed extensions, extension repos (as configured in motor).

## Yomu SQLite

| Area | Tables (planned) |
|------|------------------|
| Sessions | `device_sessions` |
| Settings | `app_settings` |
| Maya | `maya_conversations`, `maya_messages`, `maya_memories` |
| Safety | `action_proposals`, `audit_logs` |
| Intention | `personal_status_overrides` |
| Specs | `source_specs`, `source_revisions` |
| Analytics | `reading_analytics`, `history_extras` |
| Links | `suwayomi_link` |

## Personal status reconciliation

- **Facts** (unread/read chapters): Suwayomi only.
- **Intention** (`wantToRead`…`dropped`): Yomu; may be manual override.
- If override = `completed` and unread chapters remain → show both + warning.
- Never auto-mark Suwayomi chapters read from Yomu status alone.
