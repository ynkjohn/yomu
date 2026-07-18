# Yomu

Private, local-first manga/manhwa/webtoon reader.

- **Desktop:** Flutter native Windows app (not Electron/Tauri/WebView shell)
- **Engine:** [Suwayomi-Server](https://github.com/Suwayomi/Suwayomi-Server) managed locally (**no Docker**)
- **Extensions:** Tachiyomi/Mihon ecosystem (e.g. [Keiyoushi](https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json))
- **Mobile:** iPhone via Safari/PWA → **Yomu Core only** (Suwayomi stays on loopback)
- **Extras:** Maya local-first com providers opcionais, incluindo perfil
  OpenAI-compatible personalizado; analytics e Source Builder permanecem
  fases posteriores

## Requirements

- Windows 10/11 x64
- Flutter 3.32.5 / Dart 3.8.1 (fixed for the current phases)
- Drift 2.28.0 / sqlite3 2.9.4; no `sqlite3_flutter_libs`
- **Development:** JRE 21+ is prepared by the repository tooling; Java 17 is
  not enough. Profile/Release ship the pinned Temurin runtime and do not use an
  arbitrary system Java.
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
cd ..\yomu_storage
dart test
cd ..\yomu_ai
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

Isso roda analyzer, testes dos packages e do desktop, gates PWA e
`flutter build windows --debug`. Não execute o build enquanto o Yomu estiver
aberto; em `LNK1168`, peça fechamento normal ao usuário.

Para incluir também o gate do bundle offline já preparado:

```powershell
powershell -ExecutionPolicy Bypass -File tool/verify_workspace.ps1 `
  -VerifyOfflineEngineBundle
```

### Gates

| Gate | Estado |
|------|--------|
| Gate funcional #1 (páginas reais) | ✅ |
| Hard gate (biblioteca + salvar/retomar progresso + downloads) | ✅ (Fase 2C) |
| PWA LAN real | ✅ (opt-in + pairing + proxy) |
| Maya persistente + providers OpenAI/Anthropic/Gemini/Ollama | ✅ (schema v4) |
| Provider OpenAI-compatible personalizado | ✅ publicado em `eda852b` (schema v5) |
| Source Builder | reservado para a última fase |

Yomu HTTP default: `http://127.0.0.1:8787`; LAN só com opt-in. Suwayomi: `http://127.0.0.1:14567` apenas.
Os adapters/providers da P2B/P2C foram validados com transports
determinísticos; nenhuma chamada live a conta ou modelo externo foi
certificada. O perfil custom usa somente Chat Completions, HTTPS para destinos
públicos ou HTTP para loopback literal e chave opcional no WinCred.

### Suwayomi JAR

JAR, JRE, notices, source coordinates and hashes are pinned in the single
`packages/yomu_suwayomi/vendor/engine_manifest.json`. Debug development may
download the pinned JAR after hash verification. Profile/Release use only the
JRE and JAR shipped beside the executable and never fall back to network or
system Java.

Every release containing Temurin 21.0.11+10 must publish the exact OpenJDK
source, Temurin build-source archive, provenance metadata and pinned Suwayomi
source as separate assets beside the Yomu portable ZIP.
`tool/verify_engine_release.ps1` inspects that ZIP and fails closed if the
embedded engine or release-source set is absent or inconsistent. Installer
formats remain blocked until they have a content-aware gate of their own.
Binary/source archives remain outside Git and the installer.

## Estado e arquitetura

A P2C está concluída e publicada no commit
`eda852bcc17f1b04c5045e32388bf6c78a6945fb`, com schema v5. O handoff pós-P2C
foi publicado em `673734b742c9b0fac99f4090ba0eb14a4d15f175`.
Consulte
`docs/current-handoff.md`, `docs/p2c-maya-custom-provider.md` e
`docs/architecture.md` antes de continuar.

## License

TBD
