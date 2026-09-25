# ADR-011: Módulo de billing, assinaturas Pagar.me e processamento idempotente de webhooks

- **Status:** Aceita
- **Data:** 2026-08-20

## Contexto

O GoMech é uma plataforma SaaS multi-tenant para oficinas automotivas e mecânicos de frota. A plataforma se apoia em níveis de assinatura (`TRIAL`, `STARTER`, `PRO`, `ENTERPRISE`) para controlar o acesso dos tenants aos módulos (CRM, Operations, Inventory, Tools, Finance, AI Analytics) e às dimensões quantitativas de cota (usuários, unidades, ordens de serviço mensais, uso de IA).

Para monetizar a plataforma e oferecer cobrança recorrente sem atrito para as oficinas brasileiras, precisamos de uma integração robusta com a **Pagar.me** (Stone Co.), com suporte a:

- PIX (QR Code instantâneo + copia e cola).
- Cartão de crédito (tokenização, cobranças mensais recorrentes, parcelamento).
- Boleto bancário (código de barras, link do PDF e janela de cobrança/dunning).
- Ingestão de webhooks segura e idempotente, para sincronizar o status das assinaturas e a liquidação das faturas sem efeitos colaterais duplicados.
- Tratamento de inadimplência: suspensão automática do acesso do tenant e revogação das sessões IAM ativas quando as assinaturas entram em atraso (`PAST_DUE` / `CANCELED`), com recuperação imediata após a confirmação do pagamento.

## Decisão

### 1. Ownership do módulo e isolamento de fronteiras

- **Billing é dono de:** `Plan`, `PlanFeature`, `Subscription`, `Payment`/Invoice, `UsageRecord` e `ProcessedWebhookEvent`.
- **Desacoplado do IAM:** o IAM não tem nenhuma dependência de Billing, nem em tempo de compilação nem em runtime. O Billing implementa o `EntitlementContract` do Core, consumido em toda a aplicação. Quando um tenant é suspenso por inadimplência, o Billing publica `TenantSuspendedEvent` / `TenantReactivatedEvent` e revoga as sessões dos usuários por meio de application services ou event listeners.

### 2. Abstração do gateway de pagamento Pagar.me

- Um `PagarmeGatewayClient` dedicado abstrai toda a comunicação externa com a API v5 da Pagar.me.
- Suporta modos live e mock configuráveis (o mock atende às suítes de teste offline e ao CI/CD).
- Normaliza os objetos de pagamento do gateway em registros `Payment` padronizados da plataforma, com metadados explícitos da próxima ação (QR Code PIX, código de barras/URL do boleto, status de autorização do cartão).

### 3. Processamento idempotente de webhooks

- O endpoint de webhook (`/api/v1/billing/webhooks/pagarme`) verifica a assinatura criptográfica da requisição usando HMAC SHA256 ou tokens de header, comparando-os com `pagarme.webhook-secret`.
- O ID de todo evento de webhook recebido é gravado em `processed_webhook_events` dentro de uma transação, antes de aplicar as transições de estado. Entregas duplicadas do mesmo evento são confirmadas com HTTP 200 e descartadas imediatamente, sem nenhum efeito colateral.

### 4. Fluxo de inadimplência e revogação de sessões

- Quando o pagamento de uma fatura falha (`invoice.payment_failed`) ou uma assinatura entra em `PAST_DUE`:
  1. `Subscription.status` passa para `PAST_DUE`.
  2. Os entitlements restringem o acesso apenas ao autoatendimento de billing.
  3. Os refresh tokens e as sessões ativas de todos os usuários do tenant são invalidados no IAM.
- Quando o pagamento é confirmado (`order.paid` / `invoice.paid`):
  1. `Subscription.status` passa para `ACTIVE`.
  2. Os entitlements são restaurados imediatamente.

### 5. Multi-tenancy e Row Level Security

- Todas as tabelas de billing (`subscriptions`, `payments`, `usage_records`) aplicam Row Level Security (RLS) do PostgreSQL, vinculado a `app.current_tenant`.
- Os catálogos públicos de planos (`billing_plans`, `billing_plan_features`) são read models globais.

## Consequências

- Separação clara das responsabilidades de billing, sem vazamento para os domínios operacionais ou de IAM.
- Registro financeiro e de assinaturas auditável e resiliente, imune a replays de webhook e a condições de corrida em pagamentos.
