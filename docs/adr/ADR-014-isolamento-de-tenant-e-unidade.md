# ADR-014: Isolamento de tenant e unidade

- **Status:** Aceita
- **Data:** 2026-08-18

> Numeração anterior: ADR-003 (renumerada para eliminar números duplicados).

## Contexto

O GoMech V2 é uma plataforma SaaS multi-tenant voltada para oficinas mecânicas automotivas. A hierarquia de domínio distingue dois níveis organizacionais:

- **Tenant (empresa / pessoa jurídica):** a conta de nível mais alto e a fronteira legal (ex.: "Auto Mecânica Silva Ltda"). Um tenant é completamente isolado de todos os outros; em nenhuma circunstância dados, usuários ou operações podem vazar entre tenants.
- **Unidade (filial da oficina):** uma oficina física que opera sob um tenant. Um mesmo tenant pode ter uma ou várias unidades (ex.: "Matriz - Centro" e "Filial - Zona Sul").

No sistema GoMech legado, o isolamento de tenant era apenas orientativo e dependia da disciplina manual dos desenvolvedores (ex.: lembrar de chamar os métodos de repositório com sufixo `...AndOrganizationId`). O resultado foram mais de 50 queries de repositório sem escopo de tenant, o que criava riscos graves de segurança.

No GoMech V2, o isolamento de tenant e unidade precisa ser aplicado de forma estrita, ser impossível de contornar por acidente no código da aplicação e contar com garantias de defesa em profundidade no próprio banco de dados.

## Decisão

O GoMech V2 adota uma arquitetura de **banco compartilhado e schema compartilhado** (*Shared Database, Shared Schema*), com isolamento estrito em várias camadas:

1. **Backend como fronteira de segurança autoritativa:** o backend Spring Boot aplica toda a autorização de tenant e unidade. O frontend nunca é considerado confiável para segurança ou isolamento.
2. **Integração com o `@TenantId` do Hibernate (camada 1):** o ORM injeta automaticamente `tenant_id` em todo SQL gerado (`WHERE tenant_id = ?`) e preenche `tenant_id` nas inserções, com base no contexto verificado da requisição.
3. **Row Level Security (RLS) do PostgreSQL (camada 2 — defesa em profundidade):** as policies do PostgreSQL funcionam como failsafe contra queries indevidas, erros de desenvolvimento, conexões diretas ao banco ou ferramentas SQL do serviço de IA.
4. **Separação das fontes de confiança do tenant:** o sistema distingue a tenancy autenticada, a gerada pelo sistema e a solicitada pelo chamador, para evitar escalonamento de privilégios ou falsificação de identidade.

## Semântica de escopo: tenant vs. unidade

### 1. Isolamento de tenant (empresa)

- **Tipo de fronteira:** fronteira de segurança rígida e inegociável.
- **Modelo:** toda entidade com escopo de tenant contém obrigatoriamente `tenant_id UUID NOT NULL REFERENCES tenants(id)`.
- **Aplicação:** toda leitura e escrita via ORM tem escopo de `tenant_id`. Usuários do Tenant A nunca podem consultar, alterar ou observar dados do Tenant B.

### 2. Isolamento de unidade (filial)

- **Tipo de fronteira:** subdivisão operacional/hierárquica dentro de um tenant.
- **Modelo:** as entidades operacionais (ex.: `quotes`, `work_orders`, `inventory_movements`, `financial_transactions`, `products` específicos de uma filial) contêm `unit_id UUID REFERENCES units(id)` além de `tenant_id`.
- **Papéis globais vs. locais:**
  - **Escopo global (todo o tenant):** usuários com papéis de abrangência na empresa inteira (ex.: `Proprietário`, `Gerente Geral`) atuam em todas as unidades do tenant, sem filtro por unidade.
  - **Escopo local (específico da unidade):** usuários atribuídos a uma filial específica (ex.: `Mecânico`, `Atendente da Filial`) atuam estritamente dentro do `unit_id` atribuído.

## Usuários multiunidade e troca de unidade ativa

### Modelagem do relacionamento

Um usuário pode ter papéis diferentes em várias unidades do mesmo tenant, por meio da associação `user_roles`:

- `user_id UUID NOT NULL`
- `role_id UUID NOT NULL`
- `unit_id UUID` *(NULL para papéis globais/de todo o tenant, ou o ID de uma unidade específica para papéis de filial)*

### Contexto da requisição e claims do JWT

Quando um usuário se autentica:

1. O backend emite um JWT assinado contendo:
   - `sub`: ID do usuário
   - `tenantId`: UUID obrigatório do tenant
   - `unitId`: UUID opcional da unidade ativa (presente quando a sessão tem escopo de uma filial específica)
   - `roles` e `permissions`: autoridades concedidas para o contexto ativo.

### Fluxo de troca de unidade ativa

1. Quando um usuário com acesso a várias filiais troca sua unidade ativa no aplicativo cliente:
   - O cliente chama o endpoint de troca de unidade: `POST /api/v1/auth/switch-unit` com `{ "unitId": "<target_unit_uuid>" }`.
   - O backend valida que:
     1. O `unit_id` de destino pertence ao `tenant_id` do usuário.
     2. O usuário tem um papel ativo atribuído para esse `unit_id` (ou tem um papel global no tenant).
   - Se a validação for bem-sucedida, o backend emite um novo JWT com a nova claim `unitId` ativa e as permissões correspondentes.
2. As requisições seguintes carregam o novo token, o que estabelece o `UnitReference` atualizado no `UnitContextHolder`.

## Ciclo de vida do contexto da requisição e modelo de confiança

### Context holders (`ThreadLocal`)

- **`TenantContextHolder`:** guarda o `tenantId` atual e sua `TenantSource`.
- **`UnitContextHolder`:** guarda um `Optional<UnitReference>` que identifica a unidade ativa. As fatias do Core dependem apenas do record identificador `UnitReference(UUID id)`, para evitar acoplamento com os modelos de domínio ([ADR-002](ADR-002-camadas-e-regras-de-dependencia.md)).

### Fontes de confiança do tenant (`TenantSource`)

| Fonte | Estabelecida por | Confiável | Chega ao `ActorContext` / `@TenantId` |
|---|---|---|---|
| `AUTHENTICATED` | `JwtAuthenticationFilter`, a partir da claim `tenantId` verificada no JWT | **Sim** | **Sim** |
| `SYSTEM` | Execução interna no servidor (ex.: onboarding registrando um novo tenant) | **Sim** | **Sim** |
| `REQUESTED` | Header `X-Tenant-ID` enviado pelo chamador | **Não** | **Não** |

### Regras do header de requisição (`X-Tenant-ID`)

1. **Desabilitado nos ambientes implantados:** `gomech.tenancy.trust-request-header` tem valor padrão `false` em `application.yml`, `staging` e `prod`. Somente o profile `local` o habilita, para testes manuais com curl/Postman antes de o login com reconhecimento de tenant estar finalizado.
2. **Escopo de paths restrito:** mesmo quando habilitado, o header só é inspecionado em endpoints pré-autenticação que exigem a seleção de tenant antes da verificação de credenciais (`/api/v1/auth/login`).
3. **Não sobrescreve uma identidade comprovada:** `TenantContextHolder.setRequestedTenant(...)` é rejeitado se já houver um tenant `AUTHENTICATED` ou `SYSTEM` definido.

### Limpeza garantida

O `TenantFilter` é o filtro mais externo da cadeia de requisição (`Ordered.HIGHEST_PRECEDENCE + 10`, executado dentro do `CorrelationIdFilter`). Seu bloco `finally` limpa incondicionalmente o `TenantContextHolder` e o `UnitContextHolder`, garantindo que nenhum contexto de tenant/unidade vaze para as threads reaproveitadas do pool do container.

## Defesa em profundidade: o papel do RLS no PostgreSQL

Enquanto o `@TenantId` do Hibernate faz a primeira filtragem, no nível da aplicação, o **Row Level Security (RLS)** do PostgreSQL é configurado em todas as tabelas de tenant e unidade como segunda camada de defesa (migration Flyway `V3__Enable_Tenant_And_Unit_Row_Level_Security.sql`):

1. **Parâmetros de sessão:** ao obter uma conexão com o banco ou iniciar uma transação, o backend define:
   ```sql
   SET LOCAL app.current_tenant = '<tenant_uuid>';
   SET LOCAL app.current_unit = '<unit_uuid>'; -- opcional, ao operar em uma filial específica
   ```
2. **Policies de RLS do PostgreSQL:**
   - **Policy de isolamento de tenant:**
     ```sql
     CREATE POLICY tenant_isolation_policy ON <table>
         FOR ALL
         USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid)
         WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);
     ```
   - **Policy de isolamento de tenant e unidade:**
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
3. **Objetivo do RLS:**
   - Evitar vazamentos catastróficos de dados em caso de configuração incorreta do ORM, de queries SQL nativas ou de esquecimento do `@TenantId` por parte de quem desenvolve.
   - Restringir ferramentas externas de relatório, BI e agentes text-to-SQL do serviço de IA que se conectam diretamente ao PostgreSQL sob um role de banco restrito.
   - Negar escritas e consultas com unidade divergente quando a unidade ativa estiver definida.

## Alternativas consideradas

### 1. Um banco por tenant

- *Descrição:* um banco PostgreSQL separado para cada oficina.
- *Rejeitada:* complexidade operacional excessiva, esgotamento do pool de conexões e dificuldade de aplicar as migrations Flyway em centenas de pequenas oficinas.

### 2. Um schema por tenant

- *Descrição:* um schema PostgreSQL separado (`CREATE SCHEMA tenant_xxx`) por oficina.
- *Rejeitada:* alto custo de manutenção das migrations, inicialização lenta à medida que o número de tenants cresce e eficiência limitada do pool de conexões.

### 3. Filtragem orientativa no nível da aplicação (modelo legado)

- *Descrição:* repositórios filtrando manualmente por `organization_id` em métodos específicos.
- *Rejeitada:* falha comprovada na base de código legada, com mais de 50 queries vazando dados. Não oferece garantias estruturais.

### 4. RLS como único mecanismo de aplicação

- *Descrição:* depender exclusivamente do RLS do PostgreSQL, sem o `@TenantId` do ORM.
- *Rejeitada:* mais difícil de depurar, causa truncamento silencioso dos resultados sem visibilidade para a aplicação e falha se as variáveis de sessão do pool de conexões forem omitidas.

## Trade-offs

### Benefícios

- **Zero vazamento entre tenants:** a aplicação em duas camadas (ORM + RLS) elimina queries acidentais entre tenants.
- **Eficiência operacional:** um único banco e schema maximizam o aproveitamento do hardware e simplificam as migrations Flyway.
- **Contexto determinístico:** o modelo de confiança explícito impede falsificação via header.
- **Core enxuto:** o Core carrega o contexto de tenant/unidade sem conhecer detalhes das entidades internas dos módulos.

### Custos

- Toda entidade de tenant precisa ter `@TenantId` e `tenant_id`.
- Todos os índices secundários precisam começar por `tenant_id`.
- O pool de conexões exige configurar os parâmetros com `SET LOCAL` a cada transação para que o RLS fique totalmente ativo.

## Consequências

1. **Regras de definição de entidades:** toda tabela pertencente a um tenant deve declarar `tenant_id UUID NOT NULL REFERENCES tenants(id)` e mapear `@TenantId private UUID tenantId;`.
2. **Padrões de índice:** todos os índices simples e compostos em tabelas de tenant devem começar por `tenant_id` ([ADR-012](ADR-012-baseline-de-migrations-postgresql.md)).
3. **Fronteiras dos contratos públicos:** contratos entre módulos usam referências `UUID` e nunca fazem join atravessando fronteiras de tenant ([ADR-002](ADR-002-camadas-e-regras-de-dependencia.md)).
4. **Verificação arquitetural:** testes unitários e de integração verificam que o contexto de tenant é imutável durante a requisição, nunca pode ser falsificado e é limpo ao final.

## Obrigações de teste e testes de referência

### 1. Testes unitários e de fronteira de confiança

- [`TenantTrustBoundaryTest.java`](https://github.com/DeyvidJesus/gomech-backend-v2/blob/master/src/test/java/com/gomech/api/core/security/TenantTrustBoundaryTest.java):
  - Valida que o header `X-Tenant-ID` enviado pelo chamador não sobrescreve um tenant autenticado.
  - Valida que requisições não autenticadas a endpoints de negócio ignoram os headers de tenant.
  - Valida que os contextos de tenant e unidade são limpos em blocos `finally` em todos os formatos de requisição.
- [`TenantContextHolderTest.java`](https://github.com/DeyvidJesus/gomech-backend-v2/blob/master/src/test/java/com/gomech/api/core/tenancy/TenantContextHolderTest.java):
  - Valida a precedência de `AUTHENTICATED` e `SYSTEM` sobre `REQUESTED`.
- [`RequestContextLifecycleTest.java`](https://github.com/DeyvidJesus/gomech-backend-v2/blob/master/src/test/java/com/gomech/api/core/security/RequestContextLifecycleTest.java):
  - Valida o pipeline completo: requisição → `TenantFilter` → `JwtAuthenticationFilter` → `ActorContext`.

### 2. Testes de persistência e concorrência

- [`PersistenceTransactionsAndConcurrencyIT.java`](https://github.com/DeyvidJesus/gomech-backend-v2/blob/master/src/test/java/com/gomech/api/database/PersistenceTransactionsAndConcurrencyIT.java):
  - Valida o isolamento multi-tenant na persistência e os índices únicos parciais (`WHERE deleted_at IS NULL`).

### 3. Testes de integração de RLS

- [`PostgresRlsIsolationIT.java`](https://github.com/DeyvidJesus/gomech-backend-v2/blob/master/src/test/java/com/gomech/api/database/PostgresRlsIsolationIT.java):
  - Valida, sob RLS, o isolamento de tenant, o isolamento de unidade no nível da filial, a visibilidade global, os defaults fail-closed e a rejeição de mutações entre tenants e entre unidades.
