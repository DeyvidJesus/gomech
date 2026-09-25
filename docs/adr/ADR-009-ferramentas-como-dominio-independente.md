# ADR-009: Ferramentas e equipamentos como módulo de domínio independente

- **Status:** Aceita
- **Data:** 2026-08-20

## Contexto

Em um ERP/CRM para oficinas automotivas, os itens físicos gerenciados pela plataforma se dividem em duas categorias fundamentalmente distintas:

1. **Materiais de consumo e peças (`Inventory`):** óleo, pastilhas de freio, filtros, parafusos, juntas. Esses itens são controlados por quantidade/SKU, comprados em lote, reservados para ordens de serviço e **consumidos de forma permanente** (a quantidade física diminui com o uso e nunca volta para a prateleira da oficina).
2. **Ativos e equipamentos reutilizáveis (`Tools`):** torquímetros, multímetros, elevadores hidráulicos, guinchos de motor, scanners de diagnóstico, sacadores especiais. Esses itens são **ativos identificáveis** (etiquetados com número de patrimônio ou número de série), têm vida útil operacional de vários anos, ficam sob custódia temporária de mecânicos, exigem calibração/inspeção periódica e voltam ao almoxarifado da oficina na devolução (check-in).

Misturar ferramentas reutilizáveis com o estoque de consumo polui seriamente o modelo de domínio (ex.: tentar dar baixa na quantidade de itens que não são consumidos, ausência de um ciclo de custódia com check-out/check-in, impossibilidade de modelar certificados de calibração, tolerâncias de precisão e cronogramas de manutenção).

## Decisão

Estabelecemos **`Tools` (`com.gomech.api.modules.tools`)** como um módulo de domínio independente e de primeira classe dentro da arquitetura de monolito modular do GoMech, estritamente separado de `Inventory`.

### Princípios centrais

1. **Ciclo de vida e ownership independentes:**
   - `Tools` é dono das próprias tabelas (`tools`, `tool_categories`, `tool_custody_logs`, `tool_usages`, `tool_transfers`, `tool_maintenances`).
   - Ferramentas são ativos físicos únicos, identificados por `asset_tag` (único por tenant) ou `serial_number`.
2. **Rastreamento de custódia e localização em tempo real:**
   - Toda ferramenta tem um status operacional (`AVAILABLE`, `IN_USE`, `IN_MAINTENANCE`, `IN_TRANSIT`, `DECOMMISSIONED`, `LOST`), uma unidade/filial atribuída, uma localização física na prateleira e, opcionalmente, um mecânico responsável pela custódia (`current_holder_user_id`).
   - Toda mudança de custódia gera um registro de auditoria imutável em `tool_custody_logs`, com tipos de evento (`CHECK_OUT`, `CHECK_IN`, `ASSIGN`, `TRANSFER`, `RETURN`).
3. **Integração com ordens de serviço via contratos:**
   - O módulo `Operations` vincula o uso de ferramentas a ordens de serviço ativas exclusivamente por meio da interface pública `ToolsContract`.
   - Usar uma ferramenta em uma ordem de serviço muda seu status para `IN_USE` e registra a custódia, sem reduzir o inventário de ativos.
4. **Manutenção preventiva e calibração metrológica:**
   - Ferramentas especializadas (ex.: torquímetros, manômetros) podem exigir ciclos de calibração (`requires_calibration = true`, `default_maintenance_interval_days`).
   - O módulo registra manutenções agendadas e realizadas, custos, laudos de calibração e as próximas datas de vencimento.
5. **Transferências entre filiais:**
   - Transferências de ferramentas entre unidades são suportadas com números de transferência `TRFT-XXXXX`, expedição na origem e confirmação de recebimento no destino.

## Alternativas consideradas

- **Tratar ferramentas como produtos não consumíveis no estoque:** rejeitada porque as estruturas de dados do estoque (lotes, saldos por SKU, custeio FIFO/custo médio) não suportam etiquetas de patrimônio individuais, logs de custódia com check-out/check-in por mecânico nem ciclos de calibração.
- **Sistema genérico de gestão de ativos:** rejeitada para manter a integração estreita com o fluxo de trabalho automotivo (ordens de serviço, mecânicos, operação com várias filiais).

## Consequências

- **Positivas:**
  - Separação clara de responsabilidades entre itens de consumo e ativos fixos.
  - Histórico auditável completo de quem estava com qual ferramenta, quando, em qual ordem de serviço e quando ela foi devolvida.
  - Conformidade com normas de garantia da qualidade que exigem instrumentos de medição calibrados.
  - Zero acoplamento entre as tabelas de `Inventory` e de `Tools`.
- **Negativas / trade-offs:**
  - Exige manter um conjunto dedicado de tabelas, permissões e controllers.
  - Operações entre módulos (como vincular uma ferramenta a uma ordem de serviço) exigem chamadas de contrato em vez de joins SQL diretos.
