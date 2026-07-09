# iPhone Runbook (stub)

## Prerequisites

1. Yomu Desktop running on Windows
2. Yomu Core listening on port **8787**
3. iPhone on the **same Wi‑Fi**
4. Windows Firewall allows inbound TCP 8787

## Steps (Phase 1)

1. On desktop, open **Servidor / Dispositivos** and note LAN URL
2. On iPhone Safari open `http://<pc-ip>:8787/`
3. Confirm health shows Yomu ok and Suwayomi state

## Notes

- Full pairing/auth = after reading gate
- Installable PWA with Service Worker expects **HTTPS LAN** later
- HTTP is acceptable for early connectivity tests only
