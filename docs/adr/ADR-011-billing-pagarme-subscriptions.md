# ADR-011: Billing Module, Pagar.me Subscriptions, and Idempotent Webhook Processing

## Status
Accepted

## Context
GoMech is a multi-tenant SaaS platform for automotive repair shops and fleet mechanics. The platform relies on subscription tiers (`TRIAL`, `STARTER`, `PRO`, `ENTERPRISE`) to control tenant module access (CRM, Operations, Inventory, Tools, Finance, AI Analytics) and quantitative quota dimensions (Users, Units, Monthly Work Orders, AI Usage).

To monetize the platform and provide seamless recurring billing for Brazilian workshops, we need a robust integration with **Pagar.me** (Stone Co.), supporting:
- PIX (Instant QR Code + Copy & Paste).
- Credit Card (Tokenization, recurring monthly charges, installments).
- Boleto Bancário (Barcode, PDF link, and dunning window).
- Secure, idempotent webhook ingestion to sync subscription statuses and invoice settlements without duplicate side-effects.
- Delinquency handling: Automatic suspension of tenant access and revocation of active IAM sessions when subscriptions become overdue (`PAST_DUE` / `CANCELED`), and immediate recovery upon payment confirmation.

## Architectural Decisions

### 1. Module Ownership & Boundary Isolation
- **Billing owns**: `Plan`, `PlanFeature`, `Subscription`, `Payment`/Invoice, `UsageRecord`, and `ProcessedWebhookEvent`.
- **Decoupled from IAM**: IAM has zero compile-time or runtime dependency on Billing. Billing implements the Core `EntitlementContract` consumed across the application. When a tenant is suspended due to delinquency, Billing publishes `TenantSuspendedEvent` / `TenantReactivatedEvent` and revokes user sessions via application services or event listeners.

### 2. Pagar.me Payment Gateway Abstraction
- A dedicated `PagarmeGatewayClient` abstracts all external communication with Pagar.me API v5.
- Supports configurable live and mock modes (for offline test suites and CI/CD).
- Normalizes gateway payment objects into platform-standard `Payment` records with explicit next-action metadata (PIX QR code, Boleto barcode/URL, Card authorization status).

### 3. Idempotent Webhook Processing
- Webhook endpoint (`/api/v1/billing/webhooks/pagarme`) verifies signature using HMAC SHA256 or header tokens against `pagarme.webhook-secret`.
- Every incoming webhook event ID is recorded in `processed_webhook_events` within a transaction before applying state transitions. Duplicate event deliveries are acknowledged with HTTP 200 and discarded immediately with zero side-effects.

### 4. Delinquency and Session Revocation Flow
- When an invoice payment fails (`invoice.payment_failed`) or a subscription enters `PAST_DUE`:
  1. `Subscription.status` transitions to `PAST_DUE`.
  2. Entitlements restrict access to billing self-service only.
  3. Active refresh tokens and sessions for all users of the tenant are invalidated in IAM.
- When payment is confirmed (`order.paid` / `invoice.paid`):
  1. `Subscription.status` transitions to `ACTIVE`.
  2. Entitlements are restored immediately.

### 5. Multi-Tenancy & Row Level Security
- All billing tables (`subscriptions`, `payments`, `usage_records`) enforce PostgreSQL Row Level Security (RLS) linked to `app.current_tenant`.
- Public plan catalogs (`billing_plans`, `billing_plan_features`) are global read models.

## Consequences
- Clean separation of billing concerns with zero leakage into operational or IAM domains.
- Auditable, resilient financial and subscription ledger immune to webhook replays and payment race conditions.
