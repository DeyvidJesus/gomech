# Integração contínua (CI)

Cada repositório valida o que é seu. Assim, uma falha aponta direto para o serviço e para o comando que quebrou.

| Repositório | Workflow | O que valida |
| :--- | :--- | :--- |
| [`gomech`](https://github.com/DeyvidJesus/gomech) (raiz) | [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml) | Ponteiros dos submódulos, Terraform (GCP e AWS), `docker-compose.yml` e links da documentação |
| [`gomech-backend-v2`](https://github.com/DeyvidJesus/gomech-backend-v2) | `.github/workflows/ci.yml` | Regras de arquitetura (ArchUnit), testes unitários, testes de integração com PostgreSQL e empacotamento |
| [`gomech-frontend-v2`](https://github.com/DeyvidJesus/gomech-frontend-v2) | `.github/workflows/ci.yml` | `npm ci`, lint (ESLint, incluindo limites entre módulos) e build (type-check + Vite) |
| [`gomech-ai-service-v2`](https://github.com/DeyvidJesus/gomech-ai-service-v2) | `.github/workflows/ci.yml` | Lint (Ruff), testes (pytest) e importação da aplicação |

Todos os workflows rodam em push para `master` e em pull requests.

## Repositório raiz

| Job | Comando principal | Por quê |
| :--- | :--- | :--- |
| Submodule pointers | `actions/checkout` com `submodules: recursive` | Falha se a raiz apontar para um commit que nunca foi enviado ao repositório do serviço |
| Terraform (gcp/aws) | `terraform fmt -check`, `terraform init -backend=false`, `terraform validate` | Mantém os dois módulos válidos, inclusive o da AWS, que não está provisionado |
| Docker Compose config | `docker compose config --quiet` | Garante que o compose e o `.env.example` continuam coerentes |
| Documentation links | `lychee --offline` | Detecta links relativos quebrados nos Markdown |

## Backend: duas trilhas de teste

- **Unitária** (`./mvnw test`, Surefire): tudo o que não precisa de infraestrutura. Roda sem nada além da JDK.
- **Integração** (Failsafe, classes `*IT`): sobe o contexto completo da aplicação, o que executa o Flyway contra um PostgreSQL real. No CI, o PostgreSQL roda como *service container* com a mesma imagem e as mesmas credenciais do `docker-compose.yml` do backend.

As regras de arquitetura rodam primeiro, em um passo próprio. Assim, uma violação de limite entre módulos aparece como violação de arquitetura, e não como mais uma falha entre várias. A estratégia completa está na [ADR-015](../adr/ADR-015-estrategia-de-testes.md).

## Reproduzindo localmente

```bash
# Backend
cd backend
./mvnw -B -ntp test                      # trilha unitária
docker compose up -d postgres            # PostgreSQL para a trilha de integração
./mvnw -B -ntp verify                    # unitários + integração

# Frontend
cd frontend
npm ci && npm run lint && npm run build

# AI Service
cd ai
python -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt -r requirements-dev.txt
ruff check app tests && pytest

# Terraform (qualquer ambiente)
cd terraform/environments/gcp
terraform fmt -check -recursive ../.. && terraform init -backend=false && terraform validate
```

## Observações

- Nenhum workflow depende de nuvem: o PostgreSQL de teste roda dentro do runner do GitHub Actions.
- O deploy ainda não é automatizado. Build e publicação das imagens estão descritos em [`terraform/README.md`](../../terraform/README.md#como-provisionar-na-gcp).
