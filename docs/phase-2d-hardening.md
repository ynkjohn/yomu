# Fase 2D — Hardening (lifecycle, LAN/PWA, Maya)

## Objetivo

Fechar gaps de **ownership do Suwayomi**, **proxy de mídia/SSRF**, **pareamento**, **Maya download** e **leitor PWA** antes de novas features de produto (Source Builder, SQLite, design).

## Regras

- Suwayomi continua **somente** em `127.0.0.1:14567`
- Sem Docker
- Não matar processo sem provar ownership Yomu (PID + command line jar/rootDir)

## Entregas

### 1. Ciclo de vida Suwayomi

- Identidade persistida: `runtime/suwayomi-instance.json` (pid, runId, java, jar, rootDir, port)
- Sem adoção cega por health
- Órfão Yomu validado → kill → espera porta livre → start novo
- Processo estrangeiro → erro claro, sem kill
- `stop()` só emite `stopped` se health/porta caíram
- Ops serializadas; `shutdown()` coordenado (dispose = fallback)

### 2. Mídia / SSRF

- Cliente usa só `/api/v1/media?t=<ticket>` (ticket opaco, sessão-bound)
- `?u=` cru recusado (`raw_url_forbidden`)
- Externas: `SafeHttpFetch` (scheme, DNS/IP a cada redirect, bloqueio privado, max bytes/redirects)
- Health em LAN sanitizado (`yomu` + `suwayomiReady` apenas)
- CORS LAN: Origins explicitamente allowlisted

### 3. Pareamento

- 5 falhas / 10 min → 429 + Retry-After, pairing cancelado
- Sem log de código/token

### 4. Maya

- Download: `enqueue` + `startDownloader`
- `reject` não altera propostas `executed`/`failed`

### 5. PWA

- Preload janela: atual ±1/2; revoga blobs fora da janela
- Erro de progresso visível + Retry

## Verificação

```powershell
powershell -ExecutionPolicy Bypass -File tool/verify_workspace.ps1
```

Inclui testes `yomu_ai`, preload e `node apps/yomu_mobile_pwa/test_reader_races.mjs`.

## 2D.1 — confiabilidade

- Stop incompleto **preserva** `suwayomi-instance.json`
- Ownership: `-Dyomu.runId` + `-Dyomu.startedAt` + jar absoluto + java + rootDir + porta
- Identity save atômico (tmp + rename)
- Rate limit **por IP** (sem lockout global de outros devices)
- Sem confiança em `X-Forwarded-For`
- Proxy loopback **recusa redirects**
- PWA: generation ID, inflight map, progresso com `chapterId` capturado

### PWA e HTTP

A PWA em **HTTP** é **somente para LAN confiável** (opt-in + pairing).  
**HTTPS / Service Worker / A2HS de produção** ficam para a fase PWA final.
