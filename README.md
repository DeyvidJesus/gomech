# GoMech

Plataforma web para gestão de oficinas mecânicas. O GoMech reúne em um só sistema o cadastro de clientes e veículos, a agenda de serviços, orçamentos, ordens de serviço, estoque, ferramentas, financeiro e indicadores. A plataforma também inclui fluxos assistidos por IA para apoiar operações da oficina.

Este repositório é o ponto de entrada do projeto: fixa as versões dos serviços mantidos em repositórios próprios, documenta decisões compartilhadas, contém a infraestrutura como código e orquestra a stack local.

## Visão geral

```text
┌──────────────────┐       ┌────────────────────────┐
│ React + TypeScript├──────►│ API Spring Boot        │──────► PostgreSQL 16
└──────────────────┘       │ Monólito modular       │
                           └───────────┬────────────┘
                                       │ gateway interno
                           ┌───────────▼────────────┐
                           │ Serviço de IA          │──────► Gemini / mock
                           │ FastAPI                 │
                           └────────────────────────┘
```

- **Frontend:** aplicação web SPA com React, TypeScript, Vite e TanStack Router/Query.
- **Backend:** API REST em Java 21 e Spring Boot 3, organizada como monólito modular. PostgreSQL é versionado por migrations Flyway; autenticação e autorização usam JWT, RBAC e isolamento por oficina/unidade.
- **Serviço de IA:** serviço Python com FastAPI, isolado do backend e acessado pelo gateway de IA. O provider mock é o padrão local; o adaptador Gemini usa o modelo externo em /chat, enquanto outras capacidades ainda usam o mock no estado atual.
- **Persistência:** PostgreSQL 16, com controles de isolamento de dados por tenant e políticas Row Level Security.
- **Infraestrutura:** Terraform mantém implementações de referência para GCP e AWS. O ambiente atualmente implantado está na **GCP**.

## Repositórios e diretórios

`ai/`, `backend/` e `frontend/` são Git submodules. O repositório raiz registra um commit específico de cada serviço, permitindo evoluir cada componente separadamente e reproduzir uma composição conhecida da plataforma. As URLs dos submodules são relativas ao repositório raiz, então o clone funciona tanto por HTTPS quanto por SSH.

| Caminho | Responsabilidade |
| :--- | :--- |
| [`ai/`](ai) | Serviço de IA em Python/FastAPI (`gomech-ai-service-v2`) |
| [`backend/`](backend) | API de negócio em Java/Spring Boot (`gomech-backend-v2`) |
| [`frontend/`](frontend) | Aplicação web em React/TypeScript (`gomech-frontend-v2`) |
| [`terraform/`](terraform) | Módulos reutilizáveis e ambientes Terraform para GCP e AWS |
| [`docs/`](docs) | Arquitetura, decisões, contratos, guias e protótipos de interface |
| [`.github/workflows/`](.github/workflows) | CI do repositório de orquestração |
| [`docker-compose.yml`](docker-compose.yml) | Ambiente local integrado |

Cada backend domain module mantém suas próprias camadas `api`, `application`, `domain`, `events` e `infrastructure`. O diretório `core` contém capacidades transversais, como segurança, autorização, tenancy, auditoria e eventos. No serviço de IA, `api`, `application`, `domain`, `infrastructure` e `core` separam contrato HTTP, casos de uso, conceitos de domínio e integrações.

## Executar localmente

**Pré-requisitos:** Git com suporte a submodules e Docker Engine/Desktop com Docker Compose v2.

```bash
git clone --recurse-submodules https://github.com/DeyvidJesus/gomech.git
cd gomech
cp .env.example .env
docker compose up --build
```

Se o projeto já estiver clonado sem os submodules:

```bash
git submodule update --init --recursive
```

A stack inicializa PostgreSQL, backend, serviço de IA e frontend. O Flyway aplica as migrations quando a API inicia. A configuração local usa provider de IA `mock` por padrão e valores de integração simulados; credenciais reais são opcionais.

| Serviço | Endereço local |
| :--- | :--- |
| Frontend | <http://localhost:5173> |
| API | <http://localhost:8080/api/v1> |
| Health da API | <http://localhost:8080/actuator/health> |
| Swagger UI | <http://localhost:8080/swagger-ui.html> |
| Health da IA | <http://localhost:8000/health> |
| OpenAPI da IA | <http://localhost:8000/docs> |
| PostgreSQL | `localhost:5432` |

Para configurar variáveis, depurar serviços ou encerrar a stack, consulte o [guia do ambiente local](docs/guias/ambiente-local.md). Não use credenciais de produção no arquivo `.env` local.

## Cloud e Terraform

O projeto também serve como estudo prático de infraestrutura como código com Terraform e dos serviços de nuvem da AWS e da Google Cloud Platform. Há configurações de referência para os dois provedores, que representam componentes equivalentes da plataforma.

A plataforma está rodando na **GCP**. A escolha foi pragmática: eu já tinha o plano Pro do Google, o que facilitou o processo de conta e faturamento. O ambiente AWS permanece como configuração de estudo e referência de arquitetura; não está implantado. A decisão e o escopo de cada ambiente estão descritos na [ADR-020](docs/adr/ADR-020-terraform-multicloud-e-gcp.md) e no [guia Terraform](terraform/README.md).

## Documentação

- [Arquitetura do backend](docs/BACKEND_ARCHITECTURE.md) e [arquitetura do frontend](docs/FRONTEND_ARCHITECTURE.md)
- [Mapa de implementação do frontend](docs/FRONTEND_IMPLEMENTATION_GUIDE.md) e [integração IAM](docs/iam-frontend-integration.md)
- [Contratos e especificação do serviço de IA](docs/AI_SERVICE_SPECIFICATION.md), [contrato do gateway](docs/contratos/gateway-de-ia.md) e [fluxo de confirmação de ações](docs/AI_ACTION_CONFIRMATION_FLOW.md)
- [Semântica dos indicadores e KPIs](docs/ANALYTICS_KPI_CONTRACTS_AND_SEMANTICS.md)
- [Decisões de arquitetura (ADRs)](docs/adr/README.md)
- [Design system e protótipos](docs/design/README.md)
- [Convenções do repositório](docs/guias/convencoes-do-repositorio.md)
- [CI e validações](docs/guias/ci.md)
- [Integrações Resend e WhatsApp](docs/integrations-resend-whatsapp.md)

## Validação contínua

A CI da raiz valida os ponteiros dos submodules, o formato e a validação dos ambientes Terraform, a configuração do Docker Compose e os links relativos da documentação. Os projetos de frontend, backend e IA têm seus próprios workflows e comandos; veja o [guia de CI](docs/guias/ci.md) para reproduzi-los.

## Licença

Ainda não há uma licença definida para este repositório.
