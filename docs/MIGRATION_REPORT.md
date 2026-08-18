# GoMech V2 — Discovery & Migration Report

**Phase 1 deliverable. No code was modified.**
Date: 2026-08-16 · Scope: `gomech` (V2), `gomech-backend`, `gomech-frontend`, `gomech-ai-service`

---

## 0. Executive summary

The workspace holds four repositories at very different maturity levels:

| Repo | Role | Size | State |
| --- | --- | --- | --- |
| `gomech` (V2) | Architectural source of truth | 36 Java files, 8 frontend source files, 21 design docs | Skeleton: IAM only, does not boot |
| `gomech-backend` | Legacy business API | 180 Java files, 22 controllers, 120 endpoints | Feature-complete, in production |
| `gomech-frontend` | Legacy SPA | 86 components across 18 modules, 29 routes | Feature-complete, in production |
| `gomech-ai-service` | AI service | 12 agents, 24 FastAPI endpoints | Feature-complete, in production |

Three findings dominate everything else in this report:

1. **V2 is ~5% built.** It has the IAM module (login, workshop registration, create user) and two frontend screens. Every business module — CRM, Operations, Inventory, Finance, Billing, AI — exists only as SQL tables in `V1__Initial_Schema.sql` and as prose in the docs. This is a *reimplementation*, not a port.
2. **The legacy system's tenant isolation is advisory, not enforced.** Legacy repositories expose both scoped (`findByIdAndOrganizationId`) and unscoped (`findById`) methods, and services call the unscoped ones in ~57 places. V2's `@TenantId` + `TenantContextHolder` approach is a genuine improvement and must not be diluted.
3. **The AI service is the largest security gap in the system.** It has *no authentication*, holds a direct connection to the business database, and runs a free-form text-to-SQL LangChain agent over every table — including `users` — with tenant scoping present only as a sentence in a prompt. It can also call back into the Java backend (`execute_action`) with no bearer token. Section 14 covers this.

Two of the four repos contain **two parallel architectures each**, left over from AI-generated PRs that were merged but never adopted. Section 12 lists them; they should be treated as noise, not as reference material.

---

## 1. Current architecture of each repository

### 1.1 `gomech` — V2 (source of truth)

```
gomech/
├── backend/    Spring Boot 3.3.0, Java 21, PostgreSQL 16, Flyway
│   └── com.gomech.api
│       ├── core/       config, exceptions, security, tenancy
│       └── modules/    iam/ (controllers, dto, models, repositories, services)
├── frontend/   React 19, Vite 5, TanStack Router + Query, Zustand, Tailwind v4
├── docs/       21 architecture documents (the actual asset here)
├── .skills/    5 enforcement rule files
└── .agents/    4 role definitions
```

- Package-by-feature, then layer-inside-module. Only `iam` exists.
- Multi-tenancy via Hibernate 6 `@TenantId` + a `ThreadLocal` context holder, populated from the JWT.
- Flyway with a single migration defining **22 tables across 6 modules** — the schema is far ahead of the code.
- `spring.jpa.hibernate.ddl-auto=validate` (correct).
- **The backend does not currently boot.** `startup.log` shows `SessionFactory configured for multi-tenancy, but no tenant identifier specified` — `DataLoader` queries tenant-scoped repositories during startup, before any request establishes a tenant. Already diagnosed in `DATABASE_READINESS_REPORT.md`; the `@ConditionalOnProperty` guard now added is a workaround, not a fix.

### 1.2 `gomech-backend` — legacy

Flat, layer-first Spring Boot application: `controller/ → service/ → repository/ → model/`, with one `dto/` package subdivided by domain. No module boundaries; `InventoryService` and `ServiceOrderService` reach into each other's repositories directly.

Tenancy is `Organization`-based: a `HandlerInterceptor` reads the authenticated `User`, puts their `Organization` into a `ThreadLocal`, and a JPA `EntityListener` stamps it onto entities at `@PrePersist` via reflection. Reads are only isolated where a developer remembered to call the `...AndOrganizationId` variant.

Note: the most recent commit (`2add319 feat: refactoring app`) **deleted 184 files**, removing Billing/Pagar.me, Payments, Quotes, CRM/WhatsApp, Notifications, Analytics, all schedulers, and a parallel `com.gomech.platform.*` clean-architecture skeleton. That functionality still exists at commit `c421a97` and its DB tables are still created by migrations V10–V13. **Anything removed there is inventoried in this report from `c421a97`, not from HEAD.**

### 1.3 `gomech-frontend` — legacy

React 19 + TanStack Router (code-based routes, not file-based) + TanStack Query + Zustand, Tailwind v4, Capacitor for mobile, PWA plugin, Vercel deploy.

Organized as `src/modules/<domain>/{routes,services,components,types,hooks}` — 18 modules, close to a feature-slice architecture already. Alongside it sits an unused FSD scaffold (`src/{entities,features,widgets,processes,pages,app/saas}`) with its own router, stores and one page; `main.tsx` wires up only the `modules/` tree.

### 1.4 `gomech-ai-service` — legacy

FastAPI single-file application (`main.py`, 1 150 lines) plus 12 LangChain agents, SQLAlchemy models mirroring the business schema, and Alembic with one migration. Deployed independently (Docker Hub → VPS over SSH), separate from the Java app. LLM provider is OpenAI (`gpt-4o-mini`, `gpt-4o` for vision, `whisper-1`, TTS).

---

## 2. V2 architecture and conventions (the rules to preserve)

Extracted from `docs/` and `.skills/`. These are the constraints all migration work must satisfy.

**Structural**
- Modular monolith. Modules: `iam`, `crm`, `operations`, `inventory`, `finance`, `billing`, plus `core` for cross-cutting concerns.
- A module never touches another module's tables or repositories. Cross-module communication goes through public services or Spring `ApplicationEvent`s. Stated example: `WorkOrderService` must not use `InventoryRepository`.
- Declared dependency direction: `core`/`iam` are the base; `operations` depends on `crm`, `inventory`, `finance`; `billing` depends only on `iam`; AI/Analytics is read-only across modules.

**API**
- REST, versioned at `/api/v1`, DTOs in and out, entities never exposed. Java `record` DTOs.
- Pagination mandatory on all list endpoints.
- Errors as RFC 7807 `ProblemDetail`. `404` not found, `422` validation, `403` denied.

**Persistence**
- PostgreSQL. UUID primary keys everywhere.
- Every business table: `id`, `created_at`, `updated_at`, `tenant_id`, indexed on `tenant_id` and `created_at`.
- Soft delete via `deleted_at` / `deleted_by` on critical entities; no physical deletes.
- Flyway only; `ddl-auto: validate`.

**Security**
- Stateless JWT: short-lived access token (15 min) carrying `user_id`, `tenant_id`, permissions; opaque refresh token (7 days) persisted in `user_sessions` for per-device revocation.
- BCrypt/Argon2 password hashing.
- RBAC + PBAC: granular permissions (`os:create`, `finance:delete`), grouped into roles, assigned per unit. `@PreAuthorize` on controllers; unit-scoped checks in services.
- Tenant isolation enforced by the backend at the ORM layer, with PostgreSQL RLS as the intended second line of defence.

**Frontend**
- Feature slices under `src/features/<module>/{api,components,hooks,stores,types}`, mirroring backend modules.
- TanStack Router file-based routing with `_authenticated` layout routes and `beforeLoad` permission guards.
- Server state in TanStack Query only; Zustand for ephemeral UI state only.
- React Hook Form + Zod, with Zod schemas mirroring backend DTOs.
- `shared/components` are presentational only — no API calls.
- Axios interceptors map `401 → logout`, `403 → denied notice`, `422 → field errors in RHF`.
- `<Can do="os:create">` wrapper for permission-gated UI.

**Design system** — tokens live in `frontend/src/index.css` as Tailwind v4 `@theme` variables. Manrope for headings, Inter for body. No hardcoded colors or spacing. *(A conflict exists here — see §12.)*

---

## 3. Feature inventory

Legend for **In V2**: ✅ implemented · 📄 specified in docs/schema only · ❌ absent.

### 3.1 IAM & platform

| Feature | Source | In V2 | Target module | Migrate? | Notes |
| --- | --- | --- | --- | --- | --- |
| Login (email + password) | BE, FE | ✅ | iam | Refine | V2 issues access + refresh; legacy adds MFA |
| MFA / TOTP | BE (`MfaService`), FE | ❌ | iam | Decide | Legacy: encrypted secret, code at login. Optional per user |
| Refresh token rotation | BE (`RefreshTokenService`) | ⚠️ partial | iam | Yes | V2 persists a refresh token but has **no `/refresh` endpoint** |
| Logout / session revocation | BE | ❌ | iam | Yes | V2 has `user_sessions` table, no endpoint |
| Password reset by email | BE (`EmailService`) | ❌ | iam | Yes | Listed in PROJECT_CONTEXT as required |
| Register user (invite) | BE, FE | ✅ | iam | Refine | V2 `POST /users` **has no authorization annotation** |
| Register organization (self-serve onboarding) | BE, FE | ✅ | iam | Refine | V2 fabricates a fake CNPJ — placeholder |
| User CRUD + role assignment | BE, FE | ⚠️ create only | iam | Yes | No list/update/delete/deactivate in V2 |
| Organization CRUD (admin) | BE, FE | ❌ | iam | Yes | Legacy `/api/organizations`, ADMIN-only |
| Units / multi-branch | — | 📄 | iam | New build | **No legacy equivalent.** V2-only concept |
| Roles & permissions (PBAC) | — | 📄 | iam | New build | Legacy has a 3-value enum only |
| Tenant context enforcement | BE (weak) | ✅ | core | Keep V2 | See §12.1 |
| Audit log | BE (`AuditService`, `/audit`) | 📄 | core | Yes | `audit_logs` table exists in V2; no writer |
| LGPD status / export / deletion request | BE (`LgpdService`), FE | ❌ | core or iam | Yes | Legal requirement (BR) |
| Tutorial progress / onboarding tour | BE, FE | ❌ | — | Decide | Low value; candidate for drop |
| Dashboard layout persistence | BE, FE (`react-grid-layout`) | ❌ | — | Decide | Customizable widget grid per user |

### 3.2 CRM

| Feature | Source | In V2 | Target module | Migrate? | Notes |
| --- | --- | --- | --- | --- | --- |
| Client CRUD | BE, FE | 📄 | crm | Yes | `customers` table exists |
| Client CSV/XLSX import + template | BE, FE | 📄 | crm | Yes | Uses commons-csv + poi-ooxml |
| Client export | BE, FE | ❌ | crm | Yes | |
| Vehicle CRUD | BE, FE | 📄 | crm | Yes | `vehicles` table exists |
| Vehicle import/export/template | BE, FE | ❌ | crm | Yes | |
| Vehicle ↔ client linking | BE, FE | 📄 | crm | Yes | FK exists |
| Vehicle service history (+ export) | BE, FE | ❌ | crm/operations | Yes | Cross-module read |
| Client feedback & satisfaction metrics | BE (`c421a97`), FE | ❌ | crm | Decide | Table `client_feedbacks` (V3 migration) |
| WhatsApp inbound/outbound messaging | BE (`c421a97`) | ❌ | — | Decide | Was scaffolded, `whatsapp.enabled=false` |

### 3.3 Operations

| Feature | Source | In V2 | Target module | Migrate? | Notes |
| --- | --- | --- | --- | --- | --- |
| Service order CRUD | BE, FE | 📄 | operations | Yes | V2 calls it `work_orders` |
| Auto-generated order number | BE (`@PrePersist`) | ❌ | operations | Yes | Uniqueness must become per-tenant |
| Status lifecycle (7 states) | BE, FE | 📄 | operations | Yes | V2 schema default `PLANNED`; legacy `PENDING` |
| SO items (services + parts) | BE, FE | ❌ | operations | Yes | **No `work_order_items` table in V2 schema — gap** |
| Item apply / unapply | BE | ❌ | operations | Yes | |
| Item consume / return stock | BE, FE | ❌ | operations→inventory | Yes | Must become an event, not a direct call |
| Reports: overdue / waiting parts / waiting approval | BE, FE | ❌ | operations | Yes | |
| Quotes CRUD | BE (`c421a97`), FE | 📄 | operations | Yes | `quotes` table in V2, no `quote_items` |
| Quote → SO conversion | BE (`c421a97`), FE | 📄 | operations | Yes | Roadmap phase 4→5 |
| Quote internal approval + per-user permissions | BE (`c421a97`), FE | ❌ | operations | Rework | Legacy had a bespoke `user_quote_permissions` table — replace with PBAC |
| Public quote approve/reject (tokenized) | BE (`c421a97`), FE | ❌ | operations | Yes | Customer-facing, unauthenticated |
| Public SO tracking by token | BE, FE | ❌ | operations | Yes | `service_order_tracking` (V13) |
| Scheduling / calendar / bays | — | ❌ | operations | New build | In PROJECT_CONTEXT + design system, **no legacy code** |

### 3.4 Inventory

| Feature | Source | In V2 | Target module | Migrate? | Notes |
| --- | --- | --- | --- | --- | --- |
| Part catalogue CRUD + import | BE, FE | 📄 | inventory | Yes | V2 merges Part + InventoryItem into `products` |
| Inventory item CRUD + import | BE, FE | 📄 | inventory | Yes | See §12.4 |
| Movements: entry / reservation / consumption / cancellation / return | BE, FE | ⚠️ | inventory | Yes | V2 has only `IN`/`OUT` — reservations unmodelled |
| Availability by part / vehicle / client | BE | ❌ | inventory | Decide | |
| Consumption history by vehicle / client | BE | ❌ | inventory | Decide | Feeds the AI recommendation engine |
| Critical parts report | BE | ❌ | inventory | Yes | |
| Minimum-stock alerts | BE (`c421a97`) | ⚠️ | inventory | Yes | `min_stock` column exists, no alerting |
| Suppliers | — | 📄 | inventory | New build | `suppliers` table in V2; **no legacy equivalent** |
| AI stock recommendations | BE + AI | ❌ | inventory + AI | Decide | Two nightly sync jobs |

### 3.5 Finance & billing

| Feature | Source | In V2 | Target module | Migrate? | Notes |
| --- | --- | --- | --- | --- | --- |
| Financial accounts | BE, FE | ❌ | finance | Yes | **No `financial_accounts` table in V2** |
| Financial categories | BE, FE | ❌ | finance | Yes | **No table in V2** |
| Transactions (income/expense) + pay/cancel | BE, FE | 📄 | finance | Yes | `financial_transactions` exists |
| Cash flow | BE, FE | 📄 | finance | Yes | Derived |
| Financial dashboard | BE, FE | ❌ | finance | Yes | |
| Recurring expenses | BE (model+repo) | ❌ | finance | Decide | Table exists (V11), no endpoint |
| Financial audit log | BE | ❌ | finance/core | Merge | Legacy has a *separate* audit table — unify with `audit_logs` |
| Auto AR on SO completion | — | ❌ | operations→finance | New build | Roadmap phase 7; `origin_type`/`origin_id` columns ready |
| DRE (simplified P&L) | — | ❌ | finance | New build | In PROJECT_CONTEXT, no legacy code |
| SaaS plans & subscription | BE (`c421a97`), FE | 📄 | billing | Yes | `subscriptions`, `payments` tables exist |
| Pagar.me checkout (card + PIX) | BE (`c421a97`), FE | ❌ | billing | Yes | Full transparent checkout was built |
| Pagar.me webhooks | BE (`c421a97`) | ❌ | billing | Yes | Idempotency table `payments_webhook_events` |
| Entitlements / plan gating | BE (`@RequiresPlan`, aspect) | ❌ | billing | Rework | Must stay decoupled from authorization |
| Subscription expiry / reconciliation jobs | BE (`c421a97`) | ❌ | billing | Yes | Hourly + nightly |

### 3.6 Analytics, AI, ops

| Feature | Source | In V2 | Target module | Migrate? | Notes |
| --- | --- | --- | --- | --- | --- |
| Dashboard KPIs & charts | FE | ❌ | dashboard | Yes | Roadmap phase 9 |
| Management reports (profitability, bottlenecks, benchmark, trends, health score) | BE + AI | ❌ | analytics | Decide | Duplicated Java ↔ Python |
| AI chat assistant | BE, FE, AI | ❌ | ai | Yes | See §6 |
| Voice (transcribe / synthesize / command) | BE, FE, AI | ❌ | ai | Decide | |
| Vision (damage, part suggestion, OCR) | AI only | ❌ | ai | Decide | **No backend or frontend consumer today** |
| Predictive & simulation agents | AI only | ❌ | ai | Decide | Reachable only by calling FastAPI directly |
| Email notifications | BE | ❌ | core | Yes | Welcome + password reset |
| SO lifecycle notifications | BE (`c421a97`) | ❌ | core | Yes | Email + WhatsApp on create/status/complete |
| Nightly DB backup job | BE (`c421a97`) | ❌ | infra | Replace | Should be Cloud SQL automated backups, not app code |

---

## 4. Backend endpoint inventory

**Legacy HEAD: 120 endpoints across 22 controllers. Pre-refactor (`c421a97`): 155.** No version prefix; base paths are inconsistent (`/clients` vs `/api/organizations`).

| Base path | Endpoints | AuthZ | V2 target |
| --- | --- | --- | --- |
| `/auth` | `POST /login`, `/register`, `/register-organization`, `/refresh` | public | `iam` → `/api/v1/auth/*` |
| `/users` | GET list, GET `{id}`, POST, PUT, DELETE, GET+PUT `{id}/dashboard-layout` | `ADMIN` on write | `iam` |
| `/users/me/tutorials` | GET, POST | authenticated | drop or `iam` |
| `/api/organizations` | GET, GET `{id}`, GET `slug/{slug}`, POST, PUT, DELETE, PATCH `toggle-active` | `ADMIN` | `iam` (tenants) |
| `/clients` | POST, GET, GET `/paginated`, GET `{id}`, PUT, DELETE, POST `/upload`, GET `/export`, GET `/template` | authenticated | `crm` |
| `/vehicles` | POST, GET, `/paginated`, `{id}`, PUT, DELETE, `/upload`, `/export`, `/template`, `{id}/service-history`, `{id}/service-history/export` | authenticated | `crm` |
| `/service-orders` | 20 endpoints: CRUD, `/paginated`, `order-number/{n}`, `status/{s}`, `{id}/status`, 3 reports, 8 item operations | authenticated | `operations` |
| `/quotes` *(c421a97)* | CRUD, `{id}/send`, `{id}/convert-to-os`, `/pending-approval`, `{id}/approve-internal`, `{id}/reject-internal`, `/permissions/*` | mixed | `operations` |
| `/public/quotes/{id}` *(c421a97)* | GET, POST `/approve`, POST `/reject` | public+token | `operations` |
| `/public/tracking/{token}` | GET, GET `/status` | public+token | `operations` |
| `/parts` | POST, GET, GET `{id}`, PUT, DELETE, POST `/upload`, GET `/template` | `ADMIN` on write | `inventory` |
| `/inventory` | 19 endpoints: items CRUD, 5 movement types, movements list, 2 recommendation, critical-parts report, 3 availability, 2 history, upload, template | `ADMIN` on write | `inventory` |
| `/financial` | `/transactions` GET+POST, `{id}/pay`, `{id}/cancel`, `/cash-flow`, `/dashboard` | authenticated | `finance` |
| `/financial/accounts` | GET, GET `{id}`, POST | authenticated | `finance` |
| `/financial/categories` | GET | authenticated | `finance` |
| `/billing` *(c421a97)* | `POST /subscribe`, `GET /subscription`, `POST /subscription/cancel`, `GET /plans` | authenticated | `billing` |
| `/api/payments` *(c421a97)* | `POST /checkout`, `GET /orders/{id}` | authenticated | `billing` |
| `/api/webhooks/pagarme`, `/webhooks/pagarme` | POST | public | `billing` (one path only) |
| `/webhooks/whatsapp` *(c421a97)* | POST, GET (verification) | public | decide |
| `/management` | `/profitability`, `/bottlenecks`, `/benchmark`, `/reports/{type}`, `/dashboard`, `/trends`, `/health-score` | authenticated | `analytics` |
| `/analytics` *(c421a97)* | POST, GET `/insights` | `ADMIN` | `analytics` |
| `/crm` *(c421a97)* | `messages/send`, `messages/receive`, `messages/client/{id}`, `feedbacks` POST+GET, `metrics/satisfaction` | mixed | decide |
| `/audit` | `POST /event`, `GET /events` | `ADMIN` | `core` |
| `/lgpd` | `/status`, `/request-deletion`, `/request-export`, `/requests` | authenticated | `core` |
| `/ai/chat` | POST, `GET /status`, `GET /insights` | authenticated | `ai` |
| `/ai/voice` | `/transcribe`, `/synthesize`, `/command` | authenticated | `ai` |

**V2 today: 3 endpoints.** `POST /api/v1/auth/login`, `POST /api/v1/auth/register`, `POST /api/v1/users`.

---

## 5. Frontend route & feature inventory

Legacy: **29 routes, 18 modules, 86 components.**

| Route | Module | Access | Purpose | V2 |
| --- | --- | --- | --- | --- |
| `/login` | auth | public | Login | ✅ |
| `/register` | auth | public | Workshop signup | ✅ |
| `/privacy-policy`, `/terms-of-service` | auth | public | Legal | ❌ |
| `/` | dashboard | private | Customizable widget dashboard (KPI/chart/list widgets, drag-and-drop) | ❌ (redirects to `/login`) |
| `/clients`, `/clients/$id` | client | private | List, create, edit, import modal, detail | ❌ |
| `/vehicles`, `/vehicles/$id` | vehicle | private | List, add, edit, import, link-to-client, detail + service history | ❌ |
| `/service-orders`, `/service-orders/$id` | serviceOrder | private | List, create, edit, reports, item manager | ❌ |
| `/quotes`, `/quotes/new`, `/quotes/$id`, `/quotes/$id/edit` | quote | private | Quote lifecycle | ❌ |
| `/admin/pending-quotes`, `/admin/quote-permissions` | quote | ADMIN | Approval queue, per-user quote permissions | ❌ |
| `/public/quotes/$id` | quote | public | Customer approve/reject | ❌ |
| `/public/tracking/$token` | tracking | public | Customer SO tracking | ❌ |
| `/parts` | part | private | Catalogue, import | ❌ |
| `/inventory` | inventory | private | Stock dashboard, item modal | ❌ |
| `/financial` | financial | private | Dashboard, transactions, cash-flow chart | ❌ |
| `/analytics` | analytics | ADMIN | AI analytics dashboard | ❌ |
| `/admin` | admin | ADMIN | Users, orgs, audit panel, system settings, analytics panel | ❌ |
| `/organizations` | organization | ADMIN | Tenant management | ❌ |
| `/payments/checkout` | payments | private | Pagar.me card + PIX checkout, polling, order summary | ❌ |
| `/docs` | docs | private | In-app documentation | ❌ |
| *(no route)* | billing | — | Plan cards, subscription management — components exist but are unrouted | ❌ |
| *(overlay)* | ai | private | ChatBot modal, voice button, AI charts, guided tour | ❌ |
| *(overlay)* | tutorial | private | Per-page tutorials | ❌ |

**V2 today: 3 routes** — `/` (redirect), `/login`, `/register`. Two UI primitives (`Button`, `Input`), one layout (`PublicLayout`, currently unused by the login route).

Cross-cutting legacy patterns worth carrying over as *behaviour* (not as code): axios refresh-token retry queue with single-flight, `X-Organization-ID` header (**drop this — see §12.1**), role guards, toast notifications, offline query persistence, PWA + Capacitor packaging.

---

## 6. AI capabilities

24 FastAPI endpoints, 12 agents. Router (`router_agent.py`) classifies each chat message into one of: `sql`, `grafico`, `web`, `audit`, `recommendation`, `action`, `chat`.

| Agent | Capability | Provider | Consumed by |
| --- | --- | --- | --- |
| `sql_agent` | Natural-language → SQL over the business DB; `get_operational_stats()` | gpt-4o-mini + LangChain `create_sql_agent` | `/chat` |
| `chat_agent` | Conversational assistant with UI knowledge base, glossary, step-by-step guides; LangGraph `MessagesState` | gpt-4o-mini | `/chat` |
| `chart_agent` | Plans a chart, generates + sanitizes SQL, renders matplotlib → base64 PNG | gpt-4o-mini | `/chat` |
| `web_agent` | Keyword extraction (RAKE) + YouTube search for repair videos | YouTube Data API | `/chat` |
| `audit_agent` | Answers audit/LGPD questions by calling back into the Java `/audit` and `/lgpd` endpoints | gpt-4o-mini | `/chat` |
| `action_agent` | Parses intent, extracts params, asks for confirmation, then **executes writes against the Java API** | gpt-4o-mini | `/chat`, `/action/confirm` |
| `recommendation_agent` | Profitability, bottlenecks, internal benchmark, management reports (JSON/CSV) | gpt-4o-mini | `/management/*` |
| `voice_agent` | Whisper transcription, Google STT fallback, OpenAI TTS, full voice command loop | whisper-1, TTS, Google Cloud | `/voice/*` |
| `vision_agent` | Part image analysis, damage level, replacement suggestion, part-code OCR | gpt-4o vision | `/vision/*` — **unused** |
| `predictive_agent` | Order-delay prediction, bottleneck forecast, proactive alerts | heuristics | `/predictive/*` — **unused** |
| `simulation_agent` | Price change, capacity change, marketing, what-if, scenario comparison | gpt-4o-mini | `/simulation/*` — **unused** |
| `crm_agent` | Sentiment, urgency, message classification, auto-reply, review reminders, surveys | gpt-4o-mini | removed CRM controller |

**Integration contract today (Java → Python):** `PythonAiService` uses a WebClient against `${ai.service.url}` (default `http://localhost:5000`) calling `/chat`, `/status`, `/`, `/insights`, `/inventory/recommendations`, `/inventory/features`, `/pipelines`, `/voice/{transcribe,synthesize,command}`. Timeouts of 3 minutes; failures wrapped in a bare `RuntimeException`; no retry, no circuit breaker, no auth header, and Python DTOs (`reply`, `thread_id`, `image_base64`) leak into the Java layer.

**Integration contract today (Python → Java):** `execute_action()` POSTs/PUTs/DELETEs to `${BACKEND_URL}` with **no Authorization header**. Since legacy `SecurityFilter` requires a token for these paths, AI writes almost certainly fail in production — worth confirming with the user.

---

## 7. Database / domain model inventory

### 7.1 Legacy schema (21 tables at HEAD via Flyway V1–V13)

`organizations`, `users`, `refresh_tokens`, `conversations` (+`messages`), `tutorial_progress`, `completed_tutorials`, `dashboard_layouts`, `clients`, `vehicles`, `parts`, `inventory_items`, `service_orders`, `service_items`, `inventory_movements`, `audit_events`, `client_feedbacks`, `billing_customers`, `billing_plans`, `subscriptions`, `invoices`, `financial_accounts`, `financial_categories`, `financial_transactions`, `recurring_expenses`, `financial_audit_logs`, `user_quote_permissions`, `quotes`, `quote_items`, `quote_history`, `quote_templates`, `service_order_tracking`, `notification_logs`.

Characteristics: `BIGSERIAL` identity PKs, `organization_id` FK on business tables, no soft delete, `users.email` globally unique.

### 7.2 V2 schema (22 tables, `V1__Initial_Schema.sql`)

| Module | Tables |
| --- | --- |
| IAM | `tenants`, `units`, `users`, `roles`, `permissions`, `role_permissions`, `user_roles`, `user_sessions` |
| CRM | `customers`, `vehicles` |
| Inventory | `suppliers`, `products`, `inventory_movements` |
| Operations | `quotes`, `work_orders` |
| Billing/Finance | `subscriptions`, `payments`, `financial_transactions` |
| Audit | `audit_logs` |

Characteristics: UUID PKs, `tenant_id` on every business table, partial unique indexes that respect soft delete (`WHERE deleted_at IS NULL`), `unit_id` for multi-branch, append-only `inventory_movements`, JSONB before/after states in `audit_logs`.

### 7.3 Gaps in the V2 schema

Tables the roadmap needs but the migration does not define:

- `quote_items` and `work_order_items` — **both quotes and work orders are headers with a `total_amount` and no line items.** This blocks Operations entirely.
- `financial_accounts`, `financial_categories` — Finance transactions reference a free-text `category` string.
- `billing_plans` — `subscriptions.plan_name` is a string; no plan catalogue, no entitlement limits.
- Scheduling/appointments — required by PROJECT_CONTEXT and the design system's Service Bay Timeline.
- `deleted_by` — the skills file mandates it; the schema only has `deleted_at`, and only on some tables (`quotes`, `work_orders`, `financial_transactions`, `user_roles`, `user_sessions` have none).
- No RLS policies. `DATABASE_DESIGN.md` and `ARCHITECTURE.md` both promise `CREATE POLICY`; the migration contains zero.
- `roles.tenant_id` is nullable for "system roles", but the JPA entity annotates it `@TenantId` — Hibernate cannot resolve a null tenant discriminator, so global roles are unreachable in code.

### 7.4 Entity mapping legacy → V2

| Legacy | V2 | Change |
| --- | --- | --- |
| `Organization` (Long) | `Tenant` (UUID) | Rename + retype; adds `cnpj` as required unique |
| — | `Unit` | New concept |
| `User.role` (enum ADMIN/USER/TECHNICIAN) | `Role` + `Permission` + `UserRole(unit)` | Enum → full RBAC/PBAC |
| `RefreshToken` (encrypted + hashed) | `UserSession` | V2 stores the refresh token **in plaintext** — regression, see §14 |
| `Client` | `Customer` | Rename |
| `Vehicle` | `Vehicle` | Adds `vin`, `current_mileage` |
| `ServiceOrder` | `WorkOrder` | Rename; loses `laborCost`/`partsCost`/`discount`/`diagnosis`/`problemDescription` split |
| `ServiceOrderItem` | *missing* | Must be created |
| `Part` + `InventoryItem` | `Product` | Two entities collapsed into one |
| `InventoryMovement` (7 types) | `inventory_movements` (IN/OUT + reason) | Reservation semantics lost |
| `FinancialTransaction` | `financial_transactions` | Loses account + category FKs |
| `AuditEvent` + `FinancialAuditLog` | `audit_logs` | Two tables unified |
| `Subscription`/`Invoice`/`BillingPlan` | `subscriptions` + `payments` | Simplified |
| `Quote`/`QuoteItem`/`QuoteHistory`/`QuoteTemplate` | `quotes` | Heavily simplified |
| `Conversation`/`Message` | *none* | AI chat history has no home in V2 |

---

## 8. Authentication and authorization behaviour

### 8.1 Legacy

- **AuthN:** JWT (auth0 `java-jwt`) with the user's email as subject. `SecurityFilter` validates the token and loads the `User` from the DB on **every request** (`findWithOrganizationByEmail`). Optional TOTP MFA at login, secret encrypted at rest via `EncryptionService`. Refresh tokens stored encrypted + hashed, revocable, rotated on use.
- **AuthZ:** three-value `Role` enum → Spring authorities, `ADMIN` inheriting `ROLE_USER`. Enforced by URL matchers in `SecurityConfig` plus `@PreAuthorize` on ~20 methods. Plan gating via `@RequiresPlan` + an aspect (removed at HEAD).
- **Tenancy:** `OrganizationInterceptor` puts the user's `Organization` into a `ThreadLocal`; `OrganizationEntityListener` stamps it on write via reflection. **Reads are not automatically scoped.**

### 8.2 V2

- **AuthN:** JWT (jjwt) with `user_id` as subject and a `tenantId` claim. `JwtAuthenticationFilter` validates signature and expiry with no DB round-trip. Access 15 min / refresh 7 days. BCrypt.
- **AuthZ:** `@EnableMethodSecurity` is on, but the filter builds the authentication with an **empty authority list**, and no controller carries `@PreAuthorize`. Authorization is effectively "any valid token, any endpoint".
- **Tenancy:** `TenantContextHolder` (ThreadLocal) + Hibernate `@TenantId` on `User`, `Unit`, `Role`, `UserRole` — the ORM injects `tenant_id` into both reads and writes. This is the right model.

### 8.3 Behavioural deltas to resolve

| Concern | Legacy | V2 | Action |
| --- | --- | --- | --- |
| Token subject | email | user UUID | Keep V2 |
| Permissions in token | none | designed, not implemented | Implement |
| MFA | yes | no | Decide |
| Refresh endpoint | yes | **missing** | Implement |
| Logout | via refresh revocation | **missing** | Implement |
| Refresh token at rest | encrypted + hashed | plaintext | Fix before launch |
| CORS | explicit allowlist | `.cors(disable)` | Implement |
| Brute-force lockout | none | promised in docs | Implement |
| Email uniqueness | global | per tenant | Keep V2 (blocks the same person working at two workshops otherwise — confirm intent) |

---

## 9. External integrations

| Integration | Where | Purpose | Config | V2 |
| --- | --- | --- | --- | --- |
| OpenAI | AI service | Chat, SQL, charts, vision, Whisper, TTS | `OPENAI_API_KEY` | ❌ |
| Google Cloud Speech | AI service | STT fallback | `GOOGLE_CLOUD_API_KEY` | ❌ |
| YouTube Data API | AI service | Repair video search | `YOUTUBE_API_KEY` | ❌ |
| LangSmith | AI service | LLM tracing | `LANGSMITH_API_KEY` | ❌ |
| Pagar.me | Backend (`c421a97`) + frontend | Subscriptions, card + PIX checkout, webhooks | `PagarmeProperties`, `VITE_PAGARME_PUBLIC_KEY` | ❌ |
| SMTP | Backend | Welcome + password reset emails | `MAIL_*` | ❌ |
| WhatsApp Cloud API | Backend (`c421a97`) | Client messaging | `whatsapp.api.*`, disabled | ❌ |
| Vercel Analytics / Speed Insights | Frontend | Web vitals | — | ❌ |
| Docker Hub + VPS over SSH | CI/CD, all repos | Deploy | GH secrets | ❌ (V2 targets GCP Cloud Run + Cloud SQL) |

**Environment variables — legacy backend:** `DB_URL`, `DB_USERNAME`, `DB_PASSWORD`, `JWT_SECRET`, `ENCRYPTION_KEY`, `FRONTEND_URL`, `MAIL_ENABLED`, `MAIL_HOST`, `MAIL_PORT`, `MAIL_USERNAME`, `MAIL_PASSWORD`, `MAIL_FROM_EMAIL`, `MAIL_FROM_NAME`, plus `ai.service.url`.
**AI service:** `DATABASE_URL`, `OPENAI_API_KEY`, `BACKEND_URL`, `CORS_ORIGINS`, `YOUTUBE_API_KEY`, `GOOGLE_CLOUD_API_KEY`, `LANGSMITH_*`.
**Frontend:** `VITE_API_BASE_URL`, `VITE_API_URL`, `VITE_APP_ENV`, `VITE_TENANT_RESOLUTION_MODE`, `VITE_AUTH_REFRESH_MARGIN_SECONDS`, `VITE_PAGARME_PUBLIC_KEY`.
**V2 backend:** `SPRING_PROFILES_ACTIVE`, `DB_HOST`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `JWT_SECRET`, `GCP_PROJECT_ID`, `GCP_REGION`, `CLOUD_SQL_INSTANCE`, `gomech.data-loader.enabled`.

**Scheduled jobs (all legacy, all removed at HEAD):** nightly DB backup (03:00), subscription expiry check (hourly), subscription reconciliation (02:00), vehicle consumption sync to AI (02:15), SO consumption sync to AI (02:45).

---

## 10. Already implemented in V2

**Backend** — `core/security` (JWT util, filter, `SecurityConfig`, BCrypt), `core/tenancy` (context holder, servlet filter, Hibernate resolver), `core/exceptions` (RFC 7807 handler for validation + `IllegalArgumentException`), `core/config/DataLoader` (seed, guarded off). IAM: `Tenant`, `Unit`, `User`, `Role`, `Permission`, `UserRole`, `UserSession` entities; 5 repositories; `AuthService.login`, `OnboardingService.register`, `UserService.createUser`; 3 endpoints. Flyway migration with the full 22-table schema. Docker Compose + multi-stage Dockerfile. Four Spring profiles including a Cloud SQL socket-factory production profile.

**Frontend** — Vite + React 19 + TanStack Router (file-based) + Query, Zustand auth store with `persist`, axios client, `LoginForm` and `RegisterForm` (RHF + Zod + `useMutation`), `Button` and `Input`, `PublicLayout`, design tokens in `index.css`.

**Docs** — 21 documents covering system architecture, backend, frontend, database design, domain model, API spec, UX flows, design system, component library, UI conventions, infrastructure, DevOps, CI/CD, roadmap, and the database readiness report. This is the most complete part of V2 and should drive the work.

---

## 11. Missing from V2

Ordered by blocking severity.

**Blocks everything**
1. Application does not boot (`DataLoader` / tenant resolver conflict).
2. No authorization: empty authorities, no `@PreAuthorize`, no permission seeding, no `role_permissions` data.
3. No `/auth/refresh`, no `/auth/logout` — sessions are unusable past 15 minutes.
4. Login very likely cannot resolve a user: `UserRepository.findByEmail` runs against a `@TenantId` entity while no tenant is in context, so Hibernate filters by the fallback tenant `00000000-...-0000`. Tenant resolution must precede user lookup (lookup by email across tenants, or tenant-qualified login).
5. No CORS configuration — the frontend cannot call the API cross-origin.

**Blocks the MVP**
6. Entire CRM, Operations, Inventory, Finance, Billing, Dashboard modules (backend + frontend).
7. `quote_items` / `work_order_items` tables and models.
8. Authenticated layout, sidebar, top bar, protected routes, `<Can>` component, axios interceptors.
9. Pagination, filtering and sorting conventions — no `PageResponse` equivalent exists.
10. No tests anywhere except a stub `contextLoads`.

**Required before production**
11. Audit log writer, soft-delete enforcement (`@SQLRestriction` is commented out on `User`), RLS policies, refresh-token hashing, brute-force protection, structured JSON logging + MDC correlation ids, `deleted_by`, LGPD endpoints, email sending, CI/CD pipelines.

---

## 12. Conflicts between legacy and V2

### 12.1 Tenant resolution: header-trusted vs token-derived
Legacy `util/OrganizationContext` reads `X-Organization-ID` from the request **first**, falling back to the JWT then the user. The legacy frontend sets that header from `localStorage`. Any authenticated user can therefore read another tenant's data through the endpoints that use it (`TutorialController` today; the utility was clearly intended to spread further). V2 derives the tenant from the signed JWT only, plus `@TenantId` at the ORM layer.
**Resolution: V2 wins.** Never migrate the header path. Note that V2's own `TenantFilter` also accepts an `X-Tenant-ID` header "for testing" — that must be removed or restricted to non-production profiles.

### 12.2 Read scoping: opt-in vs automatic
Legacy repositories expose both `findById` and `findByIdAndOrganizationId`; services call the unscoped variant in roughly 57 places, and `InventoryService` calls `findAll()` outright. V2's `@TenantId` makes scoping automatic and non-bypassable.
**Resolution: V2 wins.** During migration, never carry over an unscoped finder — even where the legacy method exists.

### 12.3 Authorization model: role enum vs RBAC/PBAC
Legacy: 3-value enum, hardcoded URL matchers, plus a bespoke `user_quote_permissions` table that exists purely because the enum was too coarse. V2: permissions → roles → per-unit assignment.
**Resolution: V2 wins.** The quote-permission table is evidence for the V2 model, and should be reimplemented as ordinary permissions (`quote:approve`, `quote:create`), not as its own table.

### 12.4 Part vs InventoryItem
Legacy separates `Part` (catalogue) from `InventoryItem` (stock at a location). V2 collapses both into `products` with `unit_id` and `current_stock_calculated`.
**Unresolved.** V2's model cannot represent the same part stocked in two units, and `current_stock_calculated` denormalizes a value that the append-only `inventory_movements` table already derives. Needs a decision — see §15 Q4.

### 12.5 Design system: two conflicting palettes
`docs/ui/DESIGN_SYSTEM.md` and `frontend/src/index.css` define primary `#2563EB` (blue) on `#F9FAFB`. `.skills/ui-guidelines.md` defines primary `#FF6500` (orange) on `#F7F8FA`. The implemented `LoginForm` uses neither consistently — it hardcodes `#FFF8F6`, `#FF6500`, `#00AD4E`, `#E3BFB1`, violating the "no hardcoded colors" rule in the same skills file.
**Unresolved and urgent** — every screen built from now on inherits this. See §15 Q1.

### 12.6 Parallel architectures left in the legacy repos
- `gomech-backend` at `c421a97` contained `com.gomech.platform.*` — a full hexagonal skeleton (domain/application/infrastructure/interfaces, `TenantResolutionFilter`, use cases) duplicating auth, users, tenants and service orders, running alongside the real code. Deleted at HEAD.
- `gomech-frontend` contains `src/{entities,features,widgets,processes,pages,app/saas}` — an FSD scaffold with its own router, auth store and tenant store, referenced by nothing in `main.tsx`.
**Resolution:** treat both as dead weight. They are AI-generated scaffolds, not working reference implementations. Read `src/modules/*` and `com.gomech.{controller,service,model}` for behaviour.

### 12.7 Identifier types
Legacy `BIGSERIAL`/`Long` throughout, exposed in URLs (`/clients/42`). V2 UUID.
**Resolution: V2 wins.** Consequence: any legacy data migration needs an ID remapping table, and the AI service's SQLAlchemy models (all `Integer` PKs) break entirely.

### 12.8 Naming
`Organization`→`Tenant`, `Client`→`Customer`, `ServiceOrder`→`WorkOrder`, `Part`+`InventoryItem`→`Product`. V2 names are in English and consistent with the docs.
**Resolution: V2 wins,** but note the product's users are Brazilian and the legacy UI is in Portuguese — the rename is a code-level concern only; UI copy should stay pt-BR.

### 12.9 API surface conventions
Legacy has no version prefix and mixes `/clients` with `/api/organizations`; two different Pagar.me webhook paths exist simultaneously. V2 mandates `/api/v1/*`.
**Resolution: V2 wins.** The legacy frontend will need a full API-client rewrite regardless, so there is no compatibility cost.

### 12.10 Audit: two tables vs one
Legacy has `audit_events` (general) and `financial_audit_logs` (finance-specific, with its own service). V2 has one `audit_logs` with JSONB old/new state.
**Resolution: V2 wins.** Verify that the finance-specific fields legacy tracked survive the JSONB representation.

---

## 13. Recommended migration order

Aligned to `IMPLEMENTATION_ROADMAP.md`, with a corrective phase 0 the roadmap does not have.

**Phase 0 — Make V2 runnable (days, not weeks)**
Fix the boot failure; move seed data into a Flyway migration. Fix tenant-aware login. Add `/auth/refresh` and `/auth/logout`. Configure CORS. Remove the `X-Tenant-ID` header path from `TenantFilter`. Hash refresh tokens. Add the first integration test that proves a request from tenant A cannot read tenant B's row.
*Exit criterion: `docker compose up` yields a working login/refresh/logout loop with a passing cross-tenant isolation test.*

**Phase 1 — IAM & authorization**
Permission catalogue and seeding, `role_permissions`, roles per unit, permissions in the JWT, `@PreAuthorize` on every endpoint, user CRUD, unit CRUD, tenant admin. Frontend: authenticated layout (sidebar + top bar), route guards, `<Can>`, axios interceptors, unit selector.
*This is the foundation every later phase depends on. Do not start business modules before it.*

**Phase 2 — Tenant hardening**
PostgreSQL RLS policies, `deleted_by` columns, soft-delete restrictions on entities, audit event publisher + async listener, MDC/correlation-id logging.

**Phase 3 — CRM**
Customers and vehicles: CRUD, per-tenant unique document/plate, soft delete, pagination, CSV import/export. Frontend: list/detail/form screens establishing the data-table, modal and import patterns the rest of the app reuses.

**Phase 4 — Operations: quotes**
Add `quote_items`. Quote lifecycle, public tokenized approval link, quote→work-order conversion.

**Phase 5 — Operations: work orders**
Add `work_order_items`. Status machine with legal transitions, mechanic assignment, technical notes, the three operational reports, public tracking token. Frontend: timeline/kanban.

**Phase 6 — Inventory**
Products, suppliers, append-only movements with reservation semantics, minimum-stock alerts. Integration: work-order completion emits an event that inventory consumes — never a direct repository call.

**Phase 7 — Finance**
Accounts, categories, transactions, cash flow, DRE. Integration: work-order completion emits an event that finance turns into a receivable; reopening reverses it.

**Phase 8 — Billing & entitlements**
Plan catalogue, subscription lifecycle, Pagar.me checkout + webhooks with idempotency, entitlement checks kept in a separate component from authorization.

**Phase 9 — Dashboard & analytics**
KPI cards, charts, consolidated vs per-unit views. Decide Java-vs-Python ownership of management reports first.

**Phase 10 — AI**
Rebuild the contract: an `ai` module in Spring Boot owning a client interface + DTOs, the AI service authenticated and tenant-scoped, no direct DB access from Python. Then chat, then optional voice/vision.

**Phase 11 — Secondary & cleanup**
LGPD, email, notifications, tutorials/docs, data migration from legacy, decommission.

---

## 14. Architectural risks

**R1 — AI service database access (critical).** `sql_agent` builds a `SQLDatabase.from_uri(DATABASE_URL)` over the entire business database and lets an LLM author arbitrary SQL. Tenant scoping exists only as the sentence *"Sempre considere o organization_id nas consultas"* inside a prompt. The schema summary it is given explicitly includes `users … password`. A crafted question can read any tenant's data, and the endpoint requires no authentication at all (`CORS_ORIGINS` defaults to `*`). **Any V2 AI integration must not reuse this design:** the AI service should receive tenant-scoped data through authenticated backend APIs, or hold a DB role restricted by RLS with the tenant set per request.

**R2 — Secrets committed to the repository (critical).** `gomech-backend/src/main/resources/application-dev.properties` contains a live database host, username and password in plaintext. Default fallbacks for `JWT_SECRET` and `ENCRYPTION_KEY` are hardcoded in `application.properties`, and V2 repeats the pattern with a default JWT secret in `application.yml`. Rotate the exposed credentials and purge them from git history before this repo is shared further.

**R3 — No authorization in V2 (critical).** Today `POST /api/v1/users` is reachable by any authenticated user. Building modules on top of this before phase 1 means retrofitting authorization across a growing surface.

**R4 — RLS promised but absent (high).** Both architecture docs treat RLS as the safety net under `@TenantId`. There are no policies. If a report tool, an analytics job, or the AI service ever connects to the database directly, the only isolation left is application code.

**R5 — Refresh tokens stored in plaintext (high).** Legacy stored them encrypted *and* hashed. V2 stores the raw UUID. A database read discloses every live session. This is a regression, not a simplification.

**R6 — `@TenantId` on a nullable column (high).** `roles.tenant_id` is nullable by design (system roles) but annotated `@TenantId`. Hibernate cannot express "tenant OR global" through the discriminator, so either global roles become unreachable or the annotation must be dropped and scoping done explicitly. `OnboardingService` already relies on `findByName("Proprietário")` finding a shared role — it will instead create one row per tenant.

**R7 — Missing line-item tables (high).** Quotes and work orders without items cannot represent the core business object. Anything built on the current schema will need reworking.

**R8 — Legacy tenant leakage during coexistence (high).** For as long as both systems run against related data, the legacy unscoped finders and the header-trusted tenant context remain exploitable. Decide whether legacy stays in production during the migration, and if so whether to patch its finders.

**R9 — Duplicated business logic across Java and Python (medium).** Profitability, bottlenecks and benchmarks are implemented twice — `ManagementReportService` in Java and `recommendation_agent` in Python — with different formulas. Consolidating is a prerequisite for a trustworthy dashboard.

**R10 — The AI service cannot follow V2's UUID migration (medium).** Its SQLAlchemy models use integer PKs and legacy table names. Every table it touches changes name, key type and tenant column. The service needs a contract-based rewrite, not an adjustment.

**R11 — Infrastructure discontinuity (medium).** Legacy deploys by SSH-ing into a VPS and restarting containers, with the deploy password in GitHub secrets. V2 documents GCP Cloud Run + Cloud SQL with Workload Identity. No V2 pipeline exists yet; the gap will be felt the first time something needs to reach staging.

**R12 — No test safety net (medium).** V2 has one stub test. §12 of the brief calls for behaviour comparison between old and new; without contract tests the only comparison available is manual.

**R13 — Frontend rebuild is larger than it looks (medium).** 86 legacy components, several of them heavy (customizable dashboard grid, checkout with polling, chatbot with markdown/charts/voice, SO item manager). Reimplementing on the V2 design system is a multi-month effort on its own and should be sequenced by workflow, not by component.

**R14 — Multi-unit is a new requirement with no legacy precedent (low but structural).** Every business table carries `unit_id` and every query needs a unit-scoping decision (consolidated vs per-unit). Getting this wrong early is expensive; settle the rule in phase 1 alongside authorization.

---

## 15. Questions that require your decision

**Q1 — Which palette is canonical: `#2563EB` blue (DESIGN_SYSTEM.md + `index.css`) or `#FF6500` orange (`.skills/ui-guidelines.md`, and what the login screen actually renders)?** Blocking: every screen from here on inherits it. Related: is the current `LoginForm`, with its hardcoded hexes and blurred gradient blobs, the intended visual direction, or a prototype to be redone from the design system?

**Q2 — Is the legacy system in production with real customer data today, and must the two run in parallel?** This determines whether we need a data migration with UUID remapping, whether legacy's tenant-leak paths need patching in the meantime, and whether cutover is per-module or big-bang.

**Q3 — MFA: keep, drop, or defer?** Legacy has working TOTP with encrypted secrets. V2's docs never mention it.

**Q4 — Inventory model: keep V2's single `products` table, or restore the legacy `Part` (catalogue) / `InventoryItem` (stock per unit) split?** With multi-unit as a first-class concept, the split may now be *more* justified than it was in legacy. Also: keep `current_stock_calculated` as a denormalized column, or derive stock from the append-only movement ledger?

**Q5 — Do quotes and work orders need line items in the V2 schema?** I assume yes and that this is an oversight, but it is a schema change to `V1__Initial_Schema.sql` (or a new `V2__` migration) and I would rather confirm than assume.

**Q6 — Which of these legacy features are still required?** Tutorial progress and in-app tours · customizable dashboard layouts · in-app docs page · WhatsApp messaging · client feedback / satisfaction survey · vision agent (damage detection, part OCR) · predictive and simulation agents · voice interface · in-app database backup job. Several have no consumer today.

**Q7 — Management reports: Java or Python?** Profitability, bottlenecks, benchmark and trends exist in both. Java keeps the domain logic testable and tenant-safe; Python keeps it near the LLM. My recommendation is Java for the numbers, Python only for narrative interpretation.

**Q8 — What is the AI service's data access contract in V2?** Options: (a) AI calls tenant-scoped backend REST APIs with a service token and a propagated tenant — safest, most work; (b) AI keeps a DB connection under a restricted PostgreSQL role with RLS and a per-request tenant setting; (c) status quo. This decides whether text-to-SQL survives at all.

**Q9 — Billing: rebuild Pagar.me now or defer?** The roadmap puts it at phase 8 and says beta customers can be invoiced manually, but a working transparent checkout already exists in `c421a97` and the code is a useful reference that will rot.

**Q10 — Is per-tenant email uniqueness intended?** V2's partial unique index is `(tenant_id, email)`; legacy was globally unique. Per-tenant is more correct for a SaaS, but it means login cannot identify a user by email alone — which ties directly into the broken login in §11.4. If we keep it, how does a user pick their workshop at login: subdomain, a workshop selector, or an email that happens to be unique in practice?

**Q11 — Scheduling/agenda: in or out of the MVP?** It appears in PROJECT_CONTEXT and the design system (Service Bay Timeline) but has no legacy implementation and no V2 tables.

**Q12 — Repository layout: does V2 stay a monorepo with `backend/` and `frontend/`, and does the AI service eventually move in as a third top-level directory?** It is currently a separate repository outside the V2 tree.

---

## Recommended next step

Answer Q1, Q2, Q5, Q10 (the blocking four), then let me execute **Phase 0** — roughly a day of work that turns V2 from a non-booting skeleton into a running, tenant-safe authentication foundation with the first isolation test. Everything after that has a stable base to build on.
