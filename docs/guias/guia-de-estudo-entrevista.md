# Guia de estudo do GoMech para entrevista

Este guia é um roteiro para recuperar o contexto do projeto e explicá-lo com segurança. Ele descreve o estado registrado neste repositório. Diferencie sempre o que está implementado, o que está simulado e o que é uma configuração de estudo.

## Resumo em 30 segundos

O GoMech é uma plataforma web para gestão de oficinas mecânicas. Ela reúne clientes e veículos, agenda, inspeções, orçamentos, ordens de serviço, estoque, ferramentas, financeiro e indicadores. A aplicação principal é um backend Spring Boot organizado como monólito modular, acompanhado de um frontend React e de um serviço de IA independente em FastAPI. O sistema usa PostgreSQL com isolamento multi-tenant. Terraform descreve ambientes equivalentes para GCP e AWS; a implantação ativa está na GCP.

## Mapa do repositório

A raiz é um repositório de orquestração. `ai/`, `backend/` e `frontend/` são submódulos Git: cada um tem seu próprio histórico, remoto e commits. O repositório raiz fixa os commits de serviço usados juntos.

| Diretório | O que contém | Por onde começar |
| :--- | :--- | :--- |
| [`backend/`](../../backend) | API e regras de negócio em Java 21 / Spring Boot | [`GoMechV2ApiApplication.java`](../../backend/src/main/java/com/gomech/api/GoMechV2ApiApplication.java) e `src/main/java/com/gomech/api/` |
| [`frontend/`](../../frontend) | SPA React 19 e TypeScript | [`src/main.tsx`](../../frontend/src/main.tsx), [`src/app/router.ts`](../../frontend/src/app/router.ts) e `src/features/` |
| [`ai/`](../../ai) | API Python / FastAPI e adaptadores de provedores de IA | [`app/main.py`](../../ai/app/main.py), `app/api/` e `app/infrastructure/providers/` |
| [`terraform/`](../../terraform) | Módulos e ambientes Terraform para GCP e AWS | [`README.md`](../../terraform/README.md), `environments/gcp/` e `modules/gcp/` |
| [`docs/`](..) | Arquitetura, contratos, decisões, guias e protótipos de interface | [`adr/README.md`](../adr/README.md) |
| Raiz | Docker Compose, CI e configuração compartilhada local | [`docker-compose.yml`](../../docker-compose.yml), [`.env.example`](../../.env.example) |

### Domínios do backend

Os módulos de negócio ficam em `backend/src/main/java/com/gomech/api/modules/`:

- `iam`: autenticação, usuários, papéis, permissões e unidades.
- `crm`: clientes e veículos.
- `operations`: agenda, inspeções, orçamentos e ordens de serviço.
- `inventory`: produtos, estoque, reservas e movimentações.
- `tools`: equipamentos reutilizáveis, custódia e manutenção.
- `finance`: contas a pagar e receber, transações e relatórios financeiros.
- `billing`: planos, assinaturas, cobrança e entitlements.
- `analytics`: indicadores, projeções e relatórios gerenciais.
- `ai`: gateway de IA, auditoria de solicitações e propostas de ação.

Cada módulo separa `api`, `application`, `domain`, `infrastructure` e, quando publica fatos de negócio, `events`. O pacote `core/` concentra capacidades transversais, como segurança, tenancy, autorização, auditoria, entitlements e barramento de eventos. A fronteira entre módulos é importante: use contratos públicos em `api/` ou eventos, sem acessar repositórios internos de outro domínio.

No frontend, as rotas de `src/routes/` conectam URLs a páginas; `src/features/` agrupa código por domínio. TanStack Query gerencia dados remotos, enquanto Zustand guarda estado local compartilhado, como sessão e layout. A instância Axios concentra autenticação e renovação de tokens.

No serviço de IA, `api/` declara rotas, `application/` coordena casos de uso, `domain/` contém schemas e guardrails e `infrastructure/providers/` adapta os provedores. O serviço não possui conexão com o PostgreSQL.

## Arquitetura explicada por fluxos

### Uma ordem de serviço e os módulos de negócio

1. O usuário acessa uma rota do frontend; a tela carrega ou altera dados pela API REST.
2. O controller do módulo `operations` valida a entrada e delega o caso de uso à camada `application`.
3. O caso de uso aplica regras e persiste pelo repositório pertencente ao módulo, dentro da transação.
4. Quando uma mudança tem consequências para outros domínios, o módulo publica um evento. Finance, inventory e analytics reagem por meio de seus próprios handlers ou contratos.

Os eventos do monólito são despachados dentro do processo Spring. Isso reduz acoplamento entre domínios, mas não é uma fila distribuída durável: é um trade-off consciente e uma boa pergunta para discutir consistência, falhas e uma possível evolução com outbox ou broker.

### Isolamento de oficina e unidade

O backend deriva o tenant autenticado do contexto de segurança e carrega o escopo da unidade conforme a requisição. O código diferencia um tenant comprovado por autenticação de uma seleção enviada pelo cliente; um header público não pode substituir silenciosamente o tenant de um token válido. PostgreSQL Row Level Security adiciona uma barreira no banco, além das verificações da aplicação. As migrations Flyway versionam o schema e as políticas.

Pontos de leitura: [`TenantContextHolder.java`](../../backend/src/main/java/com/gomech/api/core/tenancy/TenantContextHolder.java), [`TenantSource.java`](../../backend/src/main/java/com/gomech/api/core/tenancy/TenantSource.java), [`V3__Enable_Tenant_And_Unit_Row_Level_Security.sql`](../../backend/src/main/resources/db/migration/V3__Enable_Tenant_And_Unit_Row_Level_Security.sql) e as ADRs [014](../adr/ADR-014-isolamento-de-tenant-e-unidade.md) e [017](../adr/ADR-017-row-level-security-postgresql.md).

### Solicitação de IA e confirmação humana

O desenho coloca o gateway no backend para aplicar autenticação, permissão, quota, sanitização de dados sensíveis, auditoria e métricas. A IA pode produzir uma proposta estruturada; alterações de negócio passam por uma proposta com validade e estado, e exigem confirmação explícita do operador. Quando confirmada, a ação usa um contrato público do módulo dono, como `OperationsActionContract`, em vez de gravar diretamente nas entidades de Operations.

**Estado importante do código:** o FastAPI está implementado e a infraestrutura Terraform prevê um serviço de IA privado. Porém, `DefaultAiServiceExecutor` no backend ainda gera respostas simuladas dentro do processo; a integração HTTP do backend com o serviço FastAPI não está conectada. Apresente o gateway e o serviço Python como componentes existentes, e a ligação entre eles como trabalho futuro. O detalhe está em [`docs/contratos/gateway-de-ia.md`](../contratos/gateway-de-ia.md) e nas ADRs [018](../adr/ADR-018-gateway-de-ia.md) e [019](../adr/ADR-019-isolamento-do-servico-de-ia.md).

Para acompanhar a confirmação no código, leia [`AiActionConfirmationService.java`](../../backend/src/main/java/com/gomech/api/modules/ai/application/AiActionConfirmationService.java), [`OperationsActionContract.java`](../../backend/src/main/java/com/gomech/api/modules/operations/api/OperationsActionContract.java) e os componentes em `frontend/src/features/ai/`.

### Analytics

O módulo `analytics` recebe eventos de negócio, verifica duplicidade por tenant/evento e atualiza projeções próprias para ordens de serviço, finanças, estoque e ferramentas. Consultas e relatórios leem essas projeções em vez de atravessar os repositórios dos módulos de origem. Como handlers podem executar de forma assíncrona, os indicadores podem refletir eventos com pequeno atraso.

Pontos de leitura: [`AnalyticsEventListener.java`](../../backend/src/main/java/com/gomech/api/modules/analytics/application/AnalyticsEventListener.java), `backend/src/main/resources/db/migration/V18__Create_Analytics_Tables_And_Permissions.sql` e [`contratos e semântica dos KPIs`](../ANALYTICS_KPI_CONTRACTS_AND_SEMANTICS.md).

## Nuvem e infraestrutura

Terraform descreve a aplicação em duas nuvens para fins de estudo e comparação:

- **GCP, ambiente ativo:** Cloud Run para frontend, backend e serviço de IA; Cloud SQL PostgreSQL; Secret Manager e Artifact Registry.
- **AWS, configuração de referência:** App Runner, RDS, S3/CloudFront e gerenciador de segredos.

A GCP foi escolhida porque eu já tinha o plano Pro do Google, o que simplificou o processo de conta e faturamento. O código Terraform da AWS demonstra o estudo multicloud e não representa uma segunda implantação. Veja [`terraform/README.md`](../../terraform/README.md) e a [ADR-020](../adr/ADR-020-terraform-multicloud-e-gcp.md).

Trade-offs conhecidos para falar com transparência: o estado Terraform ainda é local, a publicação das imagens não está automatizada e o módulo AWS precisa de ajustes de rede antes de um uso real. Consulte a seção de limitações no guia Terraform para os detalhes atuais.

## Rodar a stack local

Pré-requisitos: Git com suporte a submódulos e Docker Compose v2.

```bash
git clone --recurse-submodules https://github.com/DeyvidJesus/gomech.git
cd gomech
cp .env.example .env
docker compose up --build
```

A configuração padrão usa o provider `mock` no serviço Python e simulação no executor do gateway do backend; chaves externas de IA não são necessárias para subir a stack. Endereços locais:

- Frontend: <http://localhost:5173>
- API: <http://localhost:8080/api/v1>
- Health da API: <http://localhost:8080/actuator/health>
- Swagger UI: <http://localhost:8080/swagger-ui.html>
- Health e OpenAPI do serviço Python: <http://localhost:8000/health> e <http://localhost:8000/docs>
- PostgreSQL: `localhost:5432`

O passo a passo completo, as variáveis e os comandos para desligar a stack estão no [guia do ambiente local](ambiente-local.md).

## Roteiro de revisão para uma semana

1. **Mapa geral:** leia este guia, o README e percorra a aplicação local, se o ambiente estiver disponível.
2. **Backend:** siga um fluxo de ordem de serviço no controller, serviço de aplicação, repositório e evento. Leia as ADRs 001–004.
3. **Segurança:** revise autenticação, contexto de tenant, unidade, permissões e RLS. Prepare um exemplo concreto de como o sistema evita acesso cruzado entre oficinas.
4. **IA:** leia o gateway, o serviço FastAPI e o fluxo de confirmação. Memorize a diferença entre integração alvo e executor simulado atual.
5. **Analytics:** siga um evento até a projeção e explique idempotência e consistência eventual.
6. **Nuvem:** percorra o módulo GCP e compare com AWS. Explique o motivo prático da escolha da GCP e quais partes são apenas exercício.
7. **Ensaio:** pratique a apresentação de 90 segundos abaixo e responda às perguntas sem ler o texto.

## Apresentação de 90 segundos

> O GoMech é uma plataforma de gestão para oficinas mecânicas. Eu organizei o backend como um monólito modular Spring Boot: os domínios de IAM, CRM, operações, estoque, ferramentas, financeiro, billing, analytics e IA têm limites internos e conversam por contratos ou eventos. Essa escolha mantém um deploy operacionalmente simples sem abandonar separação de domínio. O PostgreSQL usa migrations versionadas e Row Level Security para defesa em profundidade no isolamento entre oficinas. O frontend é uma SPA React e existe também um serviço Python/FastAPI isolado para capacidades de IA. No estado atual, o serviço Python está implementado, mas o executor do gateway no backend ainda usa respostas simuladas; a integração HTTP é uma evolução pendente. Também descrevi a infraestrutura com Terraform para GCP e AWS. O ambiente ativo roda na GCP, que escolhi porque já tinha o plano Pro do Google e isso facilitou conta e faturamento; AWS é referência de estudo. Uma decisão que eu revisaria conforme a escala é a entrega de eventos assíncronos: hoje o barramento é in-process, então avaliar outbox e broker seria um próximo passo para obter entrega durável.

Ajuste a apresentação para refletir sua participação exata nas decisões e na implementação.

## Perguntas que podem surgir

**Por que monólito modular em vez de microserviços?**

Porque os domínios precisam de limites claros, mas dividir cada domínio em deploys independentes adicionaria custo operacional e comunicação distribuída sem necessidade atual. O desenho preserva fronteiras para evoluir depois.

**Como os módulos evitam dependências circulares?**

O módulo dono publica contratos na camada `api` para operações síncronas e eventos para consequências desacopladas. Regras de arquitetura são verificadas no backend com ArchUnit.

**Como é feito o isolamento multi-tenant?**

O tenant autenticado vem do token/contexto validado, a unidade faz parte do escopo de acesso e as queries ficam protegidas pelas regras da aplicação e pelo RLS no PostgreSQL. O valor enviado pelo cliente não pode sobrescrever um tenant já confiável.

**A IA altera dados sozinha?**

Não deve. O serviço retorna conteúdo ou propostas estruturadas; uma ação que muda o domínio exige confirmação autenticada e passa pelo contrato do módulo responsável. Além disso, a chamada da aplicação ao FastAPI ainda não está conectada no executor atual.

**O que acontece se um consumidor de evento falhar?**

O barramento atual é in-process e não oferece as mesmas garantias de persistência e reentrega de um broker. A resposta depende do handler e da semântica definida para o evento. Para maior durabilidade, uma evolução possível é outbox e mensageria, com idempotência explícita.

**Por que GCP? E onde entra AWS?**

A escolha operacional foi a GCP porque o plano Pro já estava disponível e simplificou conta e faturamento. AWS foi mantida como exercício de Terraform multicloud e configuração de referência, não como ambiente em produção.

**Qual o principal próximo passo técnico?**

Conectar o `AiServiceClient` do backend ao FastAPI com autenticação de serviço, timeouts, tratamento de falhas e mapeamento dos contratos; depois, automatizar publicação e deploy, e considerar estado Terraform remoto e entrega durável de eventos.

## Leituras de apoio

- [Arquitetura do backend](../BACKEND_ARCHITECTURE.md)
- [Arquitetura do frontend](../FRONTEND_ARCHITECTURE.md)
- [ADRs](../adr/README.md)
- [Contrato do gateway de IA](../contratos/gateway-de-ia.md)
- [Especificação do serviço FastAPI](../AI_SERVICE_SPECIFICATION.md)
- [Guia Terraform](../../terraform/README.md)
- [Ambiente local](ambiente-local.md)
- [CI](ci.md)
