# Modelo de Domínio - GoMech V2

Este documento mapeia todas as entidades principais do sistema GoMech V2, definindo seus objetivos, responsabilidades, campos, relacionamentos e regras de negócio.

---

## 1. IAM, Autenticação e Multi-Tenant

### Entidade: Tenant
* **Objetivo**: Representar a empresa/oficina contratante da plataforma (o locatário no modelo SaaS).
* **Responsabilidades**: Isolar dados, agrupar unidades físicas e atuar como raiz de faturamento da assinatura.
* **Campos principais**: `id`, `name`, `cnpj`, `status` (ACTIVE, SUSPENDED, CANCELED), `created_at`.
* **Relacionamentos**:
  * `1:N` com Unidades (`Unit`)
  * `1:1` com Assinatura (`Subscription`)
  * `1:N` com todos os dados gerados pela empresa.
* **Regras de negócio**: Os dados de um tenant jamais podem ser acessados por usuários de outro tenant (Isolamento rígido lógico via RLS no banco). Se o status estiver suspenso (por falta de pagamento, por exemplo), nenhum usuário daquele tenant pode usar o sistema.
* **Dependências**: Nenhuma (é a entidade raiz do sistema multilocatário).

### Entidade: Unit
* **Objetivo**: Representar uma unidade física (matriz ou filial) de uma empresa.
* **Responsabilidades**: Segregar operações locais, como estoque físico específico, agenda local e fluxo de caixa de balcão.
* **Campos principais**: `id`, `tenant_id`, `name`, `address`, `phone`, `is_headquarters`.
* **Relacionamentos**:
  * `N:1` com `Tenant`
  * `1:N` com Usuários (papéis de acesso por unidade)
  * `1:N` com Estoque, Ordens de Serviço, Transações Financeiras (como centro de custo).
* **Regras de negócio**: Todo Tenant deve ter no mínimo uma Unit criada (a Matriz). Operações do dia a dia do mecânico ou atendente ocorrem sempre vinculadas ao escopo de uma Unit.
* **Dependências**: Depende de `Tenant`.

### Entidade: User
* **Objetivo**: Representar um operador do sistema (proprietário, mecânico, gerente, etc.).
* **Responsabilidades**: Autenticar no sistema e executar operações sob a permissão concedida.
* **Campos principais**: `id`, `tenant_id`, `name`, `email`, `password_hash`, `status`, `last_login`.
* **Relacionamentos**:
  * `N:1` com `Tenant`
  * `N:M` com `Role` (Cargos/Papéis vinculados também ao contexto de uma `Unit`)
* **Regras de negócio**: Um usuário pertence a um único Tenant. O e-mail deve ser único para garantir que a autenticação recupere o Tenant correto.
* **Dependências**: Depende de `Tenant`.

### Entidade: Role
* **Objetivo**: Agrupar permissões em um perfil de acesso (ex: "Gerente", "Mecânico Padrão").
* **Responsabilidades**: Facilitar a gestão de acessos em massa, evitando atribuir permissões individualmente por usuário.
* **Campos principais**: `id`, `tenant_id` (nulo para roles padrão do sistema), `name`, `description`.
* **Relacionamentos**:
  * `N:M` com `Permission`
  * `1:N` com `User`
* **Regras de negócio**: Cargos globais gerados pelo sistema não podem ser editados. Administradores do Tenant podem criar "Roles" customizadas restritas ao próprio Tenant.
* **Dependências**: Depende de `Tenant` (somente se for uma role customizada).

### Entidade: Permission
* **Objetivo**: Representar uma ação atômica e validável na API (ex: `os:create`, `finance:delete`).
* **Responsabilidades**: Funcionar como a trava de segurança base no backend.
* **Campos principais**: `id`, `code` (ex: `INVENTORY_READ`), `module` (ex: `INVENTORY`).
* **Relacionamentos**:
  * `N:M` com `Role`.
* **Regras de negócio**: Permissões são entidades imutáveis injetadas estaticamente na base de dados durante o deploy. Usuários não criam permissões.
* **Dependências**: Nenhuma (estática).

---

## 2. Assinatura e Pagamentos SaaS (Billing)

### Entidade: Subscription
* **Objetivo**: Controlar o plano de assinatura da plataforma GoMech pela oficina.
* **Responsabilidades**: Determinar limites de uso da plataforma e gerir o ciclo de vida.
* **Campos principais**: `id`, `tenant_id`, `plan_name` (ex: Basic, Pro, Enterprise), `status` (ACTIVE, PAST_DUE, CANCELED), `next_billing_date`, `gateway_subscription_id` (PagArme).
* **Relacionamentos**:
  * `1:1` com `Tenant`
  * `1:N` com `Payment`
* **Regras de negócio**: Caso uma fatura atrase e passe da tolerância, a Subscription muda para PAST_DUE e pode bloquear o Tenant. Alterações de plano (Upgrades/Downgrades) aplicam novos limites imediatamente.
* **Dependências**: Depende de `Tenant`.

### Entidade: Payment
* **Objetivo**: Registrar uma cobrança e transação mensal/anual do plano SaaS (relacionamento interno GoMech <> Cliente).
* **Responsabilidades**: Rastrear pagamentos do gateway PagArme.
* **Campos principais**: `id`, `subscription_id`, `amount`, `status` (PENDING, PAID, FAILED), `payment_method` (CREDIT_CARD, PIX), `due_date`, `paid_at`.
* **Relacionamentos**:
  * `N:1` com `Subscription`
* **Regras de negócio**: O pagamento é reconciliado de forma automatizada via Webhooks. Quando PAID, ele renova a `next_billing_date` da Assinatura.
* **Dependências**: Depende de `Subscription`.

---

## 3. CRM (Clientes e Veículos)

### Entidade: Customer
* **Objetivo**: Representar o cliente final da oficina (quem paga a conta).
* **Responsabilidades**: Armazenar dados de contato, identificação e histórico.
* **Campos principais**: `id`, `tenant_id`, `name`, `document` (CPF/CNPJ), `phone`, `email`, `address`.
* **Relacionamentos**:
  * `1:N` com `Vehicle`
  * `1:N` com `Quote` e `WorkOrder`
* **Regras de negócio**: O documento (CPF/CNPJ) deve ser único dentro do Tenant.
* **Dependências**: Depende de `Tenant`.

### Entidade: Vehicle
* **Objetivo**: O "paciente" da oficina. Veículo que receberá a manutenção.
* **Responsabilidades**: Armazenar os dados de placa, chassi e histórico de rodagem.
* **Campos principais**: `id`, `tenant_id`, `customer_id`, `license_plate`, `brand`, `model`, `year`, `vin` (Chassi), `current_mileage`.
* **Relacionamentos**:
  * `N:1` com `Customer`
  * `1:N` com `WorkOrder`
* **Regras de negócio**: A placa deve ser única por Tenant. A `current_mileage` (quilometragem) é sobrescrita e atualizada sempre que uma nova OS for concluída com a quilometragem de entrada mais recente.
* **Dependências**: Depende de `Customer`.

---

## 4. Operações (Core)

### Entidade: Quote (Orçamento)
* **Objetivo**: Proposta comercial de serviços e peças apresentada ao cliente.
* **Responsabilidades**: Negociação e fluxo de aprovação pré-serviço.
* **Campos principais**: `id`, `tenant_id`, `unit_id`, `vehicle_id`, `status` (DRAFT, PENDING_APPROVAL, APPROVED, REJECTED), `total_amount`, `valid_until`.
* **Relacionamentos**:
  * `N:1` com `Vehicle` (logo, `Customer`)
  * `1:1` com `WorkOrder` (uma vez aprovado, gera uma OS)
* **Regras de negócio**: O Orçamento fica bloqueado para edição se for enviado (`PENDING_APPROVAL`) ou se for respondido (`APPROVED` ou `REJECTED`). Sua aprovação gera diretamente uma `WorkOrder`.
* **Dependências**: Depende de `Vehicle` e `Unit`.

### Entidade: WorkOrder (Ordem de Serviço - OS)
* **Objetivo**: Orquestrar a execução técnica e de peças no veículo.
* **Responsabilidades**: Monitorar andamento e alocação da equipe técnica.
* **Campos principais**: `id`, `tenant_id`, `unit_id`, `quote_id`, `vehicle_id`, `mechanic_user_id`, `status` (PLANNED, IN_PROGRESS, WAITING_PARTS, COMPLETED, CANCELED), `start_date`, `end_date`, `total_amount`, `technical_notes`.
* **Relacionamentos**:
  * `N:1` com `Vehicle`, `Quote`, `User` (Mecânico)
  * `1:N` com `InventoryMovement` (consumo de peças)
  * `1:N` com `FinancialTransaction` (faturamento/receita gerada)
* **Regras de negócio**: 
  - Mudar o status para `IN_PROGRESS` indica que o veículo está na rampa/box de atendimento.
  - Mudar para `COMPLETED` finaliza o processo: realiza a baixa no estoque fisicamente (InventoryMovement) para as peças orçadas e gera a conta a receber (FinancialTransaction).
* **Dependências**: Depende de `Vehicle`, `Unit`, `User`.

---

## 5. Estoque

### Entidade: Product (Produto/Peça)
* **Objetivo**: Cadastro base do insumo, ferramenta ou peça revendida pela oficina.
* **Responsabilidades**: Controle de catálogo, preços e limiares de estoque crítico.
* **Campos principais**: `id`, `tenant_id`, `unit_id` (se local) ou global, `sku_code`, `name`, `cost_price`, `selling_price`, `min_stock`, `current_stock_calculated`.
* **Relacionamentos**:
  * `N:1` com `Supplier`
  * `1:N` com `InventoryMovement`
* **Regras de negócio**: O `current_stock_calculated` não é apenas um número editável; ele deve espelhar sempre a soma matemática de todo histórico do `InventoryMovement`. Alertas são gerados caso atinja o `min_stock`.
* **Dependências**: Depende de `Tenant` e (opcionalmente) `Supplier`.

### Entidade: Supplier (Fornecedor)
* **Objetivo**: Cadastro do fornecedor de autopeças.
* **Responsabilidades**: Centralizar informações de contato para reposição de peças.
* **Campos principais**: `id`, `tenant_id`, `name`, `cnpj`, `contact_name`, `phone`, `email`.
* **Relacionamentos**:
  * `1:N` com `Product`
* **Regras de negócio**: Facilitar o agrupamento de compras e emissão de requisições baseadas no estoque mínimo.
* **Dependências**: Depende de `Tenant`.

### Entidade: InventoryMovement
* **Objetivo**: Livro razão do estoque. Registro imutável e transacional de entradas/saídas de cada unidade da peça.
* **Responsabilidades**: Garantir a auditoria do que entrou e saiu.
* **Campos principais**: `id`, `tenant_id`, `unit_id`, `product_id`, `type` (IN, OUT), `quantity`, `reason` (PURCHASE, WORK_ORDER_CONSUMPTION, MANUAL_ADJUSTMENT), `reference_id` (ID da NF ou ID da OS), `created_at`.
* **Relacionamentos**:
  * `N:1` com `Product`, `WorkOrder`, `User` (quem deu baixa)
* **Regras de negócio**: Registros são puramente inseridos (*append-only*). Se uma OS for cancelada após o fechamento, é lançada uma movimentação de estorno (`IN`) em vez de deletar a movimentação originária de `OUT`.
* **Dependências**: Depende de `Product` e de instâncias de origem como `WorkOrder`.

---

## 6. Financeiro e Auditoria

### Entidade: FinancialTransaction (Transação Financeira)
* **Objetivo**: Registrar eventos de fluxo de caixa gerando receitas ou despesas.
* **Responsabilidades**: Alimentar DRE e gestão de Contas a Pagar / Receber.
* **Campos principais**: `id`, `tenant_id`, `unit_id`, `type` (INCOME, EXPENSE), `category` (ex: "Serviço", "Peça", "Aluguel", "Folha de Pagamento"), `amount`, `due_date`, `paid_date`, `status` (PENDING, PAID, CANCELED), `origin_type` (WORK_ORDER, PURCHASE, MANUAL), `origin_id`.
* **Relacionamentos**:
  * `N:1` com `Unit` e indiretamente referenciando entidades raiz como `WorkOrder`.
* **Regras de negócio**: Transações geradas via `WorkOrder` só podem ser editadas ou canceladas se a OS correspondente sofrer alteração. Transações manuais (ex: conta de luz) são livremente administradas.
* **Dependências**: Depende de `Unit`.

### Entidade: AuditLog
* **Objetivo**: Fornecer a rastreabilidade total (Auditoria de Ações Críticas).
* **Responsabilidades**: Monitorar e gravar comportamentos sensíveis da plataforma.
* **Campos principais**: `id`, `tenant_id`, `user_id`, `entity_name` (ex: "WORK_ORDER"), `entity_id`, `action` (CREATE, UPDATE, DELETE, CANCEL), `old_state_json`, `new_state_json`, `ip_address`, `created_at`.
* **Relacionamentos**:
  * `N:1` com `User` e `Tenant`.
* **Regras de negócio**: Tabela de crescimento vertiginoso (Write-heavy). Os dados são imutáveis e devem ser processados de forma assíncrona (ex: via Eventos/Filas ou *Spring Data Envers*) para evitar gargalos de I/O na requisição do usuário.
* **Dependências**: Depende de `Tenant` e `User`.
