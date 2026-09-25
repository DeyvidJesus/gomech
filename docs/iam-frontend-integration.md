# Integração de identidade entre frontend e backend

Este guia resume o fluxo de autenticação e os pontos de código que conectam a SPA à API. O contrato OpenAPI publicado pelo backend é a referência para endpoints, campos e códigos HTTP; esta página explica a integração, sem manter cópias extensas de payloads.

## Fluxo de sessão

1. A pessoa autentica com e-mail/senha ou inicia o fluxo Google OAuth.
2. O backend valida a identidade e devolve access token e refresh token.
3. O frontend mantém a sessão no estado de autenticação e o cliente HTTP envia o access token como Authorization: Bearer ....
4. Quando a API rejeita um access token expirado, o cliente coordena a renovação; chamadas concorrentes aguardam a mesma renovação antes de tentar novamente.
5. A troca de unidade atualiza o escopo da sessão. O backend continua sendo a autoridade para permissões e tenant.

## Onde ler no código

| Responsabilidade | Local |
| :--- | :--- |
| Rotas de login, cadastro e callback Google | frontend/src/routes/login.tsx, register.tsx e auth.callback.google.tsx |
| Estado de autenticação | frontend/src/features/iam/stores/authStore.ts |
| Cliente HTTP e renovação | frontend/src/shared/api/apiClient.ts |
| Controllers e serviços IAM | backend/src/main/java/com/gomech/api/modules/iam/ |
| Segurança e contexto transversal | backend/src/main/java/com/gomech/api/core/security/ e core/tenancy/ |

O callback Google cadastrado no provedor deve corresponder à rota e à configuração do ambiente. Não coloque tokens ou credenciais reais no código ou no .env.example.

## Conceitos relacionados

- [ADR-005 — JWT e rotação de refresh tokens](adr/ADR-005-jwt-e-refresh-tokens.md)
- [ADR-006 — RBAC e permissões](adr/ADR-006-rbac-e-permissoes.md)
- [ADR-014 — Isolamento de tenant e unidade](adr/ADR-014-isolamento-de-tenant-e-unidade.md)
- [ADR-016 — OAuth 2.0 e OpenID Connect com Google](adr/ADR-016-oauth2-e-oidc-google.md)
- [Swagger UI local](http://localhost:8080/swagger-ui.html)
- [Guia do ambiente local](guias/ambiente-local.md)
