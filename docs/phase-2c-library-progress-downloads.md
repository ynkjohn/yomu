# Phase 2C — Biblioteca, progresso e downloads

## Objetivo

Fechar o **hard gate** operacional: usar a biblioteca do Suwayomi, **salvar/retomar** progresso de leitura e enfileirar downloads — sem PWA/Maya/Source Builder.

## Fluxo de validação

1. Servidor → Iniciar Suwayomi  
2. Extensões → MangaDex instalado  
3. Explorar → obra → **Adicionar à biblioteca**  
4. Abrir capítulo → virar páginas → fechar leitor  
5. Biblioteca → **Continuar** retoma capítulo/página  
6. Na obra → Baixar capítulo(s) → aba Downloads mostra fila  

## Implementado

| Área | Onde |
|------|------|
| `listLibrary` / `setInLibrary` | `SuwayomiApi` |
| `updateChapterProgress` / `getChapter` | progresso `lastPageRead` + `isRead` |
| `getDownloadStatus`, enqueue/dequeue/clear/start/stop | downloads |
| UI Biblioteca | `library_screen.dart` |
| UI Downloads | `downloads_screen.dart` |
| Leitor com save debounce + resume | `reader_screen.dart` |
| Detalhe: biblioteca + download | `manga_detail_screen.dart` |

## GraphQL (confirmado em schema / matrix)

- `mangas(condition: { inLibrary: true })` (+ fallback list+filter)
- `updateManga(input: { id, patch: { inLibrary } })`
- `updateChapter(input: { id, patch: { lastPageRead, isRead } })`
- `chapter(id)`
- `downloadStatus { state queue { … } }`
- `enqueueChapterDownloads` / `dequeueChapterDownloads` / `clearDownloader` / `startDownloader` / `stopDownloader`

## Limitações

- UI ainda provisória (sem design final)
- Downloads = fila Suwayomi; gestão de disco limitada
- Retomada usa `lastPageRead` do motor (0-based page index)
- PWA/Maya/Source Builder continuam bloqueados

## Fora de escopo 2C

- PWA iPhone com LAN/auth  
- Maya  
- Source Builder  
- Design final  
