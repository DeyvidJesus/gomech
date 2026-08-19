# GoMech V2 - Guia Completo de Implementação Frontend & Integração com Backend

> **Versão:** 2.0.0  
> **Público-alvo:** Engenheiros Frontend e Agentes de IA (Google AI Studio / Codex)  
> **URL Base da API Backend:** `http://localhost:8080/api/v1` (configurável via `VITE_API_URL`)  
> **Design System de Referência:** `stitch_gomech_enterprise_design_system` (Tema *Mechanical Precision*)  
> **Padrões Arquiteturais:** Multi-tenancy RLS (ADR-001), Modularidade (ADR-002), RBAC/PBAC (ADR-003), REST Conventions RFC 7807 (ADR-004), Token Rotation (ADR-005).

---

## 1. Visão Geral da Stack do Frontend

A aplicação frontend do GoMech V2 é construída com as seguintes tecnologias e padrões:

| Camada / Função | Tecnologia | Descrição & Boas Práticas |
| :--- | :--- | :--- |
| **Core & Framework** | React 19 + TypeScript + Vite | SPA rápida e fortemente tipada. |
| **Roteamento** | TanStack Router (`@tanstack/react-router`) | Rotas tipadas baseadas em arquivos em `src/routes/`. |
| **Server State & Cache** | TanStack Query (`@tanstack/react-query`) | Gerenciamento de cache, refetching, queries e mutations. |
| **Client State** | Zustand (`zustand/middleware`) | Estado global leve (autenticação, unidade ativa, tema). |
| **Cliente HTTP** | Axios | Instância configurada com interceptors para injeção de JWT e renovação automática de Refresh Token. |
| **Estilização** | TailwindCSS v4 + CSS Tokens | Baseado nos tokens de cores e tipografia de `Mechanical Precision`. |
| **Ícones** | Lucide React / Material Symbols | Ícones consistentes e semânticos. |
| **Formulários & Validação** | React Hook Form + Zod | Validação client-side alinhada com as regras do backend. |

---

## 2. Design System: *Mechanical Precision*

Os tokens de design estão definidos em [`stitch_gomech_enterprise_design_system/mechanical_precision/DESIGN.md`](file:///home/deyvid/Documents/work/gomech-project/gomech/stitch_gomech_enterprise_design_system/mechanical_precision/DESIGN.md).

### 2.1 Paleta de Cores Principais
- **Primary (Automotive Rust/Amber)**:
  - Base: `#a33e00` (`primary`)
  - Container / Destaque: `#ff6500` (`primary-container`)
  - On-Primary: `#ffffff`
- **Surface & Background**:
  - Background: `#fff8f6`
  - Surface: `#fff8f6`
  - Surface Container: `#ffe9e2`
  - Surface Container High: `#fee2d8`
  - On-Surface (Texto principal): `#271812`
  - On-Surface Variant (Texto secundário): `#5a4136`
- **Secondary (Steel Slate / Engenharia)**:
  - Base: `#555f6f`
  - Container: `#d6e0f3`
- **Tertiary (Operacional / Sucesso)**:
  - Base: `#006e2f`
  - Container: `#00ad4e`
- **Status de Diagnóstico & Checklist**:
  - `OK` / Conforme: `#006e2f` (Verde)
  - `ATTENTION` / Atenção: `#d97706` (Âmbar/Laranja)
  - `CRITICAL` / Crítico: `#ba1a1a` (Vermelho)
  - `NOT_APPLICABLE`: `#555f6f` (Cinza)

### 2.2 Tipografia
- **Títulos & Display**: `Manrope` (`font-weight: 600, 700`)
- **Corpo & Rótulos**: `Inter` (`font-weight: 400, 500, 600`)

---

## 3. Matriz de Mapeamento: Telas do Stitch x Rotas x Backend

Abaixo está o mapeamento de **todas as 36 telas** criadas no Stitch para as rotas da aplicação frontend e seus respectivos endpoints no backend:

| Pasta no Stitch (`code.html` + `screen.png`) | Rota no Frontend (TanStack Router) | Módulo Backend | Status do Backend | Endpoints Utilizados |
| :--- | :--- | :--- | :--- | :--- |
| `autentica_o_login` | `/login` | IAM | ✅ Entregue | `POST /api/v1/auth/login`<br>`GET /api/v1/auth/oauth/google/authorize`<br>`POST /api/v1/auth/oauth/google/callback` |
| `autentica_o_cadastro`<br>`autentica_o_cadastro_fluxo_atualizado` | `/register` | IAM | ✅ Entregue | `POST /api/v1/auth/register` |
| `onboarding_dados_da_oficina` | `/onboarding/workshop` | IAM | ✅ Entregue | `POST /api/v1/auth/register` |
| `onboarding_sele_o_de_plano` | `/onboarding/plans` | Billing | ✅ Entregue | `GET /api/v1/billing/plans` |
| `dashboard_principal` | `/dashboard` | Core / IAM | ✅ Entregue | Agregação de dados do usuário, unidade ativa, atalhos de agendamento e clientes |
| `configura_es_perfil_do_usu_rio` | `/settings/profile` | IAM | ✅ Entregue | `GET /api/v1/auth/sessions`<br>`DELETE /api/v1/auth/sessions/{id}`<br>`POST /api/v1/auth/switch-unit` |
| `administra_o_configura_es_da_empresa` | `/admin/company` | IAM | ✅ Entregue | `GET /api/v1/units`<br>`POST /api/v1/units`<br>`GET /api/v1/units/{id}` |
| `administra_o_gest_o_de_usu_rios` | `/admin/users` | IAM | ✅ Entregue | `GET /api/v1/users`<br>`POST /api/v1/users`<br>`GET /api/v1/users/{id}`<br>`POST /api/v1/users/{id}/roles` |
| `administra_o_pap_is_e_permiss_es` | `/admin/roles` | IAM | ✅ Entregue | `GET /api/v1/roles`<br>`GET /api/v1/roles/permissions`<br>`POST /api/v1/roles` |
| `administra_o_gest_o_de_assinatura` | `/admin/subscription` | Billing | ✅ Entregue | Gestão de plano, cotas e consumo |
| `administra_o_configura_es_gerais` | `/admin/settings` | IAM | ✅ Entregue | Preferências da oficina e unidades |
| `clientes_listagem` | `/crm/customers` | CRM | ✅ Entregue | `GET /api/v1/customers?search=...&page=...&size=...`<br>`DELETE /api/v1/customers/{id}` |
| `clientes_novo_cadastro` | `/crm/customers/new`<br>`/crm/customers/$id` | CRM | ✅ Entregue | `POST /api/v1/customers`<br>`GET /api/v1/customers/{id}`<br>`PUT /api/v1/customers/{id}` |
| `ve_culos_listagem` | `/crm/vehicles` | CRM | ✅ Entregue | `GET /api/v1/vehicles?search=...&customerId=...&page=...&size=...`<br>`DELETE /api/v1/vehicles/{id}` |
| `ve_culos_novo_cadastro` | `/crm/vehicles/new`<br>`/crm/vehicles/$id` | CRM | ✅ Entregue | `POST /api/v1/vehicles`<br>`GET /api/v1/vehicles/{id}`<br>`PUT /api/v1/vehicles/{id}` |
| `agenda_calend_rio_mensal` | `/operations/scheduling/calendar` | Operations | ✅ Entregue | `GET /api/v1/appointments/calendar?from=...&to=...&unitId=...` |
| `agenda_check_in_di_rio` | `/operations/scheduling/checkin` | Operations | ✅ Entregue | `GET /api/v1/appointments?date=...`<br>`PUT /api/v1/appointments/{id}/status` |
| `agenda_novo_agendamento` | `/operations/scheduling/new` | Operations | ✅ Entregue | `POST /api/v1/appointments`<br>`GET /api/v1/customers`<br>`GET /api/v1/vehicles` |
| `mechanical_precision` (Checklist / Inspeções) | `/operations/inspections`<br>`/operations/inspections/$id` | Operations | ✅ Entregue | `POST /api/v1/inspections`<br>`GET /api/v1/inspections`<br>`GET /api/v1/inspections/{id}`<br>`PUT /api/v1/inspections/{id}/items`<br>`POST /api/v1/inspections/{id}/complete`<br>`DELETE /api/v1/inspections/{id}` |
| `or_amentos_listagem` | `/operations/quotes` | Operations | ✅ Entregue | `GET /api/v1/quotes?customerId=...&vehicleId=...&status=...`<br>`DELETE /api/v1/quotes/{id}` |
| `or_amentos_novo_or_amento` | `/operations/quotes/new`<br>`/operations/quotes/$id` | Operations | ✅ Entregue | `POST /api/v1/quotes`<br>`POST /api/v1/quotes/from-inspection/{id}`<br>`GET /api/v1/quotes/{id}`<br>`PUT /api/v1/quotes/{id}/items` |
| `portal_do_cliente_aprova_o_de_or_amento` | `/portal/quotes/$id` | Operations | ✅ Entregue | `POST /api/v1/quotes/{id}/customer-decision`<br>`POST /api/v1/quotes/{id}/approve`<br>`POST /api/v1/quotes/{id}/send` |
| `ordens_de_servi_o_listagem` | `/operations/work-orders` | Operations | ✅ Entregue | `GET /api/v1/work-orders?customerId=...&vehicleId=...&status=...`<br>`DELETE /api/v1/work-orders/{id}` |
| `ordens_de_servi_o_kanban` | `/operations/work-orders/kanban` | Operations | ✅ Entregue | `GET /api/v1/work-orders/kanban?unitId=...`<br>`PUT /api/v1/work-orders/{id}/status` |
| `ordens_de_servi_o_detalhes` | `/operations/work-orders/$id`<br>`/operations/work-orders/new` | Operations | ✅ Entregue | `POST /api/v1/work-orders`<br>`POST /api/v1/work-orders/from-quote/{quoteId}`<br>`GET /api/v1/work-orders/{id}`<br>`PUT /api/v1/work-orders/{id}`<br>`PUT /api/v1/work-orders/{id}/items`<br>`POST /api/v1/work-orders/{id}/complete` |
| `estoque_listagem_de_produtos` | `/inventory/products` | Inventory | ⏳ Fase 5 | `GET /api/v1/products` |
| `estoque_cadastro_de_produto` | `/inventory/products/new` | Inventory | ⏳ Fase 5 | `POST /api/v1/products` |
| `estoque_movimenta_es` | `/inventory/movements` | Inventory | ⏳ Fase 5 | `GET /api/v1/inventory/movements` |
| `financeiro_dashboard` | `/finance/dashboard` | Finance | ⏳ Fase 6 | `GET /api/v1/finance/dashboard` |
| `financeiro_fluxo_de_caixa` | `/finance/cash-flow` | Finance | ⏳ Fase 6 | `GET /api/v1/finance/cash-flow` |
| `financeiro_contas_a_pagar` | `/finance/payables` | Finance | ⏳ Fase 6 | `GET /api/v1/finance/payables` |
| `financeiro_contas_a_receber` | `/finance/receivables` | Finance | ⏳ Fase 6 | `GET /api/v1/finance/receivables` |
| `pagamentos_checkout` | `/billing/checkout` | Billing | ⏳ Fase 7 | `POST /api/v1/billing/checkout` |
| `pagamentos_sucesso` | `/billing/success` | Billing | ⏳ Fase 7 | Confirmação de assinatura |
| `ai_insights_dashboard_preditivo` | `/ai/insights` | AI / Analytics | ⏳ Fase 8 | Painel de diagnósticos e frotas |

---

## 4. Detalhamento de Implementação dos Módulos Entregues

---

### 4.1 Módulo IAM: Autenticação, Onboarding, Unidades & RBAC

#### 1. Arquitetura de Autenticação (`src/features/iam`)
- **Estado Global (`useAuthStore.ts`)**:
  - `accessToken: string | null` (em memória / Zustand)
  - `refreshToken: string | null` (persistido em `localStorage`)
  - `user: UserProfile | null` (`id`, `name`, `email`, `tenantId`, `activeUnitId`, `roles`, `permissions`)
  - `setAuth(accessToken, refreshToken, user)`
  - `switchActiveUnit(unitId, newAccessToken, newRefreshToken)`
  - `logout()`

#### 2. Interceptor Axios com Fila Concorrente de Renovação
```typescript
// src/shared/api/apiClient.ts
import axios from 'axios';
import { useAuthStore } from '../../features/iam/stores/authStore';

export const api = axios.create({
  baseURL: import.meta.env.VITE_API_URL || 'http://localhost:8080/api/v1',
  headers: { 'Content-Type': 'application/json' },
});

api.interceptors.request.use((config) => {
  const token = useAuthStore.getState().accessToken;
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

let isRefreshing = false;
let failedQueue: Array<{ resolve: (token: string) => void; reject: (err: unknown) => void }> = [];

api.interceptors.response.use(
  (res) => res,
  async (error) => {
    const originalRequest = error.config;
    if (error.response?.status === 401 && !originalRequest._retry) {
      if (originalRequest.url?.includes('/auth/login') || originalRequest.url?.includes('/auth/refresh')) {
        useAuthStore.getState().logout();
        return Promise.reject(error);
      }

      if (isRefreshing) {
        return new Promise((resolve, reject) => {
          failedQueue.push({ resolve, reject });
        }).then((token) => {
          originalRequest.headers.Authorization = `Bearer ${token}`;
          return api(originalRequest);
        });
      }

      originalRequest._retry = true;
      isRefreshing = true;

      const refreshToken = useAuthStore.getState().refreshToken;
      if (!refreshToken) {
        useAuthStore.getState().logout();
        return Promise.reject(error);
      }

      try {
        const { data } = await axios.post(`${api.defaults.baseURL}/auth/refresh`, { refreshToken });
        useAuthStore.getState().setAuth(data.accessToken, data.refreshToken, data.user);
        failedQueue.forEach((prom) => prom.resolve(data.accessToken));
        failedQueue = [];
        originalRequest.headers.Authorization = `Bearer ${data.accessToken}`;
        return api(originalRequest);
      } catch (refreshErr) {
        failedQueue.forEach((prom) => prom.reject(refreshErr));
        failedQueue = [];
        useAuthStore.getState().logout();
        return Promise.reject(refreshErr);
      } finally {
        isRefreshing = false;
      }
    }
    return Promise.reject(error);
  }
);
```

#### 3. Telas & Componentes a Conectar:
- **Login (`autentica_o_login/code.html` -> `/login`)**:
  - `POST /api/v1/auth/login` (`email`, `password`).
  - Botão Google: Chama `GET /api/v1/auth/oauth/google/authorize` e redireciona para `authorizationUrl`.
  - Rota de Callback (`/oauth/callback`): Envia `code` e `state` para `POST /api/v1/auth/oauth/google/callback`.
- **Cadastro / Onboarding (`autentica_o_cadastro/code.html` -> `/register`)**:
  - `POST /api/v1/auth/register` (`workshopName`, `address`, `bays`, `services`, `ownerName`, `email`, `password`).
- **Seletor de Filial no Topbar**:
  - `GET /api/v1/units` (lista de filiais da oficina).
  - Ao selecionar: `POST /api/v1/auth/switch-unit` (`unitId`).
- **Gestão de Usuários (`administra_o_gest_o_de_usu_rios/code.html` -> `/admin/users`)**:
  - Tabela: `GET /api/v1/users`.
  - Modal de Novo Usuário: `POST /api/v1/users` (`name`, `email`, `password`, `roles: [{roleId, unitId}]`).
- **Papéis e Permissões (`administra_o_pap_is_e_permiss_es/code.html` -> `/admin/roles`)**:
  - `GET /api/v1/roles` e `GET /api/v1/roles/permissions`.
  - Criar Papel: `POST /api/v1/roles` (`name`, `description`, `permissionCodes`).

---

### 4.2 Módulo CRM: Clientes & Veículos

#### 1. Modelos de Dados & Validações
- **Cliente (`Customer`)**:
  - `name`: Obrigatório (max 150).
  - `document`: CPF (11 dígitos) ou CNPJ (14 dígitos) com validação de dígitos verificadores módulo 11.
  - `phone`: Obrigatório (max 20).
  - `email`: Formato de e-mail válido.
  - `address`: Opcional.
- **Veículo (`Vehicle`)**:
  - `customerId`: UUID do cliente proprietário.
  - `licensePlate`: Validação de Placa Tradicional (`ABC1234` / `ABC-1234`) e Mercosul (`ABC1D23`).
  - `brand`, `model`, `year`, `vin`, `currentMileage`.

#### 2. Telas & Componentes a Conectar:
- **Listagem de Clientes (`clientes_listagem/code.html` -> `/crm/customers`)**:
  - Busca com input de pesquisa: `GET /api/v1/customers?search=...&page=0&size=20`.
  - Ações: Visualizar veículos vinculados, editar e excluir (`DELETE /api/v1/customers/{id}`).
- **Cadastro / Edição de Cliente (`clientes_novo_cadastro/code.html` -> `/crm/customers/new` e `/crm/customers/$id`)**:
  - Criação: `POST /api/v1/customers`.
  - Edição: `PUT /api/v1/customers/{id}`.
- **Listagem de Veículos (`ve_culos_listagem/code.html` -> `/crm/vehicles`)**:
  - `GET /api/v1/vehicles?search=...&page=0&size=20`.
  - Badge de Placa: Exibir `formattedLicensePlate` (ex: `BRA-2E19` ou `ABC-1234`).
- **Cadastro / Edição de Veículo (`ve_culos_novo_cadastro/code.html` -> `/crm/vehicles/new`)**:
  - `POST /api/v1/vehicles` (`customerId`, `licensePlate`, `brand`, `model`, `year`, `vin`, `currentMileage`).

---

### 4.3 Módulo Operações: Agendamentos & Calendário (Scheduling)

#### 1. Endpoints & Ciclo de Vida
- **Estados do Agendamento**:
  - `SCHEDULED` (Agendado)
  - `CONFIRMED` (Confirmado)
  - `IN_PROGRESS` (Em Atendimento / Check-in)
  - `COMPLETED` (Concluído)
  - `CANCELED` (Cancelado)
  - `NO_SHOW` (Não Compareceu)

#### 2. Telas & Componentes a Conectar:
- **Calendário Mensal / Semanal (`agenda_calend_rio_mensal/code.html` -> `/operations/scheduling/calendar`)**:
  - Consulta por intervalo: `GET /api/v1/appointments/calendar?from=2026-08-01T00:00:00Z&to=2026-08-31T23:59:59Z&unitId={activeUnitId}`.
  - Renderiza cards de agendamento coloridos por status.
- **Check-in Diário (`agenda_check_in_di_rio/code.html` -> `/operations/scheduling/checkin`)**:
  - Listagem do dia: `GET /api/v1/appointments?unitId={activeUnitId}&from={startOfDay}&to={endOfDay}`.
  - Botão "Realizar Check-in": `PUT /api/v1/appointments/{id}/status` com `{ "status": "IN_PROGRESS" }`.
- **Novo Agendamento (`agenda_novo_agendamento/code.html` -> `/operations/scheduling/new`)**:
  - Seleção com busca de cliente e veículo.
  - Criação: `POST /api/v1/appointments` (`unitId`, `customerId`, `vehicleId`, `scheduledAt`, `estimatedEndAt`, `serviceType`, `notes`).
- **Cancelamento**:
  - `DELETE /api/v1/appointments/{id}?reason=Cliente+desistiu`.

---

### 4.4 Módulo Operações: Inspeções & Checklists Técnicos (Inspections)

#### 1. Endpoints & Laudo Técnico
- **Categorias do Checklist**:
  - `TIRES` (Pneus), `BRAKES` (Freios), `SUSPENSION` (Suspensão), `ENGINE` (Motor), `ELECTRICAL` (Elétrica), `FLUIDS` (Fluidos & Óleo), `BODYWORK` (Lataria/Pintura), `SAFETY` (Segurança), `INTERIOR`, `EXTERIOR`.
- **Status do Item**:
  - `OK` (Conforme)
  - `ATTENTION` (Requer atenção / Troca próxima)
  - `CRITICAL` (Crítico / Risco iminente)
  - `NOT_APPLICABLE` (Não aplicável)

#### 2. Telas & Componentes a Conectar:
- **Listagem de Vistorias (`/operations/inspections`)**:
  - `GET /api/v1/inspections?unitId={unitId}&status=...&page=0&size=20`.
  - Badges de itens críticos e itens em atenção (`criticalItems`, `attentionItems`).
- **Execução do Checklist Técnico (`mechanical_precision` -> `/operations/inspections/$id`)**:
  - Iniciar: `POST /api/v1/inspections` (`unitId`, `customerId`, `vehicleId`, `appointmentId`, `currentMileage`, `fuelLevel`, `generalNotes`, `items`).
  - Atualização contínua: `PUT /api/v1/inspections/{id}/items` enviando a lista de itens com `status`, `notes`, `recommendedAction` e `photoUrls`.
  - Finalizar Laudo: `POST /api/v1/inspections/{id}/complete` com `{ "generalNotes": "..." }`.
  - *Obs:* Após a finalização, a tela exibe o laudo em modo somente leitura com botão "Gerar Orçamento a partir desta Vistoria".

---

### 4.5 Módulo Operações: Orçamentos & Dupla Aprovação (Quotes)

#### 1. Cálculo Determinístico e Modelagem de Itens
- **Tipos de Item**: `PART` (Peça) e `LABOR` (Mão de Obra).
- **Fórmulas de Cálculo**:
  - $\text{Bruto} = \text{quantity} \times \text{unitPrice}$
  - $\text{Líquido} = \text{Bruto} - \text{discountAmount}$
  - $\text{Imposto} = \text{Líquido} \times (\text{taxRate} / 100)$
  - $\text{Total} = \text{Líquido} + \text{Imposto}$
- **Máquina de Estados de Dupla Aprovação**:
  - `DRAFT`: Orçamento em elaboração (permite edição dinâmica de peças e serviços).
  - `PENDING_INTERNAL_APPROVAL`: Submetido para aprovação do gerente/administrador.
  - `INTERNAL_APPROVED`: Aprovado internamente pela oficina. (**Obrigatório antes de enviar ao cliente**).
  - `SENT_TO_CUSTOMER`: Enviado para avaliação e aprovação do cliente.
  - `CUSTOMER_APPROVED`: Aprovado pelo cliente (pronto para conversão em Ordem de Serviço).
  - `CUSTOMER_REJECTED`: Rejeitado pelo cliente (com motivo registrado).
  - `REVISION`: Devolvido para ajustes técnicos ou comerciais.
  - `CANCELED`: Cancelado.

#### 2. Telas & Componentes a Conectar:
- **Listagem de Orçamentos (`or_amentos_listagem/code.html` -> `/operations/quotes`)**:
  - `GET /api/v1/quotes?unitId={unitId}&status=...&page=0&size=20`.
  - Badges por status e separação visual de total de peças e total de mão de obra.
- **Novo Orçamento / Edição (`or_amentos_novo_or_amento/code.html` -> `/operations/quotes/new` e `/operations/quotes/$id`)**:
  - Criação avulsa: `POST /api/v1/quotes` (`customerId`, `vehicleId`, `items`).
  - Geração a partir da vistoria: `POST /api/v1/quotes/from-inspection/{inspectionId}`.
  - Edição dinâmica de itens: `PUT /api/v1/quotes/{id}/items` com recálculo automático no frontend e sincronização.
  - Botão "Submeter para Aprovação Gerencial": `POST /api/v1/quotes/{id}/submit-approval`.
  - Botão "Aprovar (Gerente)": `POST /api/v1/quotes/{id}/approve`.
  - Botão "Enviar ao Cliente": `POST /api/v1/quotes/{id}/send` (habilitado apenas quando `INTERNAL_APPROVED`).
- **Portal do Cliente / Decisão (`portal_do_cliente_aprova_o_de_or_amento/code.html` -> `/portal/quotes/$id`)**:
  - `POST /api/v1/quotes/{id}/customer-decision` com `{ "approved": true/false, "notes": "..." }`.

---

### 4.6 Módulo Operações: Ordens de Serviço & Quadro Kanban (Work Orders)

#### 1. Ciclo de Vida e Modelagem de Execução Técnica
- **Tipos de Item**: `PART` (Peça) e `SERVICE` (Mão de Obra / Serviço).
- **Status do Item**: `PENDING` (Pendente), `IN_PROGRESS` (Em Execução), `COMPLETED` (Concluído).
- **Máquina de Estados da Ordem de Serviço**:
  - `DRAFT`: Em planejamento/montagem de serviços e peças.
  - `OPEN`: Aberta e atribuída a um box/baia, aguardando início da execução.
  - `IN_PROGRESS`: Em execução técnica pelo mecânico responsável.
  - `WAITING_PARTS`: Pausada aguardando chegada de peças do estoque/fornecedor.
  - `WAITING_CUSTOMER`: Pausada aguardando autorização/resposta do cliente.
  - `COMPLETED`: Serviço 100% finalizado (dispara evento transacional `WorkOrderCompletedEvent`).
  - `CANCELED`: Cancelada com motivo registrado.

#### 2. Telas & Componentes a Conectar:
- **Listagem de Ordens de Serviço (`ordens_de_servi_o_listagem/code.html` -> `/operations/work-orders`)**:
  - `GET /api/v1/work-orders?unitId={unitId}&status=...&page=0&size=20`.
  - Exibe número da OS (`orderNumber`), cliente, veículo, mecânico responsável, box e totalizadores.
- **Quadro Kanban Operacional (`ordens_de_servi_o_kanban/code.html` -> `/operations/work-orders/kanban`)**:
  - `GET /api/v1/work-orders/kanban?unitId={unitId}`.
  - Retorna 4 colunas ativas (`OPEN`, `IN_PROGRESS`, `WAITING_PARTS`, `WAITING_CUSTOMER`).
  - Drag-and-drop ou troca de coluna chama `PUT /api/v1/work-orders/{id}/status` com `{ "status": "...", "notes": "..." }`.
- **Detalhes e Execução Técnica (`ordens_de_servi_o_detalhes/code.html` -> `/operations/work-orders/$id`)**:
  - Consulta: `GET /api/v1/work-orders/{id}`.
  - Conversão a partir de orçamento aprovado: `POST /api/v1/work-orders/from-quote/{quoteId}`.
  - Atualização de dados gerais (box, mecânico, km inicial): `PUT /api/v1/work-orders/{id}`.
  - Edição dinâmica de itens e peças adicionais: `PUT /api/v1/work-orders/{id}/items`.
  - Finalização da OS: `POST /api/v1/work-orders/{id}/complete` enviando `{ "endMileage": 50015, "technicalNotes": "...", "customerNotes": "..." }`.
  - Cancelamento: `DELETE /api/v1/work-orders/{id}?reason=...`.

---

### 4.7 Módulo Operações / CRM: Histórico de Serviços do Veículo & Dossiê de Manutenções

#### 1. Modelo de Agregação e Métricas de Manutenção
- Agrega **exclusivamente ordens de serviço e vistorias concluídas (`COMPLETED`)**, fornecendo uma visão auditável da vida útil do veículo para clientes e colaboradores da oficina.
- **Métricas Calculadas em Tempo Real**:
  - `totalServicesCount`: Total de passagens/ordens concluídas.
  - `totalSpent`: Valor acumulado investido no veículo (R$).
  - `averageTicket`: Ticket médio por passagem.
  - `lastRecordedMileage`: Quilometragem mais recente registrada.
  - `totalPartsReplacedCount`: Quantidade de peças substituídas ao longo da história.
  - `firstServiceDate` e `lastServiceDate`: Datas da primeira e da última passagem.

#### 2. Endpoints Disponíveis:
- **Consulta Completa do Histórico**:
  - `GET /api/v1/operations/vehicles/{vehicleId}/history`
  - Retorna dados cadastrais do veículo e cliente, métricas consolidadas, linha do tempo detalhada com ordens de serviço (`workOrders`) e peças/serviços executados, além das vistorias técnicas (`inspections`) e apontamentos críticos.
- **Dossiê / Relatório Exportável para o Cliente**:
  - `GET /api/v1/operations/vehicles/{vehicleId}/history/export`
  - Retorna o relatório formatado com identificador único (`reportId`), código de autenticidade para validação pública (`authenticityVerificationCode`), lista certificada de serviços e cláusula de garantia de 90 dias conforme CDC.

---

## 5. Padrão Global de Tratamento de Erros (RFC 7807)

O backend retorna todos os erros no formato **RFC 7807 Problem Detail**:

```json
{
  "type": "https://gomech.com/docs/errors/validation-failed",
  "title": "Validation Failed",
  "status": 422,
  "detail": "Input validation failed for some parameters.",
  "invalidParams": [
    {
      "name": "licensePlate",
      "reason": "Placa inválida. Utilize o formato Mercosul (ABC1D23) ou Tradicional (ABC-1234)"
    },
    {
      "name": "document",
      "reason": "CPF ou CNPJ inválido"
    }
  ]
}
```

### Helper de Mapeamento para React Hook Form:
```typescript
// src/shared/utils/formErrors.ts
import { FieldValues, UseFormSetError } from 'react-hook-form';

export function handleApiValidationErrors<T extends FieldValues>(
  error: any,
  setError: UseFormSetError<T>
) {
  if (error.response?.status === 422 && error.response?.data?.invalidParams) {
    const invalidParams = error.response.data.invalidParams as Array<{ name: string; reason: string }>;
    invalidParams.forEach((param) => {
      setError(param.name as any, {
        type: 'server',
        message: param.reason,
      });
    });
    return true;
  }
  return false;
}
```

---

## 6. Estrutura de Pastas Recomendada para o Frontend

```text
frontend/src/
├── app/                        # Configurações globais e providers (QueryClient, ThemeProvider)
├── routes/                     # Rotas do TanStack Router
│   ├── __root.tsx              # Root Layout com Shell e Topbar
│   ├── index.tsx               # Redirect para /dashboard ou /login
│   ├── login.tsx               # Tela de Login (autentica_o_login)
│   ├── register.tsx            # Cadastro de Oficina (autentica_o_cadastro)
│   ├── dashboard.tsx           # Dashboard Principal (dashboard_principal)
│   ├── crm.customers.tsx       # Listagem de Clientes (clientes_listagem)
│   ├── crm.customers.new.tsx   # Novo Cliente (clientes_novo_cadastro)
│   ├── crm.vehicles.tsx        # Listagem de Veículos (ve_culos_listagem)
│   ├── crm.vehicles.new.tsx    # Novo Veículo (ve_culos_novo_cadastro)
│   ├── operations.scheduling.tsx # Calendário e Check-in (agenda_calend_rio_mensal)
│   ├── operations.inspections.tsx # Vistorias e Checklists (mechanical_precision)
│   ├── admin.users.tsx         # Gestão de Usuários (administra_o_gest_o_de_usu_rios)
│   ├── admin.roles.tsx         # Papéis e Permissões (administra_o_pap_is_e_permiss_es)
│   └── admin.company.tsx       # Configuração da Empresa / Filiais (administra_o_configura_es_da_empresa)
├── features/                   # Módulos de domínio
│   ├── iam/                    # Auth, Users, Roles, Units, Sessions
│   ├── crm/                    # Customers, Vehicles, Brazilian Masks
│   └── operations/             # Scheduling, Calendar, Inspections, Checklist
├── shared/                     # Componentes reutilizáveis, UI primitives e helpers
│   ├── components/             # Button, Input, Modal, Badge, Table, Topbar, Sidebar
│   ├── api/                    # Instância Axios e interceptors
│   └── utils/                  # Formatadores de moeda, data, placa e documento
```

---

## 7. Checklist de Implementação para o Agente Frontend (Codex)

### Fase 1: Fundação & Autenticação
- [ ] Configurar variáveis de ambiente (`VITE_API_URL`).
- [ ] Ajustar `index.css` com as cores e variáveis do tema *Mechanical Precision*.
- [ ] Implementar `authStore.ts` com suporte a `accessToken`, `refreshToken` e `user`.
- [ ] Implementar interceptor Axios com renovação de token e fila de requisições.
- [ ] Montar tela de Login (`/login`) baseada em `autentica_o_login/code.html`.
- [ ] Montar tela de Cadastro (`/register`) baseada em `autentica_o_cadastro/code.html`.
- [ ] Montar Topbar com seletor de filial (`POST /api/v1/auth/switch-unit`).

### Fase 2: Administração & Usuários
- [ ] Implementar tela de Gestão de Usuários (`/admin/users`) baseada em `administra_o_gest_o_de_usu_rios/code.html`.
- [ ] Implementar tela de Papéis e Permissões (`/admin/roles`) baseada em `administra_o_pap_is_e_permiss_es/code.html`.
- [ ] Implementar tela de Filiais/Empresa (`/admin/company`) baseada em `administra_o_configura_es_da_empresa/code.html`.

### Fase 3: CRM (Clientes & Veículos)
- [ ] Implementar listagem paginada de clientes (`/crm/customers`) baseada em `clientes_listagem/code.html`.
- [ ] Implementar formulário de cliente (`/crm/customers/new`) com máscara de CPF/CNPJ.
- [ ] Implementar listagem paginada de veículos (`/crm/vehicles`) baseada em `ve_culos_listagem/code.html`.
- [ ] Implementar formulário de veículo (`/crm/vehicles/new`) com validação de placa.

### Fase 4: Operações (Agendamentos & Vistorias)
- [ ] Implementar Calendário Mensal e Semanal (`/operations/scheduling/calendar`) baseado em `agenda_calend_rio_mensal/code.html`.
- [ ] Implementar Check-in Diário de Agendamentos (`/operations/scheduling/checkin`) baseado em `agenda_check_in_di_rio/code.html`.
- [ ] Implementar Formulário de Novo Agendamento (`/operations/scheduling/new`) baseado em `agenda_novo_agendamento/code.html`.
- [ ] Implementar Execução de Vistoria / Checklist Técnico (`/operations/inspections/$id`) com laudos (`OK`, `ATTENTION`, `CRITICAL`) e finalização.
