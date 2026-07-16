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
| Settings | `app_settings` | candidato P2+; não aprovado |
| Intention | `personal_status_overrides` | candidato P2+; não aprovado |
| Specs | `source_specs`, `source_revisions` | Source Builder; fase posterior |
| Analytics | `reading_analytics`, `history_extras` | candidato P2+; não aprovado |
| Links | `suwayomi_link` | candidato P2+; não aprovado |

O schema v4 preserva o histórico atual e o estado auditável de
`ActionProposal` do schema v3 e adiciona somente a configuração não secreta do
provider da Maya. A row `settings_id = 1` diferencia modo local, modo cloud e
consentimentos de contexto; `is_enabled = 0` mantém transições e falhas cloud
duravelmente fail-closed. Ausência da row significa configuração nunca
realizada. API keys permanecem exclusivamente no Windows Credential Manager.

O schema não cria conversas múltiplas, memória, prompts/respostas remotas crus
ou logs genéricos. Os demais nomes continuam candidatos históricos, não
autorização de persistência, e exigem nova subfase com schema bump separado.
Consulte `docs/p2b-maya-providers.md` para o contrato completo da P2B.

O provider personalizado solicitado para P2C não possui coluna ou tabela no
schema v4. Se endpoint/perfil precisar ser persistido, a mudança deve ocorrer
somente em uma migração explícita `4 → 5`, após definir ownership, protocolo,
restrições de rede e política de credencial. Nenhum nome de tabela ou formato
está autorizado antes desse plano.

## Personal status reconciliation — modelo conceitual candidato

Esta seção não autoriza persistência nem ownership novo. Depende de auditoria,
aprovação de produto e schema bump próprio em subfase futura.

- **Facts** (unread/read chapters): Suwayomi only.
- **Intention** (`wantToRead`…`dropped`): candidato Yomu; pode ser override manual.
- If override = `completed` and unread chapters remain → show both + warning.
- Never auto-mark Suwayomi chapters read from Yomu status alone.
