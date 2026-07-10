# Distribuição Windows — JRE 21

## Objetivo

O build **Release/instalador** deve rodar em um PC **sem Java instalado** e **sem monorepo**.

## Layout do bundle

```
yomu_desktop.exe
jre/
  bin/java.exe    # Temurin/OpenJDK 21+  (obrigatório no Release)
pwa/
  index.html      # PWA iPhone (resolvida via Platform.resolvedExecutable)
  …
data/             # Flutter assets
flutter_windows.dll
…
```

`JavaResolver` procura nesta ordem:

1. **`YOMU_JAVA_HOME`** — override **explícito** (opcional; só se versão ≥ 21)
2. **`{exeDir}/jre`** — JRE empacotado (Release)
3. **`{appSupport}/yomu/runtime/jre`** — cópia gerenciada
4. Monorepo `packages/yomu_suwayomi/vendor/jre21` (dev)
5. `JAVA_HOME` / PATH (fallback de sistema)

A PWA é resolvida a partir de `{exeDir}/pwa` (via `Platform.resolvedExecutable`), não do cwd/monorepo.

O app **não** pede para o usuário mudar `JAVA_HOME`.

## Aquisição reprodutível do JRE 21

Manifest pinado: `packages/yomu_suwayomi/vendor/jre_manifest.json`
(campos fixos: version, downloadUrl, sha256, license, licenseUrl)

```powershell
powershell -ExecutionPolicy Bypass -File tool/fetch_jre21_windows.ps1
# primeira vez / bump: -UpdateManifestHash (grava SHA-256 após download)
```

## Build Release

```powershell
$env:Path = "C:\src\flutter\bin;" + $env:Path
cd apps\yomu_desktop
flutter build windows --release
```

O `windows/CMakeLists.txt`:

- instala `vendor/jre21` → `{prefix}/jre`
- instala `apps/yomu_mobile_pwa` → `{prefix}/pwa`
- **falha o install Release/Profile** se o JRE obrigatório ou a PWA estiverem ausentes

Cópia manual (Debug ou pasta custom):

```powershell
powershell -ExecutionPolicy Bypass -File tool/bundle_jre_windows.ps1
# ou
powershell -ExecutionPolicy Bypass -File tool/bundle_jre_windows.ps1 `
  -Target apps/yomu_desktop/build/windows/x64/runner/Debug
```

## Override opcional

```powershell
$env:YOMU_JAVA_HOME = "D:\meus-jres\temurin-21"
```

Só use se quiser **substituir** o JRE empacotado (ex.: troubleshooting). Não é necessário em instalação normal.

## HTTP / PWA

A PWA em **HTTP** é **somente LAN confiável** (opt-in + pairing).  
**HTTPS / instalável** = fase PWA final.
