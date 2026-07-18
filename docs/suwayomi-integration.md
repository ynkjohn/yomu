# Suwayomi Integration

## Role

Suwayomi-Server is the **extension engine** (Tachiyomi/Mihon). Yomu never reimplements APK runtime.

## Isolation (Gate 1.5 — required)

Managed process uses **only**:

1. Pinned JAR + SHA-256 from
   `packages/yomu_suwayomi/vendor/engine_manifest.json`
2. Profile/Release: only the packaged Temurin JRE beside the executable;
   Debug may use explicit development fallbacks
3. Data root under `{appSupport}/yomu/data/suwayomi`
4. Loopback `127.0.0.1:14567`

### JVM launch (correct)

System properties **must** appear **before** `-jar`:

```text
java \
  -Dsuwayomi.tachidesk.config.server.rootDir=<abs-managed-data-dir> \
  -Dsuwayomi.tachidesk.config.server.ip=127.0.0.1 \
  -Dsuwayomi.tachidesk.config.server.port=14567 \
  -Dsuwayomi.tachidesk.config.server.systemTrayEnabled=false \
  -Dsuwayomi.tachidesk.config.server.initialOpenInBrowserEnabled=false \
  -jar Suwayomi-Server-….jar
```

Property name confirmed in bytecode: `ApplicationRootDirKt` →  
`suwayomi.tachidesk.config.server.rootDir`.

### Hard bans

- Do **not** read/write/patch `%LOCALAPPDATA%\Tachidesk\**`
- Do **not** put `-D…` after `-jar` (they become app args and are ignored as system properties)
- Start **fails** if real data root ≠ managed dir (`verifyManagedDataRoot`)

### Verification

```powershell
dart run tool/smoke_suwayomi.dart
dart run tool/smoke_suwayomi.dart --aggressive-rename
```

Optional rename of global Tachidesk is restored in `finally`.

## Layout

```
{appSupport}/yomu/
  runtime/suwayomi/<jar>
  runtime/jre/                 # legacy development fallback only
  data/suwayomi/               # server.rootDir (conf, H2, extensions, downloads)
  config/server.conf           # Yomu mirror only (not Tachidesk AppData)
  logs/suwayomi.log
```

## Version pin

See `packages/yomu_suwayomi/vendor/engine_manifest.json`. It is the single
pin for the JAR, JRE, sources, notices and provenance. Bump only in a separately
approved update with hash and compatibility verification.

## Network

| Service | Bind | LAN |
|---------|------|-----|
| Suwayomi | `127.0.0.1:14567` | No |
| Yomu Core default | `127.0.0.1:8787` | No |
| Yomu Core com opt-in LAN | `0.0.0.0:8787` | Yes, Auth obrigatória |

As sessões do Yomu Core já são persistidas no SQLite Yomu schema v2; o bearer
é persistido apenas como hash SHA-256. O iPhone nunca acessa a porta 14567
diretamente.

## Gate Suwayomi + 1.5

- [x] Start without terminal
- [x] Health / about OK
- [x] Stop / restart
- [x] Managed data root only
- [x] Global Tachidesk untouched
- [x] Aggressive rename optional test

## API

See `docs/suwayomi-api-matrix.md` (Phase 2A).
