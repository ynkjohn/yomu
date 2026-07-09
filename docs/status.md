# Status

## Gates

### Gate funcional #1 — extensão → páginas ✅

Probe + UI mínima de leitura.

### Hard gate — biblioteca + progresso + downloads ✅ (código 2C)

- Biblioteca Suwayomi (`inLibrary`)
- Salvar/retomar `lastPageRead` no leitor
- Fila de downloads (enqueue / status / clear)

### Gate 1.5 — isolamento Suwayomi ✅

`127.0.0.1:14567`, data root gerenciado.

## Phases

| Fase | Estado |
|------|--------|
| 2B UI mínima leitura | ✅ |
| Foundation fix (git, loopback HTTP, testes) | ✅ |
| 2C biblioteca / progresso / downloads | ✅ |
| **PWA iPhone mínima (auth + LAN opt-in + SPA)** | ✅ código |
| Maya | bloqueada |
| Source Builder | bloqueado |
| Design final | bloqueado |

## PWA mínima

- Desktop: LAN opt-in, código de pareamento, sessões persistidas
- API: Bearer proxy para library / manga / chapters / pages / progress / images
- SPA: `apps/yomu_mobile_pwa` — pair, biblioteca, obra, leitor + progresso
- Suwayomi **nunca** na LAN

Validação manual: runbook em `docs/iphone-runbook.md`.

## Validação

```powershell
powershell -ExecutionPolicy Bypass -File tool/verify_workspace.ps1
```
