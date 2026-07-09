# Status

## Gates

### Gate funcional #1 — leitura ponta a ponta (probe) ✅

Extensão → busca → obra → capítulos → **páginas reais**.

- Script: `tool/gate_functional_1.dart`
- Evidence: `docs/functional-gate-1.md`
- UI mínima (2B) cobre o mesmo fluxo no desktop

### Hard gate — biblioteca + progresso + downloads ❌ pendente

Ainda **não** completo:

- Biblioteca como fonte de verdade de uso diário
- **Salvar e retomar** progresso de leitura
- Fila de downloads / offline

O leitor abre páginas reais, mas **sem persistência/retomada de progresso** o hard gate permanece aberto.

### Gate 1.5 — isolamento Suwayomi ✅

- Script: `tool/smoke_suwayomi.dart`
- Loopback `127.0.0.1:14567`, data root gerenciado, sem patch AppData Tachidesk

## Phase 2B — UI mínima desktop ✅

- Servidor / Extensões / Explorar / Detalhe / Leitor mínimo
- Ver `docs/phase-2b-ui-minimum.md`

## Foundation fix (pós-2B auditoria) ✅

- Git base commit
- Yomu HTTP **loopback-only** (`127.0.0.1:8787`), CORS fechado por padrão
- Filtro de extensões local (sem re-fetch a cada tecla)
- `tool/verify_workspace.ps1` + testes ampliados
- Documentação de gates corrigida

## Bloqueado até hard gate

| Feature | Status |
|---------|--------|
| Biblioteca / progresso / downloads UI | Fase 2C+ |
| PWA iPhone real (pareamento/LAN) | Bloqueada |
| Maya | Bloqueada |
| Source Builder | Bloqueado |
| Design final | Bloqueado |

## PWA stub

`apps/yomu_mobile_pwa` é **somente desenvolvimento** (health stub).  
**Não** empacotar / release. LAN e CORS abertos **não** estão habilitados por padrão.

## Validação

```powershell
powershell -ExecutionPolicy Bypass -File tool/verify_workspace.ps1
```
