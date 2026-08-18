# ADR-003: Tenant and Unit Isolation

**Status:** Accepted  
**Date:** 2026-08-18  
**Deciders:** Engineering team  
**Supersedes:** None

## Context

GoMech V2 is a multi-tenant SaaS platform built for automotive mechanical workshops. The domain hierarchy distinguishes between two distinct organizational levels:

- **Tenant (Company / Legal Entity):** The top-level account and legal boundary (e.g., "Auto Mecânica Silva Ltda"). A tenant is completely isolated from all other tenants; under no circumstance may data, users, or operations leak across tenant boundaries.
- **Unit (Workshop Branch / Filial):** A physical workshop facility operating under a tenant. A single tenant may own one or multiple units (e.g., "Matriz - Centro" and "Filial - Zona Sul").

In the legacy GoMech system, tenant isolation was advisory and dependent on manual developer discipline (e.g., remembering to call repository methods named `...AndOrganizationId`). This resulted in over 50 repository queries lacking tenant scoping, creating severe security risks.

In GoMech V2, tenant and unit isolation must be strictly enforced, mathematically impossible to bypass accidentally in application code, and backed by defense-in-depth database guarantees.

## Decision

GoMech V2 adopts a **Shared Database, Shared Schema** architecture with strict multi-layered isolation:

1. **Backend as the Authoritative Security Boundary:** The Spring Boot backend enforces all tenant and unit authorization. The frontend is never trusted for security or isolation.
2. **Hibernate `@TenantId` Integration (Layer 1):** The ORM automatically injects `tenant_id` into all generated SQL (`WHERE tenant_id = ?`) and populates `tenant_id` on insertions based on verified request context.
3. **PostgreSQL Row-Level Security / RLS (Layer 2 — Defense in Depth):** PostgreSQL policies act as a failsafe against rogue queries, developer errors, direct database connections, or AI service SQL tools.
4. **Separation of Tenant Trust Sources:** The system distinguishes between authenticated, system-generated, and caller-requested tenancy to prevent privilege escalation or identity spoofing.

---

## Scope Semantics: Tenant vs. Unit

### 1. Tenant (Company) Isolation
- **Boundary Type:** Hard, non-negotiable security boundary.
- **Model:** Every tenant-scoped entity contains a mandatory `tenant_id UUID NOT NULL REFERENCES tenants(id)`.
- **Enforcement:** Every ORM read and write is scoped to `tenant_id`. Users belonging to Tenant A can never query, mutate, or observe data belonging to Tenant B.

### 2. Unit (Branch) Isolation
- **Boundary Type:** Operational / hierarchical subdivision within a tenant.
- **Model:** Operational entities (e.g., `quotes`, `work_orders`, `inventory_movements`, `financial_transactions`, branch-specific `products`) contain a `unit_id UUID REFERENCES units(id)` in addition to `tenant_id`.
- **Global vs. Local Roles:**
  - **Global Scope (Tenant-Wide):** Users with company-wide roles (e.g., `Proprietário`, `Gerente Geral`) operate across all units within their tenant without unit filtering.
  - **Local Scope (Unit-Specific):** Users assigned to a specific branch (e.g., `Mecânico`, `Atendente da Filial`) operate strictly within their assigned `unit_id`.

---

## Multi-Unit Users and Active-Unit Switching

### Relationship Modeling
Users can hold distinct roles across multiple units within the same tenant via the `user_roles` association:
- `user_id UUID NOT NULL`
- `role_id UUID NOT NULL`
- `unit_id UUID` *(NULL for global/tenant-wide roles, or specific unit ID for branch roles)*

### Request Context & JWT Claims
When a user authenticates:
1. The backend issues a signed JWT containing:
   - `sub`: User ID
   - `tenantId`: Mandatory tenant UUID
   - `unitId`: Optional active unit UUID (present when the session is scoped to a specific branch)
   - `roles` and `permissions`: Authorized authorities for the active context.

### Active-Unit Switching Flow
1. When a user with access to multiple branches switches their active unit in the client application:
   - The client invokes the unit switch endpoint: `POST /api/v1/auth/switch-unit` with `{ "unitId": "<target_unit_uuid>" }`.
   - The backend validates that:
     1. The target `unit_id` belongs to the user's `tenant_id`.
     2. The user has an active role assignment for that `unit_id` (or holds a global tenant role).
   - Upon successful validation, the backend issues an updated JWT containing the new active `unitId` claim and corresponding permissions.
2. Subsequent requests carry the new token, establishing the updated `UnitReference` in `UnitContextHolder`.

---

## Request Context Lifecycle & Trust Model

### Context Holders (`ThreadLocal`)
- **`TenantContextHolder`:** Holds the current `tenantId` and its `TenantSource`.
- **`UnitContextHolder`:** Holds an `Optional<UnitReference>` identifying the active unit. Core slices depend only on the bare identifier record `UnitReference(UUID id)` to prevent coupling with domain models (ADR-002).

### Tenant Trust Sources (`TenantSource`)

| Source | Established By | Trusted | Reaches `ActorContext` / `@TenantId` |
|---|---|---|---|
| `AUTHENTICATED` | `JwtAuthenticationFilter` from verified `tenantId` claim in JWT | **Yes** | **Yes** |
| `SYSTEM` | Server-side internal execution (e.g., onboarding registering a new tenant) | **Yes** | **Yes** |
| `REQUESTED` | Caller-supplied `X-Tenant-ID` header | **No** | **No** |

### Request Header Rules (`X-Tenant-ID`)
1. **Disabled in Deployed Environments:** `gomech.tenancy.trust-request-header` defaults to `false` in `application.yml`, `staging`, and `prod`. Only the `local` profile enables it for manual curl/Postman testing before tenant-aware login is finalized.
2. **Restricted Path Scope:** Even when enabled, it is only inspected on pre-authentication endpoints that require tenant selection prior to credentials verification (`/api/v1/auth/login`).
3. **Cannot Override Proven Identity:** `TenantContextHolder.setRequestedTenant(...)` is rejected if an `AUTHENTICATED` or `SYSTEM` tenant is already set.

### Guaranteed Cleanup
`TenantFilter` is the outermost filter in the request chain (`Ordered.HIGHEST_PRECEDENCE + 10`, running inside `CorrelationIdFilter`). Its `finally` block unconditionally clears `TenantContextHolder` and `UnitContextHolder`, guaranteeing no tenant/unit context leaks onto pooled container threads.

---

## Defense in Depth: Role of PostgreSQL RLS

While Hibernate `@TenantId` provides first-line application-level filtering, PostgreSQL **Row Level Security (RLS)** is configured across all tenant and unit tables as a second layer of defense (Flyway `V3__Enable_Tenant_And_Unit_Row_Level_Security.sql`):

1. **Session Parameters:** On acquiring a database connection or starting a transaction, the backend sets:
   ```sql
   SET LOCAL app.current_tenant = '<tenant_uuid>';
   SET LOCAL app.current_unit = '<unit_uuid>'; -- optional, when operating within a specific branch
   ```
2. **PostgreSQL RLS Policies:**
   - **Tenant Isolation Policy:**
     ```sql
     CREATE POLICY tenant_isolation_policy ON <table>
         FOR ALL
         USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid)
         WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);
     ```
   - **Tenant & Unit Isolation Policy:**
     ```sql
     CREATE POLICY tenant_and_unit_isolation_policy ON <table>
         FOR ALL
         USING (
             tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid
             AND (
                 unit_id IS NULL
                 OR NULLIF(current_setting('app.current_unit', true), '') IS NULL
                 OR unit_id = NULLIF(current_setting('app.current_unit', true), '')::uuid
             )
         )
         WITH CHECK (
             tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid
             AND (
                 unit_id IS NULL
                 OR NULLIF(current_setting('app.current_unit', true), '') IS NULL
                 OR unit_id = NULLIF(current_setting('app.current_unit', true), '')::uuid
             )
         );
     ```
3. **Purpose of RLS:**
   - Prevents catastrophic data leaks in the event of ORM misconfiguration, raw native SQL queries, or developer omission of `@TenantId`.
   - Constrains external reporting, BI tools, and AI service text-to-SQL agents connecting directly to PostgreSQL under a restricted database role.
   - Denies mismatched unit writes and queries when active unit is scoped.

---

## Alternatives Considered

### 1. Database-per-Tenant
- *Description:* Separate PostgreSQL database for each workshop.
- *Rejected:* Excessive operational complexity, connection pool exhaustion, and difficult Flyway schema migrations across hundreds of small workshops.

### 2. Schema-per-Tenant
- *Description:* Separate PostgreSQL schema (`CREATE SCHEMA tenant_xxx`) per workshop.
- *Rejected:* High migration maintenance overhead, slow startup times as tenant count grows, and limited connection pooling efficiency.

### 3. Advisory Application-Level Filtering (Legacy Model)
- *Description:* Repositories manually filtering by `organization_id` on specific methods.
- *Rejected:* Proven failure in the legacy codebase with over 50 leaked queries. Lacks structural guarantees.

### 4. RLS as Sole Enforcement
- *Description:* Relying exclusively on PostgreSQL RLS without ORM `@TenantId`.
- *Rejected:* Harder to debug, causes silent query truncation without application visibility, and fails if connection pool session variables are omitted.

---

## Trade-offs

### Benefits
- **Zero Cross-Tenant Leakage:** Dual-layer enforcement (ORM + RLS) eliminates accidental cross-tenant queries.
- **Operational Efficiency:** Single database and schema maximize hardware utilization and streamline Flyway migrations.
- **Deterministic Context:** Explicit trust model prevents header-based spoofing.
- **Clean Core Scaffolding:** Core carries tenant/unit context without knowing internal module entity details.

### Costs
- Every tenant entity must carry `@TenantId` and `tenant_id`.
- All secondary indexes must be prefixed with `tenant_id`.
- Connection pooling requires per-transaction `SET LOCAL` parameter configuration for full RLS activation.

---

## Consequences

1. **Entity Definition Rules:** Every table belonging to a tenant must declare `tenant_id UUID NOT NULL REFERENCES tenants(id)` and map `@TenantId private UUID tenantId;`.
2. **Index Standards:** All single and composite indexes on tenant tables must lead with `tenant_id` (ADR-012).
3. **Public Contract Boundaries:** Cross-module contracts use `UUID` references and never join across tenant boundaries (ADR-002).
4. **Architectural Verification:** Unit and integration tests verify that tenant context is immutable during requests, never spoofable, and cleared upon completion.

---

## Testing Obligations & Reference Tests

### 1. Unit & Trust Boundary Tests
- [`TenantTrustBoundaryTest.java`](file:///home/deyvid/Documents/work/gomech-project/gomech/backend/src/test/java/com/gomech/api/core/security/TenantTrustBoundaryTest.java):
  - Validates that caller `X-Tenant-ID` header cannot overwrite an authenticated tenant.
  - Validates that unauthenticated requests to business endpoints ignore tenant headers.
  - Validates that tenant and unit contexts are cleared in `finally` blocks across all request shapes.
- [`TenantContextHolderTest.java`](file:///home/deyvid/Documents/work/gomech-project/gomech/backend/src/test/java/com/gomech/api/core/tenancy/TenantContextHolderTest.java):
  - Validates precedence of `AUTHENTICATED` and `SYSTEM` over `REQUESTED`.
- [`RequestContextLifecycleTest.java`](file:///home/deyvid/Documents/work/gomech-project/gomech/backend/src/test/java/com/gomech/api/core/security/RequestContextLifecycleTest.java):
  - Validates the complete pipeline: Request → `TenantFilter` → `JwtAuthenticationFilter` → `ActorContext`.

### 2. Persistence & Concurrency Tests
- [`PersistenceTransactionsAndConcurrencyIT.java`](file:///home/deyvid/Documents/work/gomech-project/gomech/backend/src/test/java/com/gomech/api/database/PersistenceTransactionsAndConcurrencyIT.java):
  - Validates multi-tenant persistence isolation and partial unique indexes (`WHERE deleted_at IS NULL`).

### 3. RLS Integration Tests
- [`PostgresRlsIsolationIT.java`](file:///home/deyvid/Documents/work/gomech-project/gomech/backend/src/test/java/com/gomech/api/database/PostgresRlsIsolationIT.java):
  - Validates tenant isolation, branch-level unit isolation, global visibility, fail-closed defaults, and cross-tenant/cross-unit mutation rejection under RLS.
