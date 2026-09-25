# ADR-017: Row Level Security (RLS) no PostgreSQL como defesa em profundidade

- **Status:** Aceita
- **Data:** 2026-08-18
- **Relacionadas:** [ADR-012 — Baseline de migrations e convenções de persistência](ADR-012-baseline-de-migrations-postgresql.md), [ADR-014 — Isolamento de tenant e unidade](ADR-014-isolamento-de-tenant-e-unidade.md)

> Numeração anterior: ADR-012 (renumerada para eliminar números duplicados).

## Contexto

O GoMech V2 é uma plataforma SaaS multi-tenant em que várias oficinas automotivas (tenants) compartilham um único banco e um único schema PostgreSQL (`public`). Dentro de cada tenant, as operações podem ainda ser subdivididas entre várias filiais físicas (unidades).

Na camada de aplicação, o Spring Boot e o `@TenantId` do Hibernate 6 fazem a primeira segregação dos dados, reescrevendo automaticamente as queries para acrescentar `WHERE tenant_id = ?` com base no contexto verificado da requisição (JWT).

No entanto, depender apenas do controle no nível da aplicação deixa possíveis vulnerabilidades de segurança:

1. **Acesso direto ao banco:** sistemas externos de relatório, conectores de business intelligence (BI) ou ferramentas administrativas de manutenção podem contornar a camada de aplicação Spring Boot.
2. **Geração de SQL pelo serviço de IA:** o serviço de IA ou agentes text-to-SQL que executem queries diretamente no banco poderiam ser manipulados via prompt injection para emitir SQL sem escopo de tenant.
3. **Queries SQL nativas e erros de desenvolvimento:** uma query SQL nativa (`@Query(nativeQuery = true)`) ou um statement JDBC customizado nos repositórios do backend poderia omitir, sem querer, a cláusula de `tenant_id`.
4. **Configurações incorretas do filtro do ORM:** qualquer falha no `TenantFilter`, no `TenantContextHolder` ou na configuração do resolver do Hibernate poderia, em tese, vazar linhas entre tenants.

Para oferecer uma segregação de dados incondicional, o sistema precisa do **Row Level Security (RLS) do PostgreSQL** como defesa secundária, impossível de contornar.

## Decisão

O GoMech V2 implementa **Row Level Security (RLS) no PostgreSQL** em todas as tabelas com escopo de tenant e de unidade, como **defesa em profundidade**.

### 1. Invariante da fronteira de segurança

- **O backend continua sendo a fronteira primária de segurança e autorização.**
- Regras de negócio, controle de acesso baseado em papéis (RBAC), escopo de unidade e autorização de domínio multi-tenant são avaliados na camada de aplicação.
- O RLS atua estritamente como uma rede de segurança automática e fail-closed na camada do motor de banco de dados. O RLS **não** é o único mecanismo de autorização.

### 2. Convenções de contexto de sessão: `app.current_tenant` e `app.current_unit`

As transações do banco estabelecem o contexto de isolamento por meio de configurações de sessão do PostgreSQL:

```sql
SET LOCAL app.current_tenant = '<tenant_uuid>';
SET LOCAL app.current_unit = '<unit_uuid>'; -- opcional, quando o usuário opera em uma filial específica
```

- **Escopo local à transação (`SET LOCAL`):** o modificador `LOCAL` garante que a configuração vale estritamente para a transação atual (`BEGIN ... COMMIT / ROLLBACK`). Quando a transação termina, o PostgreSQL restaura automaticamente o valor para vazio/nulo.
- **Segurança do pool de conexões:** como o `SET LOCAL` é resetado na fronteira da transação, as conexões devolvidas ao pool do HikariCP não carregam nenhum estado residual de tenant ou unidade, o que elimina por completo o vazamento de contexto entre requisições.
- **Helper de sessão:** gerenciado em Java pelo [`PostgresRlsSessionManager`](https://github.com/DeyvidJesus/gomech-backend-v2/blob/master/src/main/java/com/gomech/api/core/tenancy/PostgresRlsSessionManager.java).

### 3. Padrões de definição das policies

Implementadas pela migration Flyway [`V3__Enable_Tenant_And_Unit_Row_Level_Security.sql`](https://github.com/DeyvidJesus/gomech-backend-v2/blob/master/src/main/resources/db/migration/V3__Enable_Tenant_And_Unit_Row_Level_Security.sql):

#### A. Tabelas com escopo de tenant (`tenants`, `users`, `customers`, `vehicles`, `suppliers`, `subscriptions`, `audit_logs`)

```sql
ALTER TABLE <table_name> ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_policy ON <table_name>
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid)
    WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);
```

#### B. Tabelas com escopo de tenant + unidade (`units`, `user_roles`, `products`, `quotes`, `work_orders`, `inventory_movements`, `financial_transactions`)

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

#### C. Semântica das policies (negação por padrão)

- **Contexto não definido é fail-closed:** se `app.current_tenant` não estiver definido, `current_setting('app.current_tenant', true)` retorna `NULL`. `tenant_id = NULL` é avaliado como `UNKNOWN` (falso), retornando **0 linhas**.
- **Escopo por unidade ativa:** quando `app.current_unit` está definido, apenas as linhas da unidade ativa (ou as linhas de todo o tenant, com `unit_id IS NULL`) ficam visíveis ou podem ser alteradas. Tentativas de inserir ou modificar registros de outras filiais são rejeitadas com violação de policy de RLS.
- **Visibilidade global no tenant:** quando `app.current_unit` não está definido (ex.: dono da empresa ou gerente geral), o usuário acessa todas as unidades do seu tenant.

### 4. Modelo de roles do banco

Para garantir que o RLS seja aplicado em runtime e, ao mesmo tempo, permitir que ferramentas administrativas e migrations de schema funcionem, o banco usa classificações distintas de roles:

| Role do banco | Privilégios | Status do RLS | Uso |
|---|---|---|---|
| `gomech_app` | `SELECT, INSERT, UPDATE, DELETE` | **Aplicado** (`NOBYPASSRLS`) | Usado pelo datasource de runtime do backend Spring Boot. |
| `gomech_ai` | `SELECT` (somente leitura) | **Aplicado** (`NOBYPASSRLS`) | Usado pelo serviço de IA / ferramentas de relatório. |
| `gomech_admin` / `postgres` | `ALL PRIVILEGES` | **Ignorado** (`BYPASSRLS` ou superusuário) | Usado exclusivamente para as migrations de schema do Flyway e para operações de DBA. |

### 5. Convenções de migration

As definições de RLS seguem as convenções de migration Flyway documentadas na [ADR-012](ADR-012-baseline-de-migrations-postgresql.md):

- Sempre que uma migration Flyway introduzir uma nova tabela com escopo de tenant ou de unidade, o script **deve** habilitar o RLS e declarar a policy adequada.
- As policies de RLS são aplicadas nas 15 tabelas de negócio e operacionais na V3.

## Alternativas consideradas

### 1. RLS como único mecanismo de autorização

- *Descrição:* mover toda a lógica de autorização (papéis, permissões, ramificação multiunidade, unidades ativas do usuário) para policies SQL complexas no PostgreSQL.
- *Rejeitada:* policies SQL não têm segurança de tipos, são difíceis de testar unitariamente, introduzem penalidades severas no planejamento de queries e no uso de índices, e afastam as invariantes de domínio da camada de domínio da aplicação.

### 2. Isolamento apenas na aplicação, sem RLS

- *Descrição:* depender inteiramente do `@TenantId` do Hibernate e do Spring Security, sem policies no banco.
- *Rejeitada:* deixa o sistema indefeso contra acesso direto ao banco, conectores de analytics de terceiros, erros em SQL puro e agentes text-to-SQL de IA manipulados por prompt injection.

### 3. Um schema por tenant

- *Descrição:* schemas dinâmicos no PostgreSQL (`CREATE SCHEMA tenant_123`).
- *Rejeitada:* complexidade operacional excessiva, execução lenta das migrations Flyway em escala e esgotamento do pool de conexões.

## Trade-offs

### Benefícios

- **Isolamento de dados fail-closed:** mesmo que o código da aplicação execute `SELECT * FROM work_orders` sem nenhuma condição `WHERE`, o PostgreSQL retorna apenas as linhas do tenant e da unidade autorizados.
- **Resiliência do pool de conexões:** o `SET LOCAL` é resetado automaticamente na fronteira da transação, evitando contaminação de threads ou de conexões.
- **Contenção de IA e analytics:** serviços externos que se conectam como `gomech_ai` não conseguem ler dados de outros tenants, mesmo que um LLM peça.
- **Rede de segurança auditável:** violações de RLS geram exceções SQL imediatas (`42501 insufficient_privilege`), o que torna visíveis nos logs as tentativas de acesso entre tenants e entre unidades.

### Custos

- Pequeno overhead de latência para executar `SET LOCAL app.current_tenant` / `SET LOCAL app.current_unit` no início de cada transação.
- Exige roles de banco sem privilégio de superusuário nos testes de integração e nos deploys de produção, para garantir que as policies de RLS sejam de fato exercitadas.
- Jobs administrativos em background precisam estabelecer explicitamente o contexto de tenant ou rodar sob um role administrativo autorizado.

## Consequências

1. **Configuração do datasource:** o ciclo de vida das transações da aplicação executa `SET LOCAL app.current_tenant` e, opcionalmente, `SET LOCAL app.current_unit` ao abrir uma transação.
2. **Padrão para migrations Flyway:** toda nova tabela de tenant deve habilitar explicitamente o RLS e declarar sua policy de isolamento.
3. **Validação automatizada no CI:** a suíte de testes do CI inclui testes de RLS com Testcontainers que verificam a aplicação das policies sob um role de banco sem privilégio de superusuário.

## Obrigações de teste e testes de referência

A verificação executável das policies de RLS do PostgreSQL está implementada em:

- [**`PostgresRlsIsolationIT.java`**](https://github.com/DeyvidJesus/gomech-backend-v2/blob/master/src/test/java/com/gomech/api/database/PostgresRlsIsolationIT.java)
- [**`FlywayMigrationIT.java`**](https://github.com/DeyvidJesus/gomech-backend-v2/blob/master/src/test/java/com/gomech/api/database/FlywayMigrationIT.java)

### Cenários validados

1. **Isolamento de tenant:** queries executadas com `SET LOCAL app.current_tenant = 'tenant-a'` retornam exclusivamente linhas do Tenant A, ignorando as do Tenant B.
2. **Isolamento de unidade:** queries com escopo `app.current_unit = 'unit-1'` retornam apenas os registros daquela filial.
3. **Visibilidade global:** queries no Tenant A com `app.current_unit` não definido retornam registros de todas as unidades do Tenant A.
4. **Default fail-closed:** executar queries sem `app.current_tenant` configurado retorna `0` linhas.
5. **Prevenção de mutação entre unidades:** tentar inserir uma linha com `unit_id = 'unit-2'` enquanto `app.current_unit = 'unit-1'` é bloqueado com violação de RLS (`42501`).
6. **Prevenção de mutação entre tenants:** tentar inserir uma linha com `tenant_id = 'tenant-b'` enquanto `app.current_tenant = 'tenant-a'` é bloqueado com violação de RLS.
7. **Reset na fronteira da transação:** verifica que, após `commit` ou `rollback`, `app.current_tenant` e `app.current_unit` voltam a nulo/vazio na mesma conexão.
8. **Validação do catálogo no Flyway:** verifica `pg_tables.rowsecurity = true` para todas as tabelas de tenant no teste de migration.
