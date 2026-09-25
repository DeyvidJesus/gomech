# ADR-010: Registros financeiros orientados a eventos e independência de domínio

- **Status:** Aceita
- **Data:** 2026-08-20

## Contexto

O ecossistema GoMech precisa de controle financeiro completo para as oficinas mecânicas, abrangendo contas bancárias/caixas, contas a receber (originadas das ordens de serviço prestadas), contas a pagar (originadas das compras de insumos e das despesas operacionais), extrato financeiro unificado (transações de crédito e débito), projeção de fluxo de caixa e Demonstrativo do Resultado do Exercício (DRE).

Historicamente, sistemas legados acoplam o módulo financeiro diretamente às tabelas e aos repositórios de ordens de serviço ou de compras de estoque, criando dependências circulares e violando o isolamento de módulos preconizado na [ADR-001 (Monolito modular)](ADR-001-monolito-modular.md) e na [ADR-002 (Camadas e regras de dependência)](ADR-002-camadas-e-regras-de-dependencia.md).

## Decisão

1. **Módulo financeiro autônomo (`com.gomech.api.modules.finance`):**
   - O módulo financeiro é dono das próprias tabelas no banco de dados e gerencia suas próprias entidades (`FinanceAccount`, `FinanceCategory`, `FinanceReceivable`, `FinancePayable`, `FinanceTransaction`, `FinanceRecurringExpense`).
   - Não há importação de repositórios ou entidades de outros módulos (`operations`, `inventory` etc.).

2. **Comunicação orientada a eventos, com idempotência:**
   - A geração de contas a receber reage ao evento `WorkOrderCompletedEvent`, emitido pelo módulo de Operações.
   - O cancelamento ou a reabertura de ordens de serviço reage a `WorkOrderReopenedEvent` e `WorkOrderCanceledEvent`, executando estorno/compensação transacional idempotente.
   - A geração de contas a pagar reage a eventos de compra de estoque (`InventoryPurchaseCreatedEvent`).
   - Toda criação a partir de evento usa uma chave de correlação única (`sourceCorrelationId` / `idempotencyKey`), o que torna o replay de eventos 100% idempotente e seguro contra duplicidades.

3. **Duplo regime contábil (competência e caixa):**
   - **Competência:** data de emissão/vencimento do título (`dueDate` / `issueDate`), fundamental para a apuração contábil no DRE.
   - **Caixa:** data de liquidação efetiva nas contas bancárias (`paymentDate`), que alimenta o fluxo de caixa e o extrato de transações.

4. **Multi-tenancy e isolamento rigoroso:**
   - Todas as tabelas financeiras têm coluna `tenant_id` e políticas de Row Level Security (RLS) no PostgreSQL.

## Consequências

- **Positivas:**
  - Desacoplamento arquitetural total: o módulo financeiro pode evoluir, auditar e conciliar lançamentos sem impactar o pipeline operacional das ordens de serviço.
  - Segurança e rastreabilidade: toda movimentação financeira é correlacionada ao evento que a originou.
  - Flexibilidade de relatórios: é possível gerar DRE e fluxo de caixa determinísticos por período e por unidade.
