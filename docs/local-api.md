# Local API (Yomu Core)

## Defaults

| Item | Value |
|------|--------|
| Bind default | **`127.0.0.1:8787`** (loopback) |
| Bind LAN | **`0.0.0.0:8787`** only after **explicit opt-in** in desktop Servidor |
| Auth | Bearer token after pairing (`DeviceAuthStore`) |
| CORS | Off on loopback; on LAN reflects `Origin` (never `*`) |
| PWA | static SPA from `apps/yomu_mobile_pwa` when folder found |
| Suwayomi | **never** on LAN (`127.0.0.1:14567` only) |

## Public endpoints

| Method | Path | Notes |
|--------|------|--------|
| GET | `/health` | Yomu + Suwayomi + bind + auth summary |
| GET | `/api/v1/health` | alias |
| POST | `/api/v1/pairing/claim` | body `{ code, deviceName }` → `{ token }` |
| GET | `/` | PWA SPA (if present) |

## Authenticated endpoints (`Authorization: Bearer <token>`)

| Method | Path | Notes |
|--------|------|--------|
| GET | `/api/v1/me` | session device |
| GET | `/api/v1/library` | library items (thumb URLs rewritten to Yomu) |
| GET | `/api/v1/manga/:id` | manga detail |
| POST | `/api/v1/manga/:id/library` | `{ inLibrary: bool }` |
| GET | `/api/v1/manga/:id/chapters` | list / fetch chapters |
| GET | `/api/v1/chapters/:id/pages` | page list with **ticket** media URLs (`/api/v1/media?t=…`) |
| GET | `/api/v1/media?t=` | ticket-bound media proxy (session must match; **no raw `u=`**) |
| GET | `/api/v1/chapters/:id/pages/:index/image` | back-compat image proxy (loopback Suwayomi) |
| GET | `/api/v1/manga/:id/thumbnail` | thumbnail proxy |
| PUT | `/api/v1/chapters/:id/progress` | `{ lastPageRead, isRead }` |
| GET | `/api/v1/sources` | installed sources |
| GET | `/api/v1/sources/:id/search?q=` | search |

## Security notes

1. Pairing codes: 6 digits, ~5 minutes TTL, single use.
2. Sessions persisted under app support `yomu/device_sessions.json`.
3. Phone never receives Suwayomi host/port; all media goes through Yomu proxy.
4. LAN bind requires confirmation dialog on desktop.
