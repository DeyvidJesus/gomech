# ADR-020: Terraform multi-cloud e GCP como ambiente de execução

- **Status:** Aceita
- **Data:** 2026-08-20
- **Substitui:** [ADR-013 — Infraestrutura na AWS](ADR-013-infraestrutura-aws.md)
- **Relacionadas:** [ADR-017 — Row Level Security](ADR-017-row-level-security-postgresql.md), [ADR-018 — Gateway de IA](ADR-018-gateway-de-ia.md), [ADR-019 — Isolamento do serviço de IA](ADR-019-isolamento-do-servico-de-ia.md)

## Contexto

A [ADR-013](ADR-013-infraestrutura-aws.md) escolheu a AWS como provedor de produção. Na hora de colocar o sistema no ar, dois fatores mudaram o cenário:

1. **Objetivo de aprendizado.** O projeto também serve para estudar Infraestrutura como Código e as duas maiores nuvens públicas. Descrever a mesma arquitetura nos dois provedores obriga a separar o que é requisito da aplicação do que é detalhe do provedor.
2. **Conta e integrações já existentes no Google.** Eu já tenho o plano Pro do Google, o que simplifica conta e faturamento. Além disso, o GoMech já depende de serviços do Google: login com Google OAuth 2.0/OIDC ([ADR-016](ADR-016-oauth2-e-oidc-google.md)) e o provider Gemini no serviço de IA.

Os requisitos técnicos da ADR-013 continuam válidos: aplicação sem SDK de nuvem, PostgreSQL 16 gerenciado com RLS, containers serverless com auto-scaling, segredos fora do código e frontend servido por HTTPS.

## Decisão

1. **Toda a infraestrutura é descrita em Terraform**, com um módulo por provedor (`terraform/modules/gcp` e `terraform/modules/aws`) e uma raiz executável por ambiente (`terraform/environments/<provedor>`). Os dois módulos implementam a mesma topologia: frontend, backend, AI service, PostgreSQL 16 e gerenciador de segredos.
2. **A GCP é o ambiente de execução.** O GoMech roda em três serviços Cloud Run (frontend nginx, backend Spring Boot e AI Service FastAPI) com Cloud SQL PostgreSQL 16, Secret Manager e Artifact Registry.
3. **O módulo AWS é mantido como estudo**: validado no CI e documentado, mas sem ambiente provisionado.
4. **A aplicação continua agnóstica de nuvem.** O backend conecta por JDBC padrão com SSL (`application-prod.yml`) e só lê variáveis de ambiente. Nenhum SDK ou *socket factory* de provedor entra no código.

| Requisito (ADR-013) | GCP | AWS |
| :--- | :--- | :--- |
| Containers serverless | Cloud Run | App Runner |
| PostgreSQL 16 gerenciado com RLS | Cloud SQL | RDS |
| Segredos injetados no boot | Secret Manager + service accounts | Secrets Manager + instance role |
| Frontend via HTTPS | Cloud Run (nginx) | S3 privado + CloudFront |

## Consequências

### Positivas

- A troca de provedor é uma decisão de infraestrutura, não de código: a mesma imagem de cada serviço roda nas duas nuvens.
- O Cloud Run escala a zero os serviços sem tráfego constante (AI Service), o que reduz o custo de um projeto com uso intermitente.
- Com a conta Google já ativa, a configuração inicial ficou mais simples, e OAuth, Gemini e infraestrutura ficaram no mesmo provedor.
- Os dois módulos são checados com `terraform fmt` e `terraform validate` no CI, o que mantém o módulo AWS coerente mesmo sem uso.

### Negativas e riscos

- Manter dois módulos custa esforço: toda mudança de topologia precisa ser replicada nos dois.
- O frontend na GCP é servido por nginx no Cloud Run, sem CDN dedicada. Para o volume atual é suficiente, mas com tráfego global o próximo passo é Cloud CDN ou um bucket com Load Balancer.
- O Cloud SQL usa IP público com SSL obrigatório. O caminho de evolução (IP privado com Direct VPC egress) está listado em [`terraform/README.md`](../../terraform/README.md#limitações-conhecidas-e-próximos-passos).
