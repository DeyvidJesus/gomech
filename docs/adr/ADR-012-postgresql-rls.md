# ADR-012: PostgreSQL Row Level Security (RLS) as Defense in Depth

**Status:** Accepted  
**Date:** 2026-08-18  
**Deciders:** Engineering team  
**Supersedes:** None  
**Complements:** [ADR-003: Tenant and Unit Isolation](/home/deyvid/Documents/work/gomech-project/gomech/docs/adr/ADR-003-tenant-and-unit-isolation.md), [ADR-012: PostgreSQL Migration Baseline and Persistence Conventions](/home/deyvid/Documents/work/gomech-project/gomech/docs/adr/ADR-012-postgresql-migration-baseline.md)

## Context

GoMech V2 is a multi-tenant SaaS platform where multiple automotive repair workshops (tenants) share a single PostgreSQL database and schema (`public`). Within each tenant, operations may be further subdivided across multiple physical workshop branches (units).

In the application layer, Spring Boot and Hibernate 6 `@TenantId` provide first-line data segregation by automatically rewriting queries to append `WHERE tenant_id = ?` based on verified JWT request context.

However, relying solely on application-level enforcement leaves potential security vulnerabilities:

1. **Direct Database Access:** External reporting systems, business intelligence (BI) connectors, or administrative maintenance tools may bypass the Spring Boot application layer.
2. **AI Service SQL Generation:** The AI service or text-to-SQL agents running queries directly against the database could be manipulated via prompt injection to emit un-scoped SQL queries.
3. **Native SQL Queries & Developer Errors:** A native SQL query (`@Query(nativeQuery = true)`) or custom JDBC statement in backend repositories could inadvertently omit the `tenant_id` clause.
4. **ORM Filter Misconfigurations:** Any flaw in `TenantFilter`, `TenantContextHolder`, or Hibernate resolver configuration could theoretically leak rows across tenant boundaries.

To provide unconditional data segregation, the system requires **PostgreSQL Row Level Security (RLS)** as a non-bypassable secondary defense.

## Decision

GoMech V2 implements **PostgreSQL Row Level Security (RLS)** across all tenant-scoped and unit-scoped database tables as **defense in depth**.

### 1. Security Boundary Invariant
- **The backend application remains the primary security and authorization boundary.**
- Business rules, role-based access control (RBAC), unit scoping, and multi-tenant domain authorization are evaluated in the application layer.
- RLS serves strictly as an automated, fail-closed safety net at the database engine layer. RLS is **not** the sole authorization mechanism.

### 2. Session Context Conventions: `app.current_tenant` & `app.current_unit`

Database transactions establish isolation context via PostgreSQL session settings:

```sql
SET LOCAL app.current_tenant = '<tenant_uuid>';
SET LOCAL app.current_unit = '<unit_uuid>'; -- optional, when user operates in specific branch
```

- **Transaction-Local Scoping (`SET LOCAL`):** The `LOCAL` modifier guarantees that the setting is scoped strictly to the current transaction (`BEGIN ... COMMIT / ROLLBACK`). When the transaction finishes, PostgreSQL automatically resets the setting to empty/null.
- **Connection Pool Safety:** Because `SET LOCAL` resets at the transaction boundary, connections returned to the HikariCP connection pool carry no leftover tenant or unit state, completely eliminating cross-request context leakage.
- **Session Helper:** Managed in Java via [`PostgresRlsSessionManager`](file:///home/deyvid/Documents/work/gomech-project/gomech/backend/src/main/java/com/gomech/api/core/tenancy/PostgresRlsSessionManager.java).

### 3. Policy Definition Standards

Implemented via Flyway migration [`V3__Enable_Tenant_And_Unit_Row_Level_Security.sql`](file:///home/deyvid/Documents/work/gomech-project/gomech/backend/src/main/resources/db/migration/V3__Enable_Tenant_And_Unit_Row_Level_Security.sql):

#### A. Tenant-Scoped Tables (`tenants`, `users`, `customers`, `vehicles`, `suppliers`, `subscriptions`, `audit_logs`)
```sql
ALTER TABLE <table_name> ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_policy ON <table_name>
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid)
    WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);
```

#### B. Tenant + Unit Scoped Tables (`units`, `user_roles`, `products`, `quotes`, `work_orders`, `inventory_movements`, `financial_transactions`)
```sql
ALTER TABLE <table_name> ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_and_unit_isolation_policy ON <table_name>
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

#### C. Policy Semantics (Deny by Default)
- **Fail-Closed Unset Context:** If `app.current_tenant` is unset, `current_setting('app.current_tenant', true)` returns `NULL`. `tenant_id = NULL` evaluates to `UNKNOWN` (false), returning **0 rows**.
- **Active Unit Scoping:** When `app.current_unit` is set, only rows matching the active unit (or tenant-wide rows with `unit_id IS NULL`) are visible or mutable. Attempting to insert or modify records belonging to other branches is rejected with an RLS policy violation.
- **Global Tenant Visibility:** When `app.current_unit` is unset (e.g. company owner or general manager), the user accesses all units within their tenant.

### 4. Database Role Model

To ensure RLS is enforced during runtime while allowing administrative tools and schema migrations to function, the database uses distinct role classifications:

| Database Role | Privileges | RLS Status | Usage |
|---|---|---|---|
| `gomech_app` | `SELECT, INSERT, UPDATE, DELETE` | **Enforced** (`NOBYPASSRLS`) | Used by the Spring Boot backend runtime datasource. |
| `gomech_ai` | `SELECT` (read-only) | **Enforced** (`NOBYPASSRLS`) | Used by the AI service / reporting tools. |
| `gomech_admin` / `postgres` | `ALL PRIVILEGES` | **Bypassed** (`BYPASSRLS` or Superuser) | Used exclusively for Flyway schema migrations and DBA operations. |

### 5. Migration Conventions

RLS definitions follow the Flyway migration conventions documented in ADR-012:
- Whenever a Flyway migration introduces a new tenant-scoped or unit-scoped table, the migration script **must** enable RLS and declare the appropriate policy.
- All RLS policies are applied across all 15 business and operational tables in V3.

---

## Alternatives Considered

### 1. RLS as the Sole Authorization Engine
- *Description:* Move all authorization logic (roles, permissions, multi-unit branching, user active units) into complex PostgreSQL SQL policies.
- *Rejected:* SQL policies lack type safety, are difficult to unit-test, introduce severe query planning and index penalty overhead, and decouple domain invariants from the application domain layer.

### 2. Application-Only Isolation Without RLS
- *Description:* Rely entirely on Hibernate `@TenantId` and Spring Security without database-level policies.
- *Rejected:* Leaves the system defenseless against direct database access, third-party analytics connectors, raw SQL errors, and prompt-injected AI text-to-SQL agents.

### 3. Schema-per-Tenant
- *Description:* Dynamic PostgreSQL schemas (`CREATE SCHEMA tenant_123`).
- *Rejected:* Excessive operational complexity, slow Flyway migration execution at scale, and connection pool exhaustion.

---

## Trade-offs

### Benefits
- **Fail-Closed Data Isolation:** Even if application code issues `SELECT * FROM work_orders` with zero `WHERE` conditions, PostgreSQL returns only the authorized tenant and unit rows.
- **Connection Pool Resilience:** `SET LOCAL` auto-resets at transaction boundaries, preventing thread or connection contamination.
- **AI & Analytics Containment:** External services connecting under `gomech_ai` cannot read other tenants' data even if requested by an LLM.
- **Auditable Safety Net:** RLS violations produce immediate SQL exceptions (`42501 insufficient_privilege`), making cross-tenant and cross-unit access attempts visible in logs.

### Costs
- Minor latency overhead of executing `SET LOCAL app.current_tenant` / `SET LOCAL app.current_unit` at transaction initialization.
- Requires non-superuser database roles in integration tests and production deployments to ensure RLS policies are actively exercised.
- Background administrative jobs must explicitly establish tenant context or run under an authorized administrative role.

---

## Consequences

1. **Datasource Configuration:** The application transaction lifecycle sets `SET LOCAL app.current_tenant` and optionally `SET LOCAL app.current_unit` upon opening a transaction.
2. **Flyway Migration Standard:** Every new tenant table must explicitly enable RLS and declare its isolation policy.
3. **Automated CI Validation:** The CI test suite includes Testcontainers-based RLS tests verifying policy enforcement under a non-superuser database role.

---

## Testing Obligations & Reference Tests

Executable verification of PostgreSQL RLS policies is implemented in:

- [**`PostgresRlsIsolationIT.java`**](file:///home/deyvid/Documents/work/gomech-project/gomech/backend/src/test/java/com/gomech/api/database/PostgresRlsIsolationIT.java)
- [**`FlywayMigrationIT.java`**](file:///home/deyvid/Documents/work/gomech-project/gomech/backend/src/test/java/com/gomech/api/database/FlywayMigrationIT.java)

### Test Scenarios Validated:
1. **Tenant Isolation:** Queries executed under `SET LOCAL app.current_tenant = 'tenant-a'` return exclusively Tenant A rows, ignoring Tenant B rows.
2. **Unit Isolation:** Queries scoped to `app.current_unit = 'unit-1'` return only that branch's records.
3. **Global Visibility:** Queries under Tenant A with unset `app.current_unit` return records from all units in Tenant A.
4. **Fail-Closed Default:** Executing queries without `app.current_tenant` configured returns `0` rows.
5. **Cross-Unit Mutation Prevention:** Attempting to insert a row with `unit_id = 'unit-2'` while `app.current_unit = 'unit-1'` is blocked with an RLS violation (`42501`).
6. **Cross-Tenant Mutation Prevention:** Attempting to insert a row with `tenant_id = 'tenant-b'` while `app.current_tenant = 'tenant-a'` is blocked with an RLS violation.
7. **Transaction Boundary Reset:** Verifies that upon transaction `commit` or `rollback`, `app.current_tenant` and `app.current_unit` reset to null/empty on the same connection.
8. **Flyway Catalog Validation:** Verifies `pg_tables.rowsecurity = true` for all tenant tables in the migration test.
