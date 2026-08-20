# ADR-010: Registros Financeiros Orientados a Eventos e Independência de Domínio

## Contexto
O ecossistema GoMech necessita de controle financeiro completo para as oficinas mecânicas, englobando contas bancárias/caixas, contas a receber (oriundas de ordens de serviço prestadas), contas a pagar (oriundas de compras de insumos e despesas operacionais), extrato financeiro unificado (transações de crédito e débito), projeção de fluxo de caixa e Demonstrativo do Resultado do Exercício (DRE).

Historicamente, sistemas legados acoplam o módulo financeiro diretamente às tabelas e repositórios de ordens de serviço ou compras de estoque, criando dependências circulares e violando o isolamento de módulos preconizado no ADR-001 (Modular Monolith) e ADR-002 (Module Layering and Dependency Rules).

## Decisão
1. **Módulo Financeiro Autônomo (`com.gomech.api.modules.finance`)**:
   - O módulo Financeiro possui schema próprio no banco de dados e gerencia suas próprias entidades (`FinanceAccount`, `FinanceCategory`, `FinanceReceivable`, `FinancePayable`, `FinanceTransaction`, `FinanceRecurringExpense`).
   - Não há importação de repositórios ou entidades de outros módulos (`operations`, `inventory`, etc.).

2. **Comunicação Orientada a Eventos com Idempotência**:
   - A geração de Contas a Receber reage ao evento `WorkOrderCompletedEvent` emitido pelo módulo de Operações.
   - O cancelamento ou reabertura de ordens de serviço reage a `WorkOrderReopenedEvent` e `WorkOrderCanceledEvent`, executando estorno / compensação transacional idempotente.
   - A geração de Contas a Pagar reage a eventos de compra de estoque `InventoryPurchaseCreatedEvent`.
   - Toda criação a partir de evento utiliza uma chave de correlação única (`sourceCorrelationId` / `idempotencyKey`), tornando o replay de eventos 100% idempotente e seguro contra duplicidades.

3. **Duplo Regime Contábil (Competência e Caixa)**:
   - **Competência**: Data de emissão/vencimento do título (`dueDate` / `issueDate`), fundamental para apuração contábil no DRE.
   - **Caixa**: Data de liquidação efetiva nas contas bancárias (`paymentDate`), alimentando o Fluxo de Caixa e extrato de transações.

4. **Multi-Tenancy e Isolamento Rigoroso**:
   - Todas as tabelas financeiras possuem coluna `tenant_id` e políticas de Row Level Security (RLS) no PostgreSQL.

## Consequências
- **Positivas**:
  - Desacoplamento arquitetural total: o módulo financeiro pode evoluir, auditar e conciliar lançamentos sem impactar o pipeline operacional de ordens de serviço.
  - Segurança e rastreabilidade: qualquer movimentação financeira possui correlação com seu evento originador.
  - Flexibilidade de relatórios: capacidade de gerar DRE e Fluxo de Caixa determinísticos por período e unidade.
