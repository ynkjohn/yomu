# Yomu third-party notices

This file covers the pinned reading-engine artifacts distributed with Yomu.
It does not replace the license and notice files shipped inside those
artifacts.

## Suwayomi-Server v2.3.2238

- Component: `Suwayomi-Server-v2.3.2238.jar`
- Project: https://github.com/Suwayomi/Suwayomi-Server
- Exact source commit: `a1770cb0553e37c1f660a88c23afd7badde11328`
- Source archive: `Suwayomi-Server-a1770cb0553e37c1f660a88c23afd7badde11328.tar.gz`
- Source SHA-256: `d43dd41e2cd86ece24df1ad42c8495edc2729af1ef292f1c3d68ffb509ac4f86`
- Official source: https://github.com/Suwayomi/Suwayomi-Server/tree/a1770cb0553e37c1f660a88c23afd7badde11328
- License: MPL-2.0
- License text: https://raw.githubusercontent.com/Suwayomi/Suwayomi-Server/v2.3.2238/LICENSE
- Binary SHA-256: `9ee45c37dac659a284e4a1885dcddec54a7018ead2f18620bcb1fd29751c9786`

The exact source archive is published alongside Yomu release artifacts and
contains the MPL-2.0 license, Gradle wrapper and build scripts. The distributed
JAR retains its upstream `LICENSE`, `NOTICE`, `META-INF` license files and
dependency notices. Yomu does not modify the pinned JAR.

## Eclipse Temurin 21.0.11+10

- Component: `OpenJDK21U-jre_x64_windows_hotspot_21.0.11_10.zip`
- Project: https://adoptium.net/temurin/
- License: GPLv2 with the Classpath Exception
- License text: https://openjdk.org/legal/gplv2+ce.html
- Binary SHA-256: `be26677aaa20b39a62edcaab4c8857a8b76673b0f45abc0b6143b142b62717e4`
- Corresponding source: `OpenJDK21U-jdk-sources_21.0.11_10.tar.gz`
- Source SHA-256: `891a3dd2341c37580fb81b56c4262f135e90c8f2acb059adb6ff0fdd76ae4385`
- Official source download: https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.11%2B10/OpenJDK21U-jdk-sources_21.0.11_10.tar.gz
- OpenJDK source commit: `254494ad7d75b37f1c033245fb4dbd460d0347b5`
- Temurin build source: `temurin-build-a612825ee82a20ac872d60958c349854c1f29a8e.tar.gz`
- Temurin build-source SHA-256: `1c0cdcec98d7f43652ad26b7a54f33172089018ca58759ffc6d6fc0ee18ebd3f`
- Temurin build-source download: https://github.com/adoptium/temurin-build/archive/a612825ee82a20ac872d60958c349854c1f29a8e.tar.gz
- Temurin build-source license: Apache-2.0
- Temurin build-source NOTICE: retained inside the exact source archive
- Build provenance: `OpenJDK21U-jre_x64_windows_hotspot_21.0.11_10.zip.json`
- Provenance SHA-256: `7fff112ea1f3f24f92113f0626440deb08b9d0f28e73d9fda3a5ef3a5596665c`
- Provenance download: https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.11%2B10/OpenJDK21U-jre_x64_windows_hotspot_21.0.11_10.zip.json

Under GPLv2 section 3(a), every Yomu release that offers this Temurin binary
must offer the OpenJDK source archive, exact Temurin build-source archive and
build-provenance metadata above from the same release download location. These
files are separate release assets and are not part of the Yomu binary archive.

The packaged JRE retains its upstream `NOTICE` file and `legal/` tree,
including the GPLv2 license, Classpath Exception, Assembly Exception and
third-party notices. Yomu does not modify the pinned JRE.

Eclipse Temurin and Suwayomi names identify their respective upstream
components. No endorsement of Yomu by those projects is implied.
