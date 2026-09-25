# Mapa de implementação do frontend

Este documento localiza as partes principais da SPA e evita duplicar contratos de API. Para padrões de estado, formulários, validação e limites entre módulos, consulte a [arquitetura do frontend](FRONTEND_ARCHITECTURE.md). Para identidade visual e telas de referência, consulte o [catálogo de design](design/README.md).

## Organização do código

| Caminho | Responsabilidade |
| :--- | :--- |
| frontend/src/routes/ | Rotas TanStack Router e composição das páginas |
| frontend/src/features/<domínio>/ | API, tipos, componentes e páginas de cada domínio |
| frontend/src/shared/api/ | Cliente HTTP, token e tratamento comum de respostas |
| frontend/src/shared/components/ | Componentes compartilhados da interface |
| frontend/src/shared/stores/ | Estado local compartilhado, como autenticação e layout |
| frontend/src/app/ | Configuração do roteador e do cliente TanStack Query |

## Rotas por domínio

As rotas são declaradas por arquivos em frontend/src/routes/. A tabela resume os grupos de navegação; os arquivos de rota e o contrato OpenAPI do backend são a referência para caminhos e payloads exatos.

| Área | Rotas principais | Código de domínio |
| :--- | :--- | :--- |
| Acesso e administração | /login, /register, /admin/* | features/iam/ |
| Painel | /dashboard | features/analytics/, features/iam/ |
| Clientes e veículos | /crm/* | features/crm/ |
| Agenda, inspeções e ordens | /operations/* | features/operations/ |
| Estoque | /inventory/* | features/inventory/ |
| Ferramentas | /tools/* | features/tools/ |
| Financeiro | /finance/* | features/finance/ |
| Assinaturas | /billing/* | features/billing/ |
| Relatórios | /analytics/reports | features/analytics/ |
| Portal do cliente | /portal/* | features/operations/ |

## Comunicação com a API

O cliente central está em frontend/src/shared/api/apiClient.ts. Ele resolve a URL base da API, envia o token de acesso e coordena a renovação de sessão. Código de domínio deve manter suas chamadas em features/<domínio>/api/ e usar os hooks de TanStack Query para leitura e mutação de dados remotos.

O contrato HTTP atualizado é exposto pelo backend em http://localhost:8080/swagger-ui.html quando a stack local está ativa. A integração de autenticação está resumida no [guia IAM entre frontend e backend](iam-frontend-integration.md).

## Executar

Use o [guia do ambiente local](guias/ambiente-local.md) para subir todos os serviços. Para trabalhar apenas no frontend:

    cd frontend
    npm ci
    npm run dev

VITE_API_URL define a URL base da API. Os comandos npm run lint e npm run build fazem parte das verificações do serviço; veja o [guia de CI](guias/ci.md).
