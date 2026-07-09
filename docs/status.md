# Status

## Gates

### Gate funcional #1 — extensão → páginas ✅

Probe + UI mínima de leitura.

### Hard gate — biblioteca + progresso + downloads ✅ (código 2C)

- Biblioteca Suwayomi (`inLibrary`)
- Salvar/retomar `lastPageRead` no leitor
- Fila de downloads (enqueue / status / clear)

Validação manual: biblioteca → continuar → páginas; download na obra → aba Downloads.

### Gate 1.5 — isolamento Suwayomi ✅

`127.0.0.1:14567`, data root gerenciado.

## Phases

| Fase | Estado |
|------|--------|
| 2B UI mínima leitura | ✅ |
| Foundation fix (git, loopback HTTP, testes) | ✅ |
| **2C biblioteca / progresso / downloads** | ✅ código |
| PWA iPhone real | bloqueada |
| Maya | bloqueada |
| Source Builder | bloqueado |
| Design final | bloqueado |

## PWA stub

Loopback-only dev stub — **não** release. LAN exige opt-in + auth futuros.

## Validação

```powershell
powershell -ExecutionPolicy Bypass -File tool/verify_workspace.ps1
```
