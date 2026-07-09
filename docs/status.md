# Status

## Gates

| Gate | Estado |
|------|--------|
| Funcional #1 — extensão → páginas | ✅ |
| Hard — biblioteca / progresso / downloads | ✅ |
| 1.5 — isolamento Suwayomi | ✅ |
| PWA iPhone mínima | ✅ |
| Maya mínima | ✅ |
| **2D — hardening lifecycle / LAN / Maya** | ✅ código |

## Phases

| Fase | Estado |
|------|--------|
| 2B UI mínima | ✅ |
| 2C library / progress / downloads | ✅ |
| PWA auth + LAN + media proxy | ✅ |
| Maya mínima | ✅ |
| **2D hardening** | ✅ |
| Source Builder | bloqueado (não iniciar ainda) |
| Design final / SQLite Drift / histórico / settings | bloqueados |

## Validação

```powershell
powershell -ExecutionPolicy Bypass -File tool/verify_workspace.ps1
```

## Limitações restantes (não bloqueantes 2D)

- Probe de ownership depende de PowerShell/CIM no Windows (falha → “unverifiable”, não mata)
- External media fetch ainda carrega body em memória (cap 25 MB)
- PWA sem Service Worker / HTTPS prod
- Orphan stop exige command line legível
