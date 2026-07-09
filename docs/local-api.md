# Local API (Yomu Core)

## Phase 2B defaults (foundation fix)

| Item | Value |
|------|--------|
| Bind | **`127.0.0.1:8787`** (loopback only) |
| Auth | none (dev stub) |
| CORS | **disabled** by default (`allowOpenCors: false`) |
| PWA | static stub if present — **dev only, not release** |
| Suwayomi | **never** bound on LAN (`127.0.0.1:14567` only) |

### Endpoints (dev)

| Method | Path | Notes |
|--------|------|--------|
| GET | `/health` | Yomu + Suwayomi status JSON |
| GET | `/api/v1/health` | alias |
| GET | `/` | PWA stub static (if folder exists) |

## Before real mobile PWA / LAN

Must implement **before** enabling non-loopback bind:

1. Explicit user opt-in to LAN bind (`0.0.0.0` or interface IP)
2. Device pairing + bearer token per session
3. Restricted CORS (same-origin or allowlist, never `*` in production)
4. Rate limits + audit logs without secrets
5. Clear UX when desktop offline / wrong network

Until then, UI must **not** advertise LAN availability.
