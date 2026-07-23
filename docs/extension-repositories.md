# Extension Repositories

## Primary ecosystem

Yomu uses **Suwayomi** to run Mihon/Tachiyomi extensions. Example trusted repo (Keiyoushi):

```
https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json
```

Index entry shape (observed):

- `name`, `pkg`, `apk`, `lang`, `code`, `version`, `nsfw`, `sources[]` (`name`, `lang`, `id`, `baseUrl`)

## Capacidades do motor

O motor auditado oferece adicionar/remover repositórios, listar extensões e
instalar, atualizar ou desinstalar extensões. Essas são capacidades do motor,
não uma promessa de que toda ação já atravesse a interface Yomu.

## Escopo atual e futuro do Yomu

- A UI/contrato atual cobre descoberta e a instalação/sincronização já
  atravessadas pelo gateway de extensões.
- Adição/remoção de URL de repositório e desinstalação só poderão virar fluxo de
  produto depois de contrato e confirmação próprios; o Yomu nunca executa APK.
- F5 tratará apenas **troca de fonte assistida**: validar um destino e pedir
  confirmação final, sem prometer transferir progresso, Histórico ou downloads.
  A obra original permanece até essa validação e confirmação.

## Functional gate #1

Yomu gerencia o motor → adicionar Keiyoushi → listar → instalar → abrir fonte
→ buscar → detalhes → capítulos → páginas.
