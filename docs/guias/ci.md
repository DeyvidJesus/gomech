# Integração contínua (CI)

[![CI raiz](https://github.com/DeyvidJesus/gomech/actions/workflows/ci.yml/badge.svg)](https://github.com/DeyvidJesus/gomech/actions/workflows/ci.yml)
[![CI backend](https://github.com/DeyvidJesus/gomech-backend-v2/actions/workflows/ci.yml/badge.svg)](https://github.com/DeyvidJesus/gomech-backend-v2/actions/workflows/ci.yml)
[![CI frontend](https://github.com/DeyvidJesus/gomech-frontend-v2/actions/workflows/ci.yml/badge.svg)](https://github.com/DeyvidJesus/gomech-frontend-v2/actions/workflows/ci.yml)
[![CI AI Service](https://github.com/DeyvidJesus/gomech-ai-service-v2/actions/workflows/ci.yml/badge.svg)](https://github.com/DeyvidJesus/gomech-ai-service-v2/actions/workflows/ci.yml)

Cada repositório valida o que é seu. Assim, uma falha aponta direto para o serviço e para o comando que quebrou.

| Repositório | Workflow | O que valida |
| :--- | :--- | :--- |
| [`gomech`](https://github.com/DeyvidJesus/gomech) (raiz) | [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml) | Ponteiros dos submódulos, Terraform (GCP e AWS), `docker-compose.yml` e links da documentação |
| [`gomech-backend-v2`](https://github.com/DeyvidJesus/gomech-backend-v2) | [`.github/workflows/ci.yml`](https://github.com/DeyvidJesus/gomech-backend-v2/blob/master/.github/workflows/ci.yml) | `./mvnw verify` com JDK 21: testes unitários e regras de arquitetura (ArchUnit), testes de integração com PostgreSQL (Testcontainers) e empacotamento |
| [`gomech-frontend-v2`](https://github.com/DeyvidJesus/gomech-frontend-v2) | [`.github/workflows/ci.yml`](https://github.com/DeyvidJesus/gomech-frontend-v2/blob/master/.github/workflows/ci.yml) | `npm ci`, lint (ESLint, incluindo limites entre módulos) e build (`tsc -b` + Vite), com o Node do `.nvmrc` |
| [`gomech-ai-service-v2`](https://github.com/DeyvidJesus/gomech-ai-service-v2) | [`.github/workflows/ci.yml`](https://github.com/DeyvidJesus/gomech-ai-service-v2/blob/master/.github/workflows/ci.yml) | Lint (Ruff), testes (pytest) e boot da aplicação com `/health` |

Todos os workflows rodam em push para `master` e em pull requests.

## Repositório raiz

| Job | Comando principal | Por quê |
| :--- | :--- | :--- |
| Submodule pointers | `actions/checkout` com `submodules: recursive` | Falha se a raiz apontar para um commit que nunca foi enviado ao repositório do serviço |
| Terraform (gcp/aws) | `terraform fmt -check`, `terraform init -backend=false`, `terraform validate` | Mantém os dois módulos válidos, inclusive o da AWS, que não está provisionado |
| Docker Compose config | `docker compose config --quiet` | Garante que o compose e o `.env.example` continuam coerentes |
| Documentation links | `lychee --offline` | Detecta links relativos quebrados nos Markdown |

## Backend: duas trilhas de teste

- **Unitária** (`./mvnw test`, Surefire): tudo o que não precisa de infraestrutura, incluindo as regras de arquitetura (ArchUnit). Roda sem nada além da JDK 21.
- **Integração** (Failsafe, classes `*IT`): sobe o contexto completo da aplicação, o que executa o Flyway contra um PostgreSQL real. Cada classe inicia o próprio `postgres:16-alpine` com Testcontainers, então só é preciso ter Docker. O runner `ubuntu-latest` do GitHub Actions já tem.

A CI roda um único passo, `./mvnw -B -ntp verify`: o Surefire executa primeiro os testes unitários e de arquitetura, e o Failsafe só roda se eles passarem. Quando algo falha, os relatórios do Surefire e do Failsafe ficam disponíveis como artefato da execução. A estratégia completa está na [ADR-015](../adr/ADR-015-estrategia-de-testes.md).

## Reproduzindo localmente

```bash
# Backend
cd backend
./mvnw -B -ntp test                      # trilha unitária (unitários + ArchUnit)
./mvnw -B -ntp verify                    # unitários + integração (exige Docker para o Testcontainers)

# Frontend
cd frontend
npm ci && npm run lint && npm run build

# AI Service
cd ai
python -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt -r requirements-dev.txt
ruff check app tests && pytest           # os testes rodam com ENVIRONMENT=test (tests/conftest.py)

# Terraform (qualquer ambiente)
cd terraform/environments/gcp
terraform fmt -check -recursive ../.. && terraform init -backend=false && terraform validate
```

## Observações

- Nenhum workflow depende de nuvem: o PostgreSQL de teste roda em containers do Testcontainers dentro do runner do GitHub Actions.
- O deploy ainda não é automatizado. Build e publicação das imagens estão descritos em [`terraform/README.md`](../../terraform/README.md#como-provisionar-na-gcp).
