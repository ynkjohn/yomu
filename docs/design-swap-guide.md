# Design Swap Guide

When final design arrives:

## Replace

- Everything under `packages/yomu_ui`
- Screen widgets in `apps/yomu_desktop/lib/screens` and shell layout
- PWA markup/CSS in `apps/yomu_mobile_pwa`
- Tokens in `YomuTokens`

## Keep

- `yomu_core` domain and reconciliation
- `yomu_suwayomi` process manager + client
- `yomu_local_server` routes and proxy rules
- `yomu_storage` schema
- Maya ActionProposal rules
- SourceSpec runtime

## Route IDs (stable)

`library`, `explore`, `extensions`, `source_builder`, `downloads`, `history`, `updates`, `maya`, `server`, `settings`
