# ADR-007: Core Entitlement Contract and Subscription-Backed Billing Evaluation

## Status
Accepted

## Context
No GoMech V2, o controle de acesso é composto por duas dimensões ortogonais e independentes:
1. **Autorização (IAM / RBAC / PBAC)**: Determina *quem* o ator é e *quais ações* ele pode executar com base em papéis atribuídos (ex: `Proprietário`, `Mecânico`, permissão `OPERATIONS_WORK_ORDER_WRITE`).
2. **Elegibilidade e Cotas (Billing / Entitlement)**: Determina se a organização (*Tenant*) contratou um plano que contempla o módulo desejado (ex: Financeiro, IA) e se ainda possui saldo de cota disponível para o recurso (ex: limite de usuários ativos, filiais cadastradas, consultas de IA, armazenamento em MB, mensagens WhatsApp).

Anteriormente, o sistema utilizava um placeholder estático (`StaticEntitlementService`) no Core que apenas repassava as permissões do token sem consultar planos, módulos ou cotas.

### Requisitos e Restrições Arquiteturais
- **Separação Estrita de Módulos (ADR-001 / ADR-002)**: O Core define a interface do contrato (`EntitlementService`, `EntitlementSnapshot`, `QuotaDimension`, `EntitlementDecision`, `QuotaDecision`, exceções de domínio). O módulo `Billing` fornece a implementação operacional (`BillingEntitlementService`).
- **Desacoplamento IAM ➔ Billing**: O módulo `IAM` **não pode** depender de `Billing`. O IAM emite eventos de domínio (`TenantCreatedEvent`) via `DomainEventBus` para notificar a criação de oficinas. A verificação de limites (ex: criação de filiais em `UnitService` ou criação de usuários em `UserService`) consome exclusivamente a interface do `Core`. Essa regra é garantida via teste de arquitetura ArchUnit (`iam_must_not_depend_on_billing`).
- **Avaliação Fail-Closed**: Se uma assinatura estiver inoperante (ex: `CANCELED`, `PAST_DUE`), ou se o módulo/cota não estiver ativo no plano, o acesso é negado (HTTP 402 Payment Required para cotas ou HTTP 403 Forbidden para módulos).

---

## Decisão

### 1. Definição do Contrato no Core (`com.gomech.api.core.entitlement`)
- **`EntitlementService`**:
  - `EntitlementSnapshot resolve(ActorContext actor)`: Intersecta as permissões atribuídas ao usuário com os módulos habilitados no plano da organização.
  - `EntitlementDecision checkModuleAccess(UUID tenantId, String moduleCode)`: Avalia se o módulo de negócio está habilitado no plano.
  - `QuotaDecision checkQuota(UUID tenantId, QuotaDimension dimension, long requestedIncrement)`: Verifica se `currentUsage + requestedIncrement <= limit` (ou se o limite é -1 / ilimitado).
  - `void recordUsage(UUID tenantId, QuotaDimension dimension, long amount)`: Incrementa o consumo medido da cota no ciclo atual.
  - `EntitlementSnapshot getTenantEntitlements(UUID tenantId)`: Obtém o catálogo de capacidades ativas do Tenant.

### 2. Dimensões Padronizadas de Cota (`QuotaDimension`)
- `USERS`: Quantidade máxima de usuários ativos na organização.
- `UNITS`: Quantidade máxima de filiais/unidades físicas cadastradas.
- `AI_USAGE`: Quantidade de requisições / tokens para diagnósticos e assistente IA.
- `STORAGE_MB`: Espaço de armazenamento de anexos, laudos e fotos (MB).
- `WHATSAPP_MESSAGES`: Disparos de mensagens e avisos pelo WhatsApp.
- `REPORTS`: Quantidade de relatórios e exportações no período.
- `MODULE_ACCESS`: Acesso booleano a módulos (`MODULE_CRM`, `MODULE_OPERATIONS`, `MODULE_INVENTORY`, `MODULE_FINANCE`, `MODULE_AI`).

### 3. Modelo de Dados de Billing
- **`billing_plans`**: Catálogo de planos (`TRIAL`, `STARTER`, `PRO`, `ENTERPRISE`), preços e ciclos de faturamento.
- **`billing_plan_features`**: Mapeamento granular de cotas (`limit_value`) e flags de módulo (`enabled`) por plano.
- **`subscriptions`**: Assinatura ativa do Tenant, vínculo com o plano, datas de ciclo (`current_period_start`, `current_period_end`, `trial_ends_at`) e status (`TRIALING`, `ACTIVE`, `PAST_DUE`, `CANCELED`).
- **`usage_records`**: Registro agregado de consumo por Tenant, dimensão e período de faturamento, protegido por RLS (*Row Level Security*).

### 4. Integração Assíncrona e Provisionamento Inicial
- Ao cadastrar uma oficina (via Onboarding ou Google OAuth), o `IAM` publica o evento `TenantCreatedEvent`.
- O listener `TenantCreatedEventListener` no módulo `Billing` intercepta o evento e provisiona automaticamente uma assinatura no plano `TRIAL` (14 dias de teste com todos os módulos e limites seguros).

---

## Consequências

### Positivas
- **Independência Total**: O Core desacopla consumidores (IAM, CRM, Operations) do provedor de faturamento (Billing). Provedores de pagamento externos (Stripe, Asaas, MercadoPago) podem ser integrados internamente em `Billing` sem impacto em nenhum outro módulo.
- **Monetização e Quotas em Tempo Real**: Bloqueio transparente e descritivo (HTTP 402 `QuotaExceededException` e HTTP 403 `ModuleAccessDeniedException`) através do `GlobalExceptionHandler`.
- **Conformidade com a Arquitetura**: Regra de dependência estrita validada via ArchUnit no pipeline de CI/CD.

### Considerações e Mitigações
- **Consistência de Quotas**: A medição de cotas cumulativas baseadas em contagem de registros (ex: `USERS`, `UNITS`) é sincronizada nas operações de criação, enquanto cotas volumétricas (ex: `AI_USAGE`, `WHATSAPP_MESSAGES`) acumulam em `usage_records` por período mensal.
