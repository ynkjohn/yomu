# Yomu — regras operacionais

- Trabalhe somente em `C:\Users\joaop\Projetos\yomu`. Rejeite explicitamente `C:\Users\joaop\Projetos\multiyomi`.
- Yomu desktop é Flutter Windows nativo. Suwayomi usa `127.0.0.1:14567`; Yomu Core usa `127.0.0.1:8787`.
- Desktop é a fonte de verdade. O banco Suwayomi guarda catálogo e fatos de leitura; o SQLite Yomu guarda somente extras do app.
- 2D.2 e P0 estão concluídos. P1 e P2+ são futuros. Source Builder é a última fase.
- `design_prod/**` é referência imutável: nunca editar, mover, formatar, stagear ou commitar.
- Preserve a working tree suja. Não use Git destrutivo, `git add .`, stage, commit ou push sem permissão explícita.
- Nunca encerre Yomu, Java ou libere portas sem ownership comprovada e permissão. Em `LNK1168`, peça que o usuário feche Yomu normalmente.
- Gates obrigatórios: testes direcionados, storage, analyzer, verifier, build Windows seguro, `git diff --check`, status e evidência visual atual.
- Relatórios devem separar P0 committed, working tree inicial, mudanças desta sessão, validação atual e limitações.
