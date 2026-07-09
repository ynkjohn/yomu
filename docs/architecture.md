# Yomu Architecture

## Verdict

| Concern | Owner |
|---------|--------|
| Tachiyomi/Mihon/Keiyoushi extensions | **Suwayomi-Server** (managed process) |
| Own sources from a pasted URL | **Yomu Source Builder** (complementary, dual catalog) |
| Native UI, Maya, PWA, proxy, auth | **Yomu** |

## Processes

1. **Yomu Desktop** (Flutter native executable)
2. **Suwayomi-Server** (Java), spawned by Yomu, bound to **127.0.0.1 only**
3. **Yomu Core HTTP** (Shelf), bound for LAN, authenticates devices, proxies to Suwayomi

iPhone Safari/PWA talks **only** to Yomu Core.

## Dual catalog (Source Builder)

- Extension sources: runtime = Suwayomi; appear in Suwayomi UI/API.
- SourceSpec sources: runtime = Yomu; **do not** appear in Suwayomi in the MVP.
- Spec Bridge Extension = future evolution.

## Dual database

- Suwayomi: library, chapters, pages, downloads, main progress, extensions.
- Yomu SQLite: Maya, sessions, audit, personal status overrides, SourceSpecs, analytics.

Personal status is dual-layer: Suwayomi = facts; Yomu = intention; conflicts are visible.

## Hard gates

Do not build Maya, full PWA, or Source Builder until:

1. Suwayomi start/health/stop
2. Keiyoushi → install extension → search → details → chapters → pages
3. Desktop reader + progress save/resume
