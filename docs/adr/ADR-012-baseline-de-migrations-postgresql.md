# ADR-012: Baseline de migrations PostgreSQL e convenções de transação e persistência

- **Status:** Aceita
- **Data:** 2026-08-18

## Contexto

O GoMech V2 é uma plataforma SaaS multi-tenant apoiada em PostgreSQL. O backend é um monolito modular Spring Boot em que cada módulo é dono da própria persistência (tabelas, índices, constraints), mas todos compartilham um único banco de dados e um único schema (multi-tenancy com schema compartilhado).

Para garantir alta integridade dos dados, fronteiras de transação previsíveis, resiliência contra lost updates e isolamento entre módulos, o projeto precisa de convenções de persistência padronizadas e aplicadas em todos os módulos.

## Decisão

### 1. Flyway como fonte única da verdade para o DDL

Todas as mudanças estruturais no banco **devem** passar por arquivos de migration numerados do Flyway. A propriedade do Hibernate `spring.jpa.hibernate.ddl-auto` fica permanentemente em `validate`: o Hibernate verifica o schema na inicialização, mas nunca o modifica.

### 2. Nomenclatura dos arquivos de migration

Os arquivos seguem a convenção do Flyway `V<version>__<Descriptive_Name>.sql`:

| Padrão | Exemplo | Uso |
|---|---|---|
| Versão major | `V1__Initial_Schema.sql` | DDL completo do schema de baseline |
| Versão sequencial | `V2__Add_Optimistic_Locking_Version_Columns.sql` | Adições estruturais |
| Versão minor | `V2.1__Add_Phone_To_Customer.sql` | Pequenas alterações em um módulo existente |
| Nome descritivo | Em inglês, `Snake_Case` | Sempre descreve o que mudou |

Dois underscores (`__`) separam a versão da descrição. Arquivos já aplicados em qualquer ambiente **nunca devem ser modificados**: o Flyway valida os checksums e impede a aplicação de subir.

### 3. Chaves primárias UUID

Todas as tabelas usam chaves primárias `UUID` geradas pela função `uuid_generate_v4()` do PostgreSQL (da extensão `uuid-ossp`). Isso evita ataques de enumeração via IDs sequenciais e garante unicidade global entre tenants e ambientes.

As entidades Java usam `java.util.UUID` com o valor padrão `id = UUID.randomUUID()`. O default do banco (`uuid_generate_v4()`) funciona como rede de segurança para inserts SQL diretos.

### 4. Convenções de timestamp

| Tipo no DDL | Tipo Java | Valor padrão |
|---|---|---|
| `TIMESTAMP WITH TIME ZONE` | `java.time.OffsetDateTime` | `OffsetDateTime.now()` |

Todas as colunas de auditoria (`created_at`, `updated_at`, `deleted_at`) e os timestamps de domínio (`expires_at`, `last_login`, `start_date`, `end_date` etc.) usam `TIMESTAMP WITH TIME ZONE` no DDL e `OffsetDateTime` no Java. `LocalDateTime` **não** é usado em nenhum timestamp mapeado no banco: ele descarta a informação de fuso horário e depende silenciosamente do fuso padrão da JVM.

Colunas de auditoria padrão, presentes em todas as tabelas:

- `created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP`: definida uma única vez no insert, com `updatable = false` no JPA.
- `updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP`: atualizada pela aplicação a cada escrita.

Tabelas com soft delete acrescentam:

- `deleted_at TIMESTAMP WITH TIME ZONE`: `NULL` significa registro ativo. Os índices únicos usam `WHERE deleted_at IS NULL` para garantir unicidade parcial.

### 5. Optimistic locking e controle de concorrência

Todas as tabelas de domínio mutáveis usam controle de concorrência otimista por meio de uma coluna `version`:

- **DDL:** `version BIGINT NOT NULL DEFAULT 0`
- **Entidade JPA:**
  ```java
  @Version
  @Column(name = "version", nullable = false)
  private Long version = 0L;
  ```

#### Critérios de decisão para versionamento

| Tipo de entidade | Optimistic locking (`@Version`) | Justificativa |
|---|---|---|
| **Agregados de domínio mutáveis** (`tenants`, `users`, `work_orders`, `quotes`, `products`, `customers` etc.) | **Sim** | Evita lost updates quando dois usuários editam o mesmo registro ao mesmo tempo. |
| **Ledgers append-only** (`inventory_movements`, `audit_logs`) | **Não** | Linhas imutáveis, escritas uma única vez; não existem atualizações concorrentes. |
| **Tabelas de junção puras** (`role_permissions`, `user_roles`) | **Não** | Gerenciadas por PKs compostas e pelo ciclo de vida do agregado pai. |
| **Sessões de curta duração** (`user_sessions`) | **Não** | Inseridas no login e removidas no logout/revogação; são substituídas em vez de alteradas. |

#### Resolução de conflitos

Quando modificações concorrentes colidem, o Hibernate lança `OptimisticLockingFailureException`. O `GlobalExceptionHandler` traduz essa exceção para HTTP **`409 Conflict`** usando Problem Details (RFC 7807):

- `type`: `https://gomech.com/docs/errors/concurrency-conflict`
- `title`: `Conflict`
- `detail`: `"The resource was modified by another concurrent transaction. Please refresh and retry."`

### 6. Fronteiras e convenções de transação

1. **Responsabilidade da camada de aplicação:** as transações são definidas exclusivamente na fronteira do caso de uso / application service, em `com.gomech.api.modules.<module>.application`.
2. **Controllers e repositórios:** `@Transactional` é estritamente proibido nos controllers de `api` e nas interfaces de repositório de `infrastructure`. Isso é garantido mecanicamente por regras ArchUnit:
   - `controllers_must_not_be_transactional`
   - `controller_methods_must_not_be_transactional`
   - `repositories_must_not_declare_transactional`
3. **Transações somente leitura:** casos de uso apenas de consulta e métodos de leitura devem declarar `@Transactional(readOnly = true)`. Isso otimiza o uso de conexões com o banco e instrui o Hibernate a desativar as verificações de flush e a manutenção de snapshots.
4. **Transações de escrita:** métodos que alteram estado declaram `@Transactional`.
5. **Critérios de rollback:** o rollback padrão do Spring se aplica a todas as exceções não verificadas (`RuntimeException` e `Error`). Se um caso de uso declarar exceções de negócio verificadas (checked) que devam disparar rollback, ele precisa especificar `@Transactional(rollbackFor = Exception.class)`.

### 7. Índices, foreign keys e constraints

#### Convenções de índices

- **Prefixo de tenant nos índices:** todo índice secundário e toda unique constraint em tabelas com escopo de tenant **devem** começar por `tenant_id` (ex.: `CREATE INDEX idx_products_tenant_sku ON products(tenant_id, sku_code)`).
- **Índices parciais para soft delete:** unique constraints em tabelas com `deleted_at` devem usar índices únicos parciais do PostgreSQL, com `WHERE deleted_at IS NULL`:
  ```sql
  CREATE UNIQUE INDEX idx_users_tenant_email ON users(tenant_id, email) WHERE deleted_at IS NULL;
  ```
- **Padrão de nomenclatura:**
  - Índices comuns: `idx_<table>_<column(s)>`
  - Índices únicos: `idx_<table>_<column(s)>` (ou `idx_<table>_unique`)

#### Foreign keys e fronteiras de relacionamento (isolamento de módulos)

- **Dentro do módulo:** tabelas do mesmo módulo usam foreign keys do PostgreSQL (`REFERENCES <table>(id)`) e relacionamentos JPA `@ManyToOne` / `@OneToMany`.
- **Entre módulos:** foreign keys que cruzam fronteiras de módulo são **proibidas**. Um módulo referencia entidades de outro módulo por campos UUID simples (ex.: `UUID customerId` em `work_orders`), sem FK no banco nem relação entre entidades JPA.
- **Regras de cascade:** `@OneToMany(cascade = CascadeType.ALL, orphanRemoval = true)` só é permitido dentro de um aggregate root que gerencia suas entidades filhas internas e privadas (ex.: `User` -> `UserRole`). Cascades nunca devem atravessar aggregate roots nem fronteiras de módulo.

### 8. Configuração do Flyway por profile

| Profile | `baseline-on-migrate` | `validate-on-migrate` | `out-of-order` |
|---|---|---|---|
| `application.yml` (raiz) | `false` | `true` | `false` |
| `local` | `true` | herdado | herdado |
| `dev` | `true` | herdado | herdado |
| `staging` | `false` | herdado | herdado |
| `prod` | `false` | herdado | herdado |

`baseline-on-migrate: true` só é habilitado nos profiles local/dev, para simplificar o onboarding com bancos já existentes. Staging e produção nunca devem fazer baseline: o schema deve ser criado exclusivamente pela execução das migrations a partir da V1.

### 9. Estratégia de rollback: fix forward

A edição open source do Flyway não suporta undo migrations (`U__`). Quando uma migration falha:

- **Local/dev:** apague o banco (ou o volume Docker), corrija o script e execute novamente.
- **Staging/produção:** nunca edite o script que falhou. Crie uma nova migration corretiva (`V<n+1>__Fix_<description>.sql`). Em caso de corrupção catastrófica de dados, use o Point-in-Time Recovery (PITR) do Cloud SQL.

### 10. Testes automatizados de persistência e arquitetura

Três suítes de testes automatizados controlam as mudanças de persistência:

1. **`FlywayMigrationIT`**: teste de integração puro com Testcontainers que valida que toda a cadeia de migrations do Flyway é aplicada a partir de um banco vazio, cria as 19 tabelas, habilita `uuid-ossp` e configura corretamente as colunas `UUID`, `TIMESTAMPTZ` e `version`.
2. **`PersistenceTransactionsAndConcurrencyIT`**: teste de integração com Spring Boot + Testcontainers que verifica a integridade do rollback transacional, a detecção de colisões de optimistic locking, o incremento de versão e os índices únicos parciais de soft delete.
3. **`ModuleArchitectureRulesTest`**: suíte ArchUnit que garante as camadas dos módulos, o ownership da persistência e as fronteiras de `@Transactional`.

## Consequências

1. **Disciplina nas entidades:** toda entidade JPA deve usar `OffsetDateTime` nos campos de timestamp e `Long version` com `@Version` nas entidades mutáveis.
2. **Segurança sob concorrência:** lost updates são evitados sem locks pessimistas no banco, mantendo alto throughput sob carga concorrente.
3. **Fronteiras de transação estritas:** o ciclo de vida das transações é previsível e fica isolado na camada de aplicação, o que mantém as camadas de apresentação e de persistência livres de código de gerenciamento de transações.
4. **Desacoplamento entre módulos:** como foreign keys entre módulos e associações diretas entre entidades são proibidas, os módulos podem evoluir seus schemas internos de persistência sem propagar breaking changes para os módulos vizinhos.
5. **Verificação contínua:** qualquer erro de migration, divergência de tipo entre entidade e DDL ou violação de fronteira de transação quebra o build imediatamente e bloqueia o CI.
