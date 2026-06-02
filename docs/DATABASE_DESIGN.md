# GoMech V2 - Database Design

Este documento detalha a arquitetura do banco de dados relacional (PostgreSQL) para o sistema GoMech V2, baseado no modelo de domínio e nos requisitos arquiteturais de um SaaS multi-tenant. Não inclui scripts SQL ou *migrations*, focando-se no modelo lógico, estratégias e restrições.

---

## 1. Estratégias Globais

### 1.1 Tenant Strategy (Multi-Tenant)
- **Abordagem**: *Shared Database, Shared Schema* (Banco de Dados e Esquema Compartilhados).
- **Isolamento Lógico**: Todas as tabelas que pertencem a uma empresa (com exceção das estáticas de sistema e da própria tabela `tenants`) possuem uma coluna restritiva `tenant_id`.
- **Segurança (RLS)**: O PostgreSQL utilizará **Row Level Security (RLS)**. Cada requisição ao banco injeta o `tenant_id` do usuário logado na sessão do banco. As *Policies* do PostgreSQL garantem que qualquer query (SELECT, UPDATE, DELETE) só atinja as linhas pertencentes àquele `tenant_id`, evitando vazamento de dados mesmo em caso de falha na aplicação.

### 1.2 Unit Strategy (Multi-Unidade)
- **Escopo Operacional**: Para suportar filiais físicas dentro de uma mesma empresa, tabelas operacionais e financeiras possuem a coluna `unit_id` (chave estrangeira para a unidade).
- **Filtro Hierárquico**: O sistema permite visualização "Global" (onde apenas a policy do `tenant_id` filtra os dados) ou "Local" (filtrando adicionalmente por `unit_id`), a depender do escopo da *Role* do usuário que executa a ação.

### 1.3 Soft Delete Strategy
- **Implementação**: Tabelas de cadastros essenciais e com forte relação operacional (ex: `users`, `customers`, `vehicles`, `products`, `suppliers`) implementarão Soft Delete usando uma coluna `deleted_at` (Timestamp). Se o valor for `NULL`, o registro está ativo.
- **Justificativa**: Evita a quebra de integridade referencial. Excluir fisicamente um "Veículo" que possui histórico em "Ordens de Serviço" geraria anomalias contábeis e históricas.
- **Índices Únicos Parciais**: Restrições de unicidade (como placa do veículo ou e-mail de usuário) são implementadas através de índices com a cláusula `WHERE deleted_at IS NULL`, permitindo recadastros futuros.

### 1.4 Audit Strategy
- **Auditoria de Eventos**: Entidades transacionais sofrem auditoria assíncrona gravada na tabela `audit_logs`.
- **Imutabilidade (Append-Only)**: As tabelas `inventory_movements` (livro razão do estoque) e `audit_logs` são projetadas para inserção apenas. Modificações ou deleções diretas não são permitidas via aplicação. Correções no estoque requerem linhas de estorno/ajuste explícitas.

---

## 2. Dicionário de Dados e Relacionamentos

Abaixo constam as tabelas lógicas. As **chaves primárias (PK)** de todas as tabelas, representadas como `id`, devem utilizar o tipo lógico **UUID** visando segurança em URLs e menor previsibilidade em APIs. Todas as entidades contêm também colunas padrão `created_at` e `updated_at`.

### 2.1 Módulo: IAM (Autenticação e Multi-Tenant)

#### Tabela: `tenants`
- **PK**: `id`
- **Campos**: `name`, `cnpj`, `status` (ACTIVE, SUSPENDED, CANCELED).
- **Índices**: Unique em `(cnpj)`.

#### Tabela: `units`
- **PK**: `id`
- **FK**: `tenant_id` -> `tenants(id)`
- **Campos**: `name`, `address`, `phone`, `is_headquarters`.
- **Índices**: `(tenant_id)`.

#### Tabela: `users`
- **PK**: `id`
- **FK**: `tenant_id` -> `tenants(id)`
- **Campos**: `name`, `email`, `password_hash`, `status`, `last_login`, `deleted_at`.
- **Índices**: Unique em `(tenant_id, email)` com *Soft Delete*.

#### Tabela: `roles`
- **PK**: `id`
- **FK**: `tenant_id` -> `tenants(id)` (Pode ser nulo para papéis estáticos de sistema).
- **Campos**: `name`, `description`.

#### Tabela: `permissions`
- **PK**: `id`
- **Campos**: `code` (ex: `OS_READ`), `module`.
- **Índices**: Unique em `(code)`.

#### Tabelas Associativas IAM
- `role_permissions` (PK composta: `role_id`, `permission_id`).
- `user_roles` (PK composta: `user_id`, `role_id`, `unit_id`). O `unit_id` aqui delimita se a *role* se aplica a uma filial específica ou globalmente à empresa.

#### Tabela: `user_sessions`
- **PK**: `id`
- **FK**: `user_id` -> `users(id)`
- **Campos**: `refresh_token`, `expires_at`, `device_info`.
- **Índices**: `(refresh_token)` para buscas rápidas.

### 2.2 Módulo: Billing (Assinaturas SaaS)

#### Tabela: `subscriptions`
- **PK**: `id`
- **FK**: `tenant_id` -> `tenants(id)`
- **Campos**: `plan_name`, `status`, `next_billing_date`, `gateway_subscription_id`.
- **Índices**: Unique em `(tenant_id)`.

#### Tabela: `payments`
- **PK**: `id`
- **FK**: `subscription_id` -> `subscriptions(id)`
- **Campos**: `amount`, `status`, `payment_method`, `due_date`, `paid_at`.

### 2.3 Módulo: CRM

#### Tabela: `customers`
- **PK**: `id`
- **FK**: `tenant_id` -> `tenants(id)`
- **Campos**: `name`, `document` (CPF/CNPJ), `phone`, `email`, `address`, `deleted_at`.
- **Índices**: Unique em `(tenant_id, document)` com *Soft Delete*.

#### Tabela: `vehicles`
- **PK**: `id`
- **FK**: `tenant_id` -> `tenants(id)`, `customer_id` -> `customers(id)`
- **Campos**: `license_plate`, `brand`, `model`, `year`, `vin` (chassi), `current_mileage`, `deleted_at`.
- **Índices**: Unique em `(tenant_id, license_plate)` com *Soft Delete*.

### 2.4 Módulo: Operations

#### Tabela: `quotes` (Orçamentos)
- **PK**: `id`
- **FK**: `tenant_id` -> `tenants(id)`, `unit_id` -> `units(id)`, `vehicle_id` -> `vehicles(id)`
- **Campos**: `status`, `total_amount`, `valid_until`.
- **Índices**: `(tenant_id, status)`, `(tenant_id, unit_id)`.

#### Tabela: `work_orders` (Ordens de Serviço)
- **PK**: `id`
- **FK**: `tenant_id` -> `tenants(id)`, `unit_id` -> `units(id)`, `quote_id` -> `quotes(id)` (Nulável), `vehicle_id` -> `vehicles(id)`, `mechanic_user_id` -> `users(id)`
- **Campos**: `status`, `start_date`, `end_date`, `total_amount`, `technical_notes`.
- **Índices**: `(tenant_id, status)`, `(tenant_id, unit_id, mechanic_user_id)`.

### 2.5 Módulo: Inventory (Estoque)

#### Tabela: `suppliers`
- **PK**: `id`
- **FK**: `tenant_id` -> `tenants(id)`
- **Campos**: `name`, `cnpj`, `contact_name`, `phone`, `email`, `deleted_at`.

#### Tabela: `products`
- **PK**: `id`
- **FK**: `tenant_id` -> `tenants(id)`, `unit_id` -> `units(id)` (Nulável para peças globais), `supplier_id` -> `suppliers(id)`
- **Campos**: `sku_code`, `name`, `cost_price`, `selling_price`, `min_stock`, `current_stock_calculated`, `deleted_at`.
- **Índices**: Unique em `(tenant_id, sku_code)` com *Soft Delete*.

#### Tabela: `inventory_movements` (Append-Only)
- **PK**: `id`
- **FK**: `tenant_id` -> `tenants(id)`, `unit_id` -> `units(id)`, `product_id` -> `products(id)`, `user_id` -> `users(id)`
- **Campos**: `type` (IN/OUT), `quantity`, `reason` (PURCHASE, WORK_ORDER, ADJUSTMENT), `reference_id` (ID genérico ligando à OS ou NF).
- **Índices**: `(tenant_id, product_id, created_at)`.

### 2.6 Módulo: Finance & Auditoria

#### Tabela: `financial_transactions`
- **PK**: `id`
- **FK**: `tenant_id` -> `tenants(id)`, `unit_id` -> `units(id)`
- **Campos**: `type` (INCOME/EXPENSE), `category`, `amount`, `due_date`, `paid_date`, `status`, `origin_type` (WORK_ORDER, MANUAL), `origin_id`.
- **Índices**: `(tenant_id, due_date)`, `(tenant_id, status)`.

#### Tabela: `audit_logs` (Append-Only)
- **PK**: `id`
- **FK**: `tenant_id` -> `tenants(id)`, `user_id` -> `users(id)`
- **Campos**: `entity_name`, `entity_id`, `action`, `old_state_json` (tipo JSONB), `new_state_json` (tipo JSONB), `ip_address`.
- **Índices**: `(tenant_id, entity_name, entity_id)` otimizando buscas de log por registro específico.

---

## 3. Chaves e Composição de Índices

O banco de dados relacional de um sistema B2B em nuvem opera melhor quando as restrições lógicas suportam as físicas.
- **Prefixação Multi-Tenant**: Virtualmente todos os índices secundários e chaves únicas devem iniciar com a coluna `tenant_id` no índice B-Tree. Exemplo: Para garantir a unicidade de e-mail e facilitar o login, criar `CREATE UNIQUE INDEX idx_user_email ON users (tenant_id, email) WHERE deleted_at IS NULL`.
- **Integridade via RLS vs FK**: Mesmo com Row Level Security (RLS) mascarando visibilidade indevida em runtime, Chaves Estrangeiras (Foreign Keys) duras do PostgreSQL são obrigatórias entre tabelas para manter a saúde e corretude dos dados estruturais de cada empresa.
