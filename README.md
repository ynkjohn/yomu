# Yomu

Private, local-first manga/manhwa/webtoon reader.

- **Desktop:** Flutter native Windows app (not Electron/Tauri/WebView shell)
- **Engine:** [Suwayomi-Server](https://github.com/Suwayomi/Suwayomi-Server) managed locally (**no Docker**)
- **Extensions:** Tachiyomi/Mihon ecosystem (e.g. [Keiyoushi](https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json))
- **Mobile:** iPhone via Safari/PWA → **Yomu Core only** (Suwayomi stays on loopback)
- **Extras:** Maya, analytics, Source Builder (complementary dual-catalog)

## Requirements

- Windows 10/11 x64
- Flutter 3.32+ (for development)
- **JRE 21+** to run Suwayomi (Java 17 is not enough)
- Visual Studio Build Tools with Windows desktop C++ workload

No Docker required.

## Repo layout

```
apps/yomu_desktop      # Flutter desktop
apps/yomu_mobile_pwa   # PWA stub served by desktop
packages/yomu_core
packages/yomu_suwayomi
packages/yomu_local_server
packages/yomu_ui
…
docs/
```

## Develop

```powershell
# PATH
$env:Path = "C:\src\flutter\bin;" + $env:Path

cd C:\Users\joaop\Projetos\yomu
dart pub get
cd apps\yomu_desktop
flutter pub get
flutter run -d windows
```

### Tests

```powershell
cd packages\yomu_core
dart test
cd ..\yomu_suwayomi
dart test
cd ..\yomu_local_server
dart test
```

### Health

With the app running:

- Desktop status bar: Suwayomi state + LAN port
- `http://127.0.0.1:8787/health`
- PWA stub: `http://127.0.0.1:8787/`

### Fluxo UI mínima (Fase 2B)

1. Aba **Servidor** → Iniciar Suwayomi  
2. Aba **Extensões** → Garantir Keiyoushi → Instalar MangaDex  
3. Aba **Explorar** → buscar `berserk` → abrir obra com capítulos  
4. Abrir capítulo → ver páginas no leitor  

Detalhes: `docs/phase-2b-ui-minimum.md`.

### Validar workspace inteiro

```powershell
powershell -ExecutionPolicy Bypass -File tool/verify_workspace.ps1
```

Isso roda: `flutter analyze` (raiz), testes (core, suwayomi, local_server, desktop), `flutter build windows --debug`.

### Gates

| Gate | Estado |
|------|--------|
| Gate funcional #1 (páginas reais) | ✅ |
| Hard gate (biblioteca + salvar/retomar progresso + downloads) | ✅ (Fase 2C) |
| PWA LAN real | bloqueada (stub loopback-only) |
| Maya / Source Builder | bloqueados |

Yomu HTTP default: `http://127.0.0.1:8787` (não LAN). Suwayomi: `http://127.0.0.1:14567` apenas.

### Suwayomi JAR

Pinned in `packages/yomu_suwayomi/vendor/manifest.json` (version + sha256).  
JAR may live under `vendor/` (gitignored if large) or downloaded on first start after hash verify.

## Architecture summary

See `docs/architecture.md`. Hard rule: **do not** implement Maya / full PWA / Source Builder until Suwayomi + Keiyoushi extension + reading gates are green.

## License

TBD
