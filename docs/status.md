# Status

## Gates

| Gate | Estado |
|------|--------|
| Funcional #1 — extensão → páginas | ✅ |
| Hard — biblioteca / progresso / downloads | ✅ |
| 1.5 — isolamento Suwayomi | ✅ |
| PWA iPhone mínima | ✅ |
| Maya mínima | ✅ |
| 2D — hardening lifecycle / LAN / Maya | ✅ |
| 2D.1 — reliability | ✅ |
| **2D.2 — JRE bundle + lifecycle/LAN/PWA edges** | ✅ código |

## Phases

| Fase | Estado |
|------|--------|
| 2B–2C leitura + library | ✅ |
| PWA + Maya | ✅ |
| 2D / 2D.1 hardening | ✅ |
| Source Builder | bloqueado |
| Design / SQLite / histórico / settings | bloqueados |

## Validação

```powershell
powershell -ExecutionPolicy Bypass -File tool/verify_workspace.ps1
```

## Limitações restantes

- Ownership via PowerShell/CIM (command line ilegível → não mata)
- DNS rebinding TOCTOU residual entre resolve e TCP connect
- PWA HTTP só em LAN confiável (HTTPS na fase PWA final)
