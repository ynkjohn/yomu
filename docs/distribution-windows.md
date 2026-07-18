# Distribuição Windows — JRE 21

## Objetivo

O build **Release/instalador** deve rodar em um PC **sem Java instalado** e **sem monorepo**.

## Layout do bundle

```
yomu_desktop.exe
jre/
  bin/java.exe    # Temurin 21.0.11+10 pinado
  NOTICE
  legal/          # GPLv2, Classpath Exception e notices upstream
engine/
  engine_manifest.json
  Suwayomi-Server-v2.3.2238.jar
licenses/
  THIRD_PARTY_NOTICES.md
pwa/
  index.html      # PWA iPhone (resolvida via Platform.resolvedExecutable)
  …
data/             # Flutter assets
flutter_windows.dll
…
```

Em Profile/Release, `JavaResolver` aceita somente
`{exeDir}/jre/bin/java.exe`; não lê `YOMU_JAVA_HOME`, `JAVA_HOME`, PATH,
monorepo ou a antiga cópia de AppData. O JAR também é aceito somente de
`{exeDir}/engine`, verificado por SHA-256 e promovido ao runtime gerenciado por
arquivo temporário + rename.

Debug preserva conveniências de desenvolvimento, nesta ordem:

1. `YOMU_JAVA_HOME` explícito;
2. `{exeDir}/jre`;
3. runtime legado em AppData, se já existir;
4. `packages/yomu_suwayomi/vendor/jre21`;
5. `JAVA_HOME` / PATH.

A PWA é resolvida a partir de `{exeDir}/pwa` (via `Platform.resolvedExecutable`), não do cwd/monorepo.

O app **não** pede para o usuário mudar `JAVA_HOME`.

## Aquisição reprodutível do JRE 21

Manifest único pinado:
`packages/yomu_suwayomi/vendor/engine_manifest.json`. Ele fixa JRE, JAR,
licenças, notices, URLs oficiais, commits, nomes e SHA-256 dos materiais de
source e build.

```powershell
powershell -ExecutionPolicy Bypass -File tool/fetch_jre21_windows.ps1
```

O script nunca altera versão ou hash. Ele prepara, fora do Git:

- Temurin JRE e Suwayomi JAR para o bundle;
- `OpenJDK21U-jdk-sources_21.0.11_10.tar.gz`;
- `temurin-build-a612825ee82a20ac872d60958c349854c1f29a8e.tar.gz`;
- `OpenJDK21U-jre_x64_windows_hotspot_21.0.11_10.zip.json`;
- `Suwayomi-Server-a1770cb0553e37c1f660a88c23afd7badde11328.tar.gz`.

O gate confirma hashes, proveniência, commits, argumentos de build, materiais
obrigatórios e textos de licença/notice. Alterar qualquer pin exige subfase e
aprovação próprias.

## Build Release

```powershell
$env:Path = "C:\src\flutter\bin;" + $env:Path
cd apps\yomu_desktop
flutter build windows --release
```

O `windows/CMakeLists.txt`:

- instala `vendor/jre21` → `{prefix}/jre`
- instala o JAR e manifest → `{prefix}/engine`
- instala `THIRD_PARTY_NOTICES.md` → `{prefix}/licenses`
- instala `apps/yomu_mobile_pwa` → `{prefix}/pwa`
- falha o install Profile/Release se o bundle offline completo ou o conjunto de
  source correspondente não passar no gate

Cópia manual (Debug ou pasta custom):

```powershell
powershell -ExecutionPolicy Bypass -File tool/bundle_jre_windows.ps1
# ou
powershell -ExecutionPolicy Bypass -File tool/bundle_jre_windows.ps1 `
  -Target apps/yomu_desktop/build/windows/x64/runner/Debug
```

## Gate de publicação GPLv2 §3(a)

```powershell
powershell -ExecutionPolicy Bypass -File tool/verify_engine_release.ps1 `
  -ReleaseDirectory <pasta-da-release> `
  -BinaryArtifactPath <pasta-da-release>\Yomu-windows-x64.zip
```

O gate abre o ZIP, comprova que ele contém o executável, JRE, JAR, manifest,
notices e PWA pinados, e exige os quatro assets de source/proveniência
diretamente na mesma pasta de release. Esses assets não entram no ZIP. Um
instalador `.exe` permanece bloqueado até a tecnologia escolhida possuir um gate
capaz de inspecionar seu conteúdo. Não há oferta escrita de três anos; a política
adotada é GPLv2 §3(a).

## HTTP / PWA

A PWA em **HTTP** é **somente LAN confiável** (opt-in + pairing).  
**HTTPS / instalável** = fase PWA final.
