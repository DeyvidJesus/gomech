# Convenções do repositório

Como o código e a documentação do GoMech estão organizados, e as regras que mantêm essa organização.

## Um repositório por serviço, orquestrados por submódulos

```text
gomech/                  # este repositório: orquestração, infraestrutura e decisões
├── backend/   → gomech-backend-v2      (Spring Boot, monolito modular)
├── frontend/  → gomech-frontend-v2     (React SPA)
├── ai/        → gomech-ai-service-v2   (FastAPI, serviço de IA isolado)
├── docs/                               (ADRs, contratos entre serviços, guias e design)
├── terraform/                          (IaC para GCP e AWS)
└── docker-compose.yml                  (stack local completa)
```

**Por quê:** cada serviço tem runtime, dependências, CI e ciclo de release próprios, e pode ser lido de forma independente. O repositório raiz fixa **quais versões dos três funcionam juntas** (o commit de cada submódulo) e guarda o que é transversal: infraestrutura, stack local e decisões de arquitetura.

### Restrições arquiteturais

- Um único monolito modular Spring Boot em `backend/` ([ADR-001](../adr/ADR-001-monolito-modular.md)).
- Um único serviço FastAPI independente em `ai/`, sem banco de dados e acessado apenas pelo backend ([ADR-019](../adr/ADR-019-isolamento-do-servico-de-ia.md)).
- Sem premissas de Kubernetes: os serviços rodam como containers serverless ([ADR-020](../adr/ADR-020-terraform-multicloud-e-gcp.md)).

## Onde fica cada documento

| Tipo | Local |
| :--- | :--- |
| Decisões de arquitetura (ADRs) | `docs/adr/` (raiz) |
| Contratos entre dois ou mais serviços | `docs/contratos/` (raiz) |
| Guias da plataforma (ambiente local, CI, convenções) | `docs/guias/` (raiz) |
| Design (telas do Stitch e tokens) | `docs/design/` (raiz) |
| Infraestrutura | `terraform/README.md` (raiz) |
| Arquitetura e guias internos de um serviço | `docs/` **do repositório do serviço** |

Regra prática: se o documento só faz sentido dentro de um serviço, ele fica no repositório desse serviço. Se ele descreve algo entre serviços ou da plataforma, fica na raiz.

## Trabalhando com os submódulos

```bash
# Clonar tudo
git clone --recurse-submodules https://github.com/DeyvidJesus/gomech.git

# Atualizar os submódulos para os commits fixados na raiz
git submodule update --init --recursive

# Depois de commitar e enviar uma mudança dentro de um serviço, atualizar o ponteiro na raiz
cd backend && git push && cd ..
git add backend
git commit -m "chore(submodules): update backend"
```

O commit do serviço precisa ser enviado **antes** do commit da raiz que aponta para ele. O CI da raiz falha se um ponteiro referenciar um commit inexistente no remoto.

## Git

### Branches

`feature/<tema>`, `fix/<tema>`, `chore/<tema>` e `docs/<tema>`. A branch principal é `master`.

### Commits

[Conventional Commits](https://www.conventionalcommits.org/) com escopo pelo módulo de negócio, em inglês:

```text
feat(billing): add Pagar.me hosted checkout
fix(security): allow Cloud Run origin domains in CORS configuration
docs(adr): add ADR-020 multi-cloud Terraform
```

### Pull requests

- Um propósito claro por PR.
- Documentação atualizada quando o comportamento muda.
- Infraestrutura não se mistura com mudanças de produto no mesmo PR.

## ADRs

- Toda decisão arquitetural relevante vira uma ADR em `docs/adr/`, no formato Contexto → Decisão → Consequências.
- **Números nunca são reaproveitados.** Uma decisão revista ganha uma ADR nova, e a antiga passa a *Substituída por* (como a [ADR-013](../adr/ADR-013-infraestrutura-aws.md) → [ADR-020](../adr/ADR-020-terraform-multicloud-e-gcp.md)).
- O índice fica em [`docs/adr/README.md`](../adr/README.md).

## Segredos e configuração

- Nunca versione segredos reais. Versione apenas modelos (`.env.example`, `terraform.tfvars.example`).
- Valores locais ficam em arquivos `.env` e `terraform.tfvars`, ambos ignorados pelo git.
- Em produção, os segredos vivem no Secret Manager e são injetados no boot ([`terraform/README.md`](../../terraform/README.md#decisões-de-segurança)).
- Uma variável nova deve ser documentada no `.env.example` e no README do serviço que a consome.

## Idioma

- Documentação em português.
- Código, identificadores, comentários de código e mensagens de commit em inglês.
