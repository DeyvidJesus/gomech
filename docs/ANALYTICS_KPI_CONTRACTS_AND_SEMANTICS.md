# Analytics do GoMech: contratos e semântica dos KPIs

Este documento estabelece a arquitetura, os contratos de eventos, os modelos de leitura (read models) e a semântica formal dos Indicadores Chave de Desempenho (KPIs) e relatórios gerenciais do GoMech.

---

## 1. Princípios Arquiteturais & Regras de Fronteira

1. **Desacoplamento Rigoroso (Zero Direct Business DB Access)**:
   - O módulo de **Analytics** nunca consulta repositórios ou entidades JPA de outros módulos de negócio (`operations`, `finance`, `inventory`, `tools`, `iam`, `billing`).
   - Todo o conhecimento analítico é adquirido exclusivamente através da escuta de eventos de domínio explícitos (`DomainEvent`) despachados pelo `DomainEventBus` no padrão in-process assíncrono.
2. **Modelos de Leitura Materializados (Read Models / Projections)**:
   - Projeções dedicadas com Row Level Security (RLS) e isolamento multi-tenant (`tenant_isolation_policy`):
     - `analytics_processed_events`: Registro de replay-safety e deduplicação de eventos.
     - `analytics_daily_kpi_snapshots`: Agregados diários consolidados por métrica, dimensão, tenant e filial.
     - `analytics_work_order_projections`: Projeção operacional (turnaround lead time, split peças vs serviços, mecânicos).
     - `analytics_financial_projections`: Projeção de fluxo de caixa, recebíveis, contas a pagar e liquidações.
     - `analytics_inventory_projections`: Projeção de compras de estoque e consumo por OS.
     - `analytics_tool_projections`: Projeção de manutenções de ferramentas, downtime e custódias ativas.
3. **Idempotência e Replay-Safety**:
   - Cada evento recebido pelo `AnalyticsEventListener` valida se já foi processado através de `AnalyticsProcessedEventLogRepository.existsByTenantIdAndEventId(tenantId, eventId)`. Eventos reprocessados ou duplicados são descartados sem gerar duplicação de métricas.
4. **Governança, RBAC & Entitlements**:
   - Permissões de sistema:
     - `ANALYTICS_DASHBOARD_READ`: Acesso aos painéis e séries temporais.
     - `ANALYTICS_REPORT_READ`: Consulta aos relatórios tabulares parametrizados.
     - `ANALYTICS_REPORT_EXPORT`: Exportação em CSV/JSON.
     - `ANALYTICS_KPI_READ`: Leitura do catálogo formal de KPIs.
   - Entitlements por Plano:
     - O plano de assinatura do tenant deve habilitar a feature `MODULE_ANALYTICS`.
     - Exportações consom e debitam cota formal de relatórios (`QuotaDimension.REPORTS`).

---

## 2. Catálogo Formal de KPIs & Semântica

| Código KPI | Categoria | Título | Fórmula / Definição | Unidade | Dimensões | Gatilho / Atualização |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `WO_COMPLETED_COUNT` | `OPERATIONS` | Ordens de Serviço Concluídas | `COUNT(work_orders WHERE status = 'COMPLETED')` | unidades | `tenant_id`, `unit_id`, `date`, `mechanic_user_id` | Tempo real via `WorkOrderCompletedEvent` |
| `WO_TOTAL_REVENUE` | `OPERATIONS` | Faturamento Total de OS | `SUM(total_amount FROM completed work_orders)` | R$ | `tenant_id`, `unit_id`, `date`, `mechanic_user_id` | Tempo real via `WorkOrderCompletedEvent` |
| `WO_PARTS_REVENUE` | `OPERATIONS` | Faturamento de Peças | `SUM(total_parts_amount)` | R$ | `tenant_id`, `unit_id`, `date` | Tempo real via `WorkOrderCompletedEvent` |
| `WO_SERVICES_REVENUE` | `OPERATIONS` | Faturamento de Mão de Obra | `SUM(total_services_amount)` | R$ | `tenant_id`, `unit_id`, `date` | Tempo real via `WorkOrderCompletedEvent` |
| `WO_AVG_TICKET` | `OPERATIONS` | Ticket Médio de OS | `SUM(total_amount) / COUNT(completed work_orders)` | R$ | `tenant_id`, `unit_id`, `date` | Recálculo sob demanda |
| `WO_AVG_TURNAROUND_HOURS` | `OPERATIONS` | Lead Time Médio de Atendimento | `AVG(completed_at - opened_at)` em horas | horas | `tenant_id`, `unit_id`, `date` | Materializado em `AnalyticsWorkOrderProjection` |
| `QUOTE_CONVERSION_RATE` | `OPERATIONS` | Taxa de Conversão de Orçamentos | `(COUNT(approved) / COUNT(total quotes)) * 100` | % | `tenant_id`, `unit_id`, `date` | Tempo real via `QuoteCustomerDecisionEvent` |
| `APPOINTMENT_COMPLETION_RATE` | `OPERATIONS` | Taxa de Comparecimento de Agendamentos | `(COUNT(completed) / COUNT(scheduled)) * 100` | % | `tenant_id`, `unit_id`, `date` | Tempo real via `AppointmentStatusChangedEvent` |
| `FIN_GROSS_REVENUE` | `FINANCE` | Receita Bruta Total | `SUM(receivables amount)` | R$ | `tenant_id`, `unit_id`, `date` | Tempo real via `ReceivableCreatedEvent` |
| `FIN_RECEIVABLES_PAID` | `FINANCE` | Recebíveis Liquidados (Entradas) | `SUM(receivables WHERE status = 'PAID')` | R$ | `tenant_id`, `unit_id`, `date` | Tempo real via `TransactionRecordedEvent` |
| `FIN_PAYABLES_PAID` | `FINANCE` | Despesas Pagas (Saídas) | `SUM(payables WHERE status = 'PAID')` | R$ | `tenant_id`, `unit_id`, `date` | Tempo real via `TransactionRecordedEvent` |
| `FIN_NET_PROFIT` | `FINANCE` | Lucro Líquido Operacional | `FIN_RECEIVABLES_PAID - FIN_PAYABLES_PAID` | R$ | `tenant_id`, `unit_id`, `date` | Recálculo sob demanda |
| `FIN_OPERATING_MARGIN` | `FINANCE` | Margem Operacional | `(FIN_NET_PROFIT / FIN_RECEIVABLES_PAID) * 100` | % | `tenant_id`, `unit_id`, `date` | Recálculo sob demanda |
| `FIN_DELINQUENCY_RATE` | `FINANCE` | Taxa de Inadimplência | `(SUM(overdue receivables) / SUM(total)) * 100` | % | `tenant_id`, `unit_id`, `date` | Projeção sob demanda |
| `STOCK_PURCHASE_SPEND` | `INVENTORY` | Investimento em Compras | `SUM(purchases total_amount)` | R$ | `tenant_id`, `unit_id`, `date` | Tempo real via `InventoryPurchaseCreatedEvent` |
| `STOCK_CONSUMED_VALUE` | `INVENTORY` | Consumo de Peças em Serviços | `SUM(quantity * unit_cost)` | R$ | `tenant_id`, `unit_id`, `date`, `product_id` | Tempo real via `StockConsumedEvent` |
| `TOOL_ACTIVE_CUSTODY` | `TOOLS` | Equipamentos em Custódia | `COUNT(tools WHERE status = 'IN_USE')` | unidades | `tenant_id`, `unit_id`, `date` | Tempo real via `ToolCustodyAssignedEvent` |
| `TOOL_MAINTENANCE_COST` | `TOOLS` | Custo de Manutenção de Ferramentas | `SUM(maintenance cost)` | R$ | `tenant_id`, `unit_id`, `date` | Tempo real via `ToolMaintenanceCompletedEvent` |
| `BILLING_REPORTS_QUOTA` | `BILLING` | Consumo de Cota de Relatórios | `COUNT(report exports generated)` | execuções | `tenant_id`, `billing_cycle` | Débito em tempo de exportação via `EntitlementService` |

---

## 3. Contratos de API REST

### 3.1. Dashboard Executivo
- **Endpoint**: `GET /api/v1/analytics/dashboard`
- **Permissão**: `ANALYTICS_DASHBOARD_READ` ou `Proprietário`
- **Query Params**:
  - `unitId` (opcional, UUID da filial)
  - `startDate` (opcional, `YYYY-MM-DD`)
  - `endDate` (opcional, `YYYY-MM-DD`)
- **Resposta**: Objeto com `heroKpis` (valores formatados, direção de tendência e % de variação vs período anterior), resumos segmentados (`operational`, `financial`, `inventory`, `tools`, `billing`), `revenueTimeSeries` (pontos diários para gráficos), `serviceVsPartsBreakdown` e `topTechnicians`.

### 3.2. Relatórios Parametrizados
- **Endpoint**: `GET /api/v1/analytics/reports`
- **Permissão**: `ANALYTICS_REPORT_READ` ou `Proprietário`
- **Query Params**: `reportType`, `startDate`, `endDate`, `unitId`, `interval`, `search`, paginação (`page`, `size`, `sort`).
- **Resposta**: Objeto paginado com `columnHeaders`, `rows` estruturadas e `summaryMetrics`.

### 3.3. Exportação de Relatórios
- **Endpoint**: `POST /api/v1/analytics/reports/export`
- **Permissão**: `ANALYTICS_REPORT_EXPORT` ou `Proprietário`
- **Entitlement**: Verifica e debita cota de `QuotaDimension.REPORTS`.
- **Payload**:
  ```json
  {
    "reportType": "OPERATIONAL_SUMMARY",
    "format": "CSV",
    "startDate": "2026-08-01",
    "endDate": "2026-08-26"
  }
  ```
- **Resposta**: Arquivo binário com `Content-Disposition: attachment; filename="report-..."` em `text/csv` ou `application/json`.

### 3.4. Catálogo de Contratos de KPIs
- **Endpoint**: `GET /api/v1/analytics/kpis`
- **Permissão**: `ANALYTICS_KPI_READ` ou `Proprietário`
- **Resposta**: Lista completa dos contratos e semântica de todos os KPIs do GoMech.
