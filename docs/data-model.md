# Data Model (dual DB)

## Suwayomi

Library membership, manga metadata from sources, chapters, pages, downloads, main reading progress, installed extensions, extension repos (as configured in motor).

## Yomu SQLite

| Area | Tables | Estado |
|------|--------|--------|
| Meta | `app_meta` | schema v1; flags e markers de migração |
| Sessions | `device_sessions` | schema v2; somente hash do bearer |
| Maya | `maya_messages`, `maya_action_proposals` | schema v3; P2A |
| Maya providers | `maya_provider_settings` | schema v4; singleton sem credenciais |
| Maya custom provider | `maya_custom_provider_settings` | schema v5; singleton de endpoint sem credenciais |
| Settings | `app_settings` (ou tabelas tipadas equivalentes) | contrato aprovado para F1/schema v6; ainda não existe |
| Histórico | supressões locais vinculadas a `lastReadAt` | contrato F2 aprovado; ainda não criado |
| Novidades | watermark mínimo por obra/fronteira estável | contrato F3 aprovado; ainda não criado |
| Intention | `personal_status_overrides` | candidato histórico; não aprovado |
| Specs | `source_specs`, `source_revisions` | não pertence à interface V1; sem schema aprovado |
| Analytics | `reading_analytics`, `history_extras` | candidato P2+; não aprovado |
| Links | `suwayomi_link` | candidato P2+; não aprovado |

O schema v5 preserva todo o schema v4 e adiciona somente
`maya_custom_provider_settings`. A row geral `settings_id = 1` diferencia modo
local, modo cloud e consentimentos de contexto; `is_enabled = 0` mantém
transições e falhas cloud duravelmente fail-closed. A row custom, também
singleton, guarda URL canônica, uso opcional de chave e timestamp do snapshot.
API keys permanecem exclusivamente no Windows Credential Manager.

O schema não cria conversas múltiplas, memória, prompts/respostas remotas crus
ou logs genéricos. `app_meta` não pode receber JSON genérico de configurações:
permanece para flags e markers de migração reconhecidos. Os demais nomes
continuam candidatos ou contratos futuros, não autorização de persistência, e
exigem subfase com schema bump separado.
Consulte `docs/p2b-maya-providers.md` e
`docs/p2c-maya-custom-provider.md` para os contratos completos.

A migração `4 → 5` cria a tabela custom vazia e não inventa perfil. A row
custom só é válida quando sua URL permanece canônica e seu `updated_at_ms`
coincide com o consentimento da row geral ativa. Corrupção, ausência ou
mismatch impedem a criação do adapter.

F0 aprovou que F1 introduza configurações tipadas em schema v6, mas F0 não
cria tabela, migração ou snapshot. Histórico e Novidades, se vierem a
persistir, terão estado próprio mínimo em F2/F3 e não copiarão fatos/listas do
motor.

## Personal status reconciliation — modelo conceitual candidato

Esta seção não autoriza persistência nem ownership novo. Depende de auditoria,
aprovação de produto e schema bump próprio em subfase futura.

- **Facts** (unread/read chapters): Suwayomi only.
- **Intention** (`wantToRead`…`dropped`): candidato Yomu; pode ser override manual.
- If override = `completed` and unread chapters remain → show both + warning.
- Never auto-mark Suwayomi chapters read from Yomu status alone.
