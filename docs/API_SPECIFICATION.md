# GoMech V2 - Especificação de APIs

Este documento apresenta a especificação inicial das rotas da API RESTful para os módulos do sistema GoMech V2. Todas as requisições (com exceção das públicas, como o login) exigem o envio de um token válido via cabeçalho HTTP: `Authorization: Bearer <JWT>`.

A estrutura das respostas padroniza falhas utilizando o modelo RFC 7807 (Problem Details).

---

## 1. Módulo IAM (Identidade e Acesso)

### Autenticação (Login)
* **Endpoint:** `/api/v1/auth/login`
* **Método:** `POST`
* **Permissões:** `(Público)`
* **Request:** JSON contendo credenciais.
  ```json
  { "email": "admin@oficina.com", "password": "senha" }
  ```
* **Validações:** `email` válido, `password` obrigatória. Bloqueio por excesso de tentativas.
* **Response (200 OK):**
  ```json
  {
    "accessToken": "eyJ...",
    "refreshToken": "uuid-...",
    "expiresIn": 900
  }
  ```

### Gerenciamento de Usuários
* **Endpoint:** `/api/v1/users`
* **Método:** `POST`
* **Permissões:** `users:create`
* **Request:**
  ```json
  {
    "name": "João Mecânico",
    "email": "joao@oficina.com",
    "password": "senha_temporaria",
    "roles": [{"roleId": "uuid-role", "unitId": "uuid-unit"}]
  }
  ```
* **Validações:** `email` em formato válido e não repetido no tenant.
* **Response (201 Created):** Retorna os dados do usuário recém-criado sem a senha.

---

## 2. Módulo CRM (Clientes e Veículos)

### Cadastro de Clientes
* **Endpoint:** `/api/v1/customers`
* **Método:** `POST`
* **Permissões:** `crm:create`
* **Request:**
  ```json
  {
    "name": "Maria Silva",
    "document": "123.456.789-00",
    "phone": "11999999999",
    "email": "maria@email.com"
  }
  ```
* **Validações:** Validador customizado de CPF/CNPJ. O documento deve ser único para a empresa (tenant).
* **Response (201 Created):** Retorna as informações do cliente e o seu UUID gerado.

### Listagem de Veículos (Com Filtros)
* **Endpoint:** `/api/v1/vehicles`
* **Método:** `GET`
* **Permissões:** `crm:read`
* **Request:** Parâmetros de Query (ex: `?licensePlate=ABC1234&customerId=uuid`)
* **Response (200 OK):**
  ```json
  {
    "content": [
      {
        "id": "uuid...",
        "licensePlate": "ABC1234",
        "brand": "Ford",
        "model": "Fiesta",
        "customerId": "uuid...",
        "customerName": "Maria Silva"
      }
    ],
    "page": 0,
    "totalElements": 1
  }
  ```

---

## 3. Módulo Operations (Orçamentos e Ordens de Serviço)

### Criar Orçamento (Quote)
* **Endpoint:** `/api/v1/quotes`
* **Método:** `POST`
* **Permissões:** `operations:create`
* **Request:**
  ```json
  {
    "unitId": "uuid-unit",
    "vehicleId": "uuid-vehicle",
    "items": [
      { "productId": "uuid-prod", "quantity": 2, "unitPrice": 50.00, "type": "PART" },
      { "description": "Mão de Obra", "quantity": 1, "unitPrice": 150.00, "type": "LABOR" }
    ],
    "validUntil": "2026-10-01T00:00:00Z"
  }
  ```
* **Validações:** O veículo e unidade devem existir e o usuário precisa ter escopo de acesso à unidade enviada. Estoque não é afetado aqui.
* **Response (201 Created):** Retorna o ID do orçamento e `totalAmount` calculado.

### Converter Orçamento em Ordem de Serviço (Aprovação)
* **Endpoint:** `/api/v1/quotes/{id}/approve`
* **Método:** `POST`
* **Permissões:** `operations:approve`
* **Request:** Vazio ou notas de aprovação do cliente.
* **Validações:** O orçamento precisa estar em status `PENDING_APPROVAL`.
* **Response (200 OK):** Retorna o objeto da recém-criada `WorkOrder` atrelada.

### Atualizar Status da OS
* **Endpoint:** `/api/v1/work-orders/{id}/status`
* **Método:** `PUT`
* **Permissões:** `operations:update`
* **Request:**
  ```json
  { "status": "COMPLETED", "mechanicNotes": "Freio trocado." }
  ```
* **Validações:** Transição de status válida (não é possível retroceder de CANCELADO para ABERTO). Se `status` = `COMPLETED`, o sistema injeta assincronamente a baixa de estoque e o envio pro financeiro.
* **Response (200 OK):** Os dados da OS atualizada.

---

## 4. Módulo Inventory (Estoque)

### Criar Produto / Peça
* **Endpoint:** `/api/v1/products`
* **Método:** `POST`
* **Permissões:** `inventory:create`
* **Request:**
  ```json
  {
    "skuCode": "OLEO-5W30",
    "name": "Óleo Sintético 5W30",
    "costPrice": 35.00,
    "sellingPrice": 65.00,
    "minStock": 10
  }
  ```
* **Validações:** `skuCode` deve ser único na empresa. Preços devem ser `> 0`.
* **Response (201 Created):** Retorna a peça cadastrada.

### Lançar Movimentação de Estoque Manual (Ajuste/Compra)
* **Endpoint:** `/api/v1/inventory/movements`
* **Método:** `POST`
* **Permissões:** `inventory:adjust`
* **Request:**
  ```json
  {
    "productId": "uuid-prod",
    "unitId": "uuid-unit",
    "type": "IN",
    "quantity": 20,
    "reason": "PURCHASE"
  }
  ```
* **Validações:** Se for `OUT`, o saldo atual da unidade não pode ficar negativo (dependendo da regra de negócio).
* **Response (201 Created):** Registro *append-only* gravado. O saldo calculado do produto é atualizado de forma síncrona.

---

## 5. Módulo Finance (Financeiro)

### Listar Transações do Fluxo de Caixa
* **Endpoint:** `/api/v1/financial-transactions`
* **Método:** `GET`
* **Permissões:** `finance:read`
* **Request:** Filtros de data de vencimento e status via Querystring.
  `?startDate=2026-06-01&endDate=2026-06-30&status=PENDING`
* **Response (200 OK):** Lista paginada das transações com totalizadores no header ou payload.

### Dar Baixa em Transação (Recebimento / Pagamento)
* **Endpoint:** `/api/v1/financial-transactions/{id}/pay`
* **Método:** `PUT`
* **Permissões:** `finance:pay`
* **Request:**
  ```json
  {
    "paidDate": "2026-06-01T14:00:00Z",
    "paymentMethod": "PIX"
  }
  ```
* **Validações:** Só pode dar baixa se o status for `PENDING`. Data de pagamento não pode ser no futuro distante.
* **Response (200 OK):** Transação com status `PAID`.

---

## 6. Padrão Global de Erros (RFC 7807)

Todas as APIs com falhas de validação de negócios, entrada de dados incorretas ou ausência de permissões retornarão este padrão de erro.

**Response (422 Unprocessable Entity - Validação):**
```json
{
  "type": "about:blank",
  "title": "Validation Failed",
  "status": 422,
  "detail": "Input validation failed for some parameters.",
  "instance": "/api/v1/customers",
  "invalidParams": [
    {
      "name": "document",
      "reason": "must be a valid CPF or CNPJ format"
    }
  ]
}
```

**Response (403 Forbidden - Falta de Permissão):**
```json
{
  "type": "https://gomech.com/docs/errors/forbidden",
  "title": "Access Denied",
  "status": 403,
  "detail": "Você não possui a permissão 'operations:update' requerida para esta ação.",
  "instance": "/api/v1/work-orders/uuid/status"
}
```
