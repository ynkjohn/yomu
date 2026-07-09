# Extension Repositories

## Primary ecosystem

Yomu uses **Suwayomi** to run Mihon/Tachiyomi extensions. Example trusted repo (Keiyoushi):

```
https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json
```

Index entry shape (observed):

- `name`, `pkg`, `apk`, `lang`, `code`, `version`, `nsfw`, `sources[]` (`name`, `lang`, `id`, `baseUrl`)

## Yomu responsibilities

- Add/remove repository URLs (validate HTTPS, JSON shape)
- List extensions (via Suwayomi API once validated)
- Install / update / uninstall / surface errors
- Show origin; confirm before installing from **untrusted** repos
- Never execute APKs itself

## Functional gate #1

Suwayomi start → add Keiyoushi → list → install → open source → search → details → chapters → pages.
