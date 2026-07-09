# Phase 2B — UI mínima desktop

## Objetivo

Primeiro fluxo real de uso no **Yomu Desktop (Flutter)**, usando apenas campos GraphQL/REST confirmados no Gate funcional #1 e em `docs/suwayomi-api-matrix.md`.

## Como validar (critério de verde)

1. `flutter run -d windows` em `apps/yomu_desktop`
2. Aba **Servidor** → **Iniciar** Suwayomi (loopback `127.0.0.1:14567`)
3. Aba **Extensões** → **Garantir Keiyoushi + atualizar catálogo** → **Instalar MangaDex**
4. Aba **Explorar** → source MangaDex (en) → buscar `berserk` → abrir obra
5. Se a obra tiver capítulos, **Abrir primeiro capítulo**
6. Ver imagens reais no leitor mínimo (setas / botões Anterior·Próxima)

## Implementado

| Área | Tela | Capacidade |
|------|------|------------|
| Motor | `ServerScreen` | start/stop/restart, status, versão, porta, data root, erro, health |
| Extensões | `ExtensionsScreen` | list stores, ensure Keiyoushi, fetch catalog, list/filter, install MangaDex |
| Explorar | `ExploreScreen` | select source, SEARCH, results + thumbnail, open detail |
| Obra | `MangaDetailScreen` | title, thumb, meta, chapters list, empty chapters message, open chapter |
| Leitor | `ReaderScreen` | fetchChapterPages, Image.network, prev/next, keyboard arrows/space, loading/error |

### API layer

`packages/yomu_suwayomi/lib/src/client/suwayomi_api.dart` + models:

- `ensureKeiyoushiStore` / `addExtensionStore`
- `fetchExtensions` / `listExtensions`
- `installExtension` / `uninstallExtension`
- `listSources`
- `searchManga` (`fetchSourceManga` SEARCH)
- `getManga` / `fetchMangaChapters` / `listMangaChapters`
- `fetchChapterPages`
- `absoluteUrl` for loopback image paths

## Limitações (intencionais)

- Sem design final / theming rico
- Sem Maya, PWA completa, Source Builder
- Sem biblioteca persistente UI, progresso UI, downloads UI → **hard gate ainda pendente**
- Sem gestos webtoon avançados
- Catálogo de extensões: carrega uma vez e filtra localmente (amostra visual limitada)
- Algumas obras MangaDex podem ter 0 capítulos — UI mostra mensagem clara
- Thumbnails/páginas só funcionam com motor **running** (URLs loopback)
- Yomu HTTP em **127.0.0.1** apenas; PWA stub = dev, não release

## Fora de escopo (próximas fases)

1. Biblioteca / progresso / downloads  
2. PWA iPhone mínima  
3. Maya  
4. Source Builder  
5. Design final  

## Arquivos principais

```
apps/yomu_desktop/lib/shell/home_shell.dart
apps/yomu_desktop/lib/screens/server_screen.dart
apps/yomu_desktop/lib/screens/extensions_screen.dart
apps/yomu_desktop/lib/screens/explore_screen.dart
apps/yomu_desktop/lib/screens/manga_detail_screen.dart
apps/yomu_desktop/lib/screens/reader_screen.dart
packages/yomu_suwayomi/lib/src/client/suwayomi_api.dart
packages/yomu_suwayomi/lib/src/client/suwayomi_models.dart
```
