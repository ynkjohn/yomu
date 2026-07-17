# Yomu Desktop

Aplicativo Flutter Windows nativo que compõe a UI principal, o lifecycle do
Suwayomi-Server, o Yomu Core HTTP, autenticação local e a Maya.

## Limites arquiteturais

- Não é Electron, WebView ou browser shell.
- Suwayomi permanece somente em `127.0.0.1:14567`.
- Yomu Core usa `127.0.0.1:8787` por padrão; LAN/PWA exige opt-in.
- Catálogo, capítulos, downloads e fatos de leitura pertencem ao Suwayomi.
- O SQLite Yomu guarda somente extras do app; a P2C usa schema v5 no commit
  local `eda852b`, ainda sem push.
- Ações sensíveis da Maya exigem `ActionProposal` e confirmação explícita.
- O provider personalizado usa Chat Completions, endpoint explícito, HTTPS
  público ou HTTP em loopback literal e chave opcional somente no WinCred.

## Desenvolvimento

Versões fixas atuais: Flutter 3.32.5 e Dart 3.8.1.

```powershell
Set-Location 'C:\Users\joaop\Projetos\yomu'
flutter pub get
Set-Location apps\yomu_desktop
flutter run -d windows
```

## Testes e build

```powershell
Set-Location 'C:\Users\joaop\Projetos\yomu\apps\yomu_desktop'
flutter test
flutter analyze
flutter build windows --debug
```

Não execute o build enquanto o executável Yomu estiver aberto. Em `LNK1168`,
peça ao usuário para fechar o aplicativo normalmente; não encerre processos.

Para o gate completo do workspace, use na raiz:

```powershell
powershell -ExecutionPolicy Bypass -File tool\verify_workspace.ps1
```

Estado corrente, commits e próxima subfase:
[`docs/current-handoff.md`](../../docs/current-handoff.md).
