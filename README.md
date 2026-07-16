# Yomu

Private, local-first manga/manhwa/webtoon reader.

- **Desktop:** Flutter native Windows app (not Electron/Tauri/WebView shell)
- **Engine:** [Suwayomi-Server](https://github.com/Suwayomi/Suwayomi-Server) managed locally (**no Docker**)
- **Extensions:** Tachiyomi/Mihon ecosystem (e.g. [Keiyoushi](https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json))
- **Mobile:** iPhone via Safari/PWA → **Yomu Core only** (Suwayomi stays on loopback)
- **Extras:** Maya local-first com providers opcionais; analytics e Source
  Builder permanecem fases posteriores

## Requirements

- Windows 10/11 x64
- Flutter 3.32.5 / Dart 3.8.1 (fixed for the current phases)
- Drift 2.28.0 / sqlite3 2.9.4; no `sqlite3_flutter_libs`
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

### Gates

| Gate | Estado |
|------|--------|
| Gate funcional #1 (páginas reais) | ✅ |
| Hard gate (biblioteca + salvar/retomar progresso + downloads) | ✅ (Fase 2C) |
| PWA LAN real | ✅ (opt-in + pairing + proxy) |
| Maya persistente + providers OpenAI/Anthropic/Gemini/Ollama | ✅ (schema v4) |
| Provider OpenAI-compatible personalizado | planejado como P2C; não implementado |
| Source Builder | reservado para a última fase |

Yomu HTTP default: `http://127.0.0.1:8787`; LAN só com opt-in. Suwayomi: `http://127.0.0.1:14567` apenas.
Os adapters/providers da P2B foram validados com transports determinísticos;
nenhuma chamada live a conta ou modelo externo foi certificada.

### Suwayomi JAR

Pinned in `packages/yomu_suwayomi/vendor/manifest.json` (version + sha256).  
JAR may live under `vendor/` (gitignored if large) or downloaded on first start after hash verify.

## Estado e arquitetura

O baseline atual é `master` em `7a35094b80b9359327c49e198258fc3c3d255571`:
P0, checkpoint pós-P0, P1, P2A e P2B estão concluídos e publicados. O SQLite
Yomu está no schema v4. Consulte `docs/current-handoff.md` antes de continuar e
`docs/architecture.md` para os limites de ownership. A próxima necessidade de
produto é um provider OpenAI-compatible personalizado em subfase separada.

## License

TBD
