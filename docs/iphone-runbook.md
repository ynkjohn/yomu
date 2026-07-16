# iPhone Runbook (PWA mínima)

## Prerequisites

1. Yomu Desktop running on Windows (same Wi‑Fi as the iPhone)
2. Suwayomi motor **running** (tab Servidor → Iniciar)
3. At least one title in the desktop library (for a useful test)
4. Windows Firewall allows inbound **TCP 8787** (private network)

## Steps

1. Desktop → **Servidor**
2. Enable **Permitir acesso na LAN (Wi‑Fi)** and confirm the dialog  
   - Yomu binds `0.0.0.0:8787`  
   - Suwayomi stays on `127.0.0.1:14567`
3. Note the URL(s) listed (e.g. `http://192.168.x.x:8787/`)
4. Tap **Gerar código de pareamento** (6 digits, ~5 min)
5. On iPhone Safari open the URL
6. Enter the code → **Parear**
7. Open a title → chapter → read; progress saves via Core → Suwayomi
8. Optional: Share → **Add to Home Screen** (A2HS). Full offline SW/HTTPS comes later.

## Troubleshooting

| Symptom | Check |
|---------|--------|
| Page won't load | Same Wi‑Fi, firewall 8787, LAN toggle on, correct PC IP |
| Health offline | Desktop app running; Yomu HTTP started |
| Pairing 401 | New code; clock/TTL; code not reused |
| Library empty / 502 | Start Suwayomi; add titles on desktop |
| Images blank | Token still valid; motor healthy |

## Security

- iPhone talks **only** to Yomu Core, never to port 14567
- Bearer session after pairing; a tela **Servidor** lista e revoga sessões
  individualmente ou em conjunto
- Use trusted Wi‑Fi only; LAN is opt-in

## Notes

- HTTP is OK for early LAN tests; installable PWA + Service Worker ideally need HTTPS later
- Design is provisional
