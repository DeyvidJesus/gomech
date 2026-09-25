# ADR-007: Contrato de entitlement no Core e avaliação de billing baseada em assinatura

- **Status:** Aceita
- **Data:** 2026-08-19

## Contexto

No GoMech V2, o controle de acesso é composto por duas dimensões ortogonais e independentes:

1. **Autorização (IAM / RBAC / PBAC):** determina *quem* é o ator e *quais ações* ele pode executar, com base nos papéis atribuídos (ex.: `Proprietário`, `Mecânico`, permissão `OPERATIONS_WORK_ORDER_WRITE`).
2. **Elegibilidade e cotas (Billing / Entitlement):** determina se a organização (*tenant*) contratou um plano que contempla o módulo desejado (ex.: Financeiro, IA) e se ainda tem saldo de cota disponível para o recurso (ex.: limite de usuários ativos, filiais cadastradas, consultas de IA, armazenamento em MB, mensagens de WhatsApp).

Antes desta decisão, o sistema usava no Core um placeholder estático (`StaticEntitlementService`) que apenas repassava as permissões do token, sem consultar planos, módulos ou cotas.

### Requisitos e restrições arquiteturais

- **Separação estrita de módulos ([ADR-001](ADR-001-monolito-modular.md) / [ADR-002](ADR-002-camadas-e-regras-de-dependencia.md)):** o Core define a interface do contrato (`EntitlementService`, `EntitlementSnapshot`, `QuotaDimension`, `EntitlementDecision`, `QuotaDecision` e as exceções de domínio). O módulo `Billing` fornece a implementação operacional (`BillingEntitlementService`).
- **Desacoplamento IAM → Billing:** o módulo `IAM` **não pode** depender de `Billing`. O IAM emite eventos de domínio (`TenantCreatedEvent`) via `DomainEventBus` para notificar a criação de oficinas. A verificação de limites (ex.: criação de filiais em `UnitService` ou de usuários em `UserService`) consome exclusivamente a interface do Core. Essa regra é garantida por um teste de arquitetura ArchUnit (`iam_must_not_depend_on_billing`).
- **Avaliação fail-closed:** se uma assinatura estiver inoperante (ex.: `CANCELED`, `PAST_DUE`) ou se o módulo/cota não estiver ativo no plano, o acesso é negado (HTTP 402 Payment Required para cotas ou HTTP 403 Forbidden para módulos).

## Decisão

### 1. Definição do contrato no Core (`com.gomech.api.core.entitlement`)

- **`EntitlementService`**:
  - `EntitlementSnapshot resolve(ActorContext actor)`: faz a interseção entre as permissões atribuídas ao usuário e os módulos habilitados no plano da organização.
  - `EntitlementDecision checkModuleAccess(UUID tenantId, String moduleCode)`: avalia se o módulo de negócio está habilitado no plano.
  - `QuotaDecision checkQuota(UUID tenantId, QuotaDimension dimension, long requestedIncrement)`: verifica se `currentUsage + requestedIncrement <= limit` (ou se o limite é -1, ou seja, ilimitado).
  - `void recordUsage(UUID tenantId, QuotaDimension dimension, long amount)`: incrementa o consumo medido da cota no ciclo atual.
  - `EntitlementSnapshot getTenantEntitlements(UUID tenantId)`: obtém o catálogo de capacidades ativas do tenant.

### 2. Dimensões padronizadas de cota (`QuotaDimension`)

- `USERS`: quantidade máxima de usuários ativos na organização.
- `UNITS`: quantidade máxima de filiais/unidades físicas cadastradas.
- `AI_USAGE`: quantidade de requisições/tokens para diagnósticos e para o assistente de IA.
- `STORAGE_MB`: espaço de armazenamento de anexos, laudos e fotos (MB).
- `WHATSAPP_MESSAGES`: disparos de mensagens e avisos pelo WhatsApp.
- `REPORTS`: quantidade de relatórios e exportações no período.
- `MODULE_ACCESS`: acesso booleano a módulos (`MODULE_CRM`, `MODULE_OPERATIONS`, `MODULE_INVENTORY`, `MODULE_FINANCE`, `MODULE_AI`).

### 3. Modelo de dados de billing

- **`billing_plans`**: catálogo de planos (`TRIAL`, `STARTER`, `PRO`, `ENTERPRISE`), preços e ciclos de faturamento.
- **`billing_plan_features`**: mapeamento granular de cotas (`limit_value`) e flags de módulo (`enabled`) por plano.
- **`subscriptions`**: assinatura ativa do tenant, vínculo com o plano, datas do ciclo (`current_period_start`, `current_period_end`, `trial_ends_at`) e status (`TRIALING`, `ACTIVE`, `PAST_DUE`, `CANCELED`).
- **`usage_records`**: registro agregado de consumo por tenant, dimensão e período de faturamento, protegido por RLS (*Row Level Security*).

### 4. Integração assíncrona e provisionamento inicial

- Ao cadastrar uma oficina (via onboarding ou Google OAuth), o `IAM` publica o evento `TenantCreatedEvent`.
- O listener `TenantCreatedEventListener`, no módulo `Billing`, intercepta o evento e provisiona automaticamente uma assinatura no plano `TRIAL` (14 dias de teste com todos os módulos e limites seguros).

## Consequências

### Positivas

- **Independência total:** o Core desacopla os consumidores (IAM, CRM, Operations) do provedor de faturamento (Billing). Provedores de pagamento externos (Stripe, Asaas, MercadoPago) podem ser integrados internamente em `Billing` sem impacto em nenhum outro módulo.
- **Monetização e cotas em tempo real:** bloqueio transparente e descritivo (HTTP 402 `QuotaExceededException` e HTTP 403 `ModuleAccessDeniedException`) por meio do `GlobalExceptionHandler`.
- **Conformidade com a arquitetura:** a regra de dependência estrita é validada via ArchUnit no pipeline de CI/CD.

### Considerações e mitigações

- **Consistência das cotas:** a medição de cotas cumulativas baseadas em contagem de registros (ex.: `USERS`, `UNITS`) é sincronizada nas operações de criação, enquanto as cotas volumétricas (ex.: `AI_USAGE`, `WHATSAPP_MESSAGES`) são acumuladas em `usage_records` por período mensal.
