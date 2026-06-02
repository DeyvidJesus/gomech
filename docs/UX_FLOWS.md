# Fluxos de Navegação do Sistema - GoMech

Este documento mapeia as jornadas completas de navegação para os principais perfis de usuários do GoMech, detalhando seus objetivos, telas acessadas, ações realizadas e permissões necessárias.

---

## 1. Jornada do Proprietário

**Objetivo:** Ter a visão estratégica completa do negócio, acompanhar os indicadores de performance, faturamento e tomar decisões gerenciais envolvendo múltiplas unidades e configurações do sistema.

**Telas Acessadas:**
- Dashboard Principal (Visão Consolidada e por Unidade)
- Relatórios (Operacionais e Financeiros)
- Administração (Gestão de Unidades e Assinaturas)
- Auditoria e Históricos Críticos

**Ações Realizadas:**
- Analisar indicadores (DRE, Fluxo de Caixa, Taxa de Conversão).
- Mudar de unidade (caso possua múltiplas unidades) para análise comparativa.
- Gerenciar a assinatura do SaaS (Upgrades/Downgrades/Pagamentos via PagArme).
- Acessar o módulo de auditoria para visualizar ações críticas e rastreabilidade.
- Consultar a Inteligência Artificial para gerar relatórios e insights de negócios.

**Permissões Necessárias:**
- `owner_access`: Acesso total e incondicional ao sistema e suas unidades.
- `view_all_units`: Permite visualizar dados de todas as unidades da empresa.
- `view_audit_logs`: Permite acessar os logs de auditoria de ações críticas.
- `manage_subscription`: Acesso ao painel de gestão de assinaturas do GoMech.

---

## 2. Jornada do Administrador / Gerente

**Objetivo:** Gerenciar a operação diária da unidade, controlar equipes, aprovar fluxos financeiros, monitorar o estoque e garantir que o fluxo de atendimento da oficina flua corretamente.

**Telas Acessadas:**
- Dashboard (Visão da Unidade Atual)
- Gestão de Usuários e Cargos
- Estoque e Inventário
- Financeiro (Contas a Pagar e Receber, Fluxo de Caixa)
- Ordens de Serviço (Visão Geral/Gestão)
- Agenda (Calendário e Distribuição)

**Ações Realizadas:**
- Cadastrar e gerenciar acessos de colaboradores (Mecânicos, Consultores, etc.).
- Aprovar e revisar contas a pagar e movimentações financeiras.
- Monitorar alertas de estoque mínimo e aprovar entrada/saída de peças e fornecedores.
- Distribuir serviços e gerenciar o calendário geral e a ocupação da oficina.
- Utilizar a Inteligência Artificial para consultas operacionais.

**Permissões Necessárias:**
- `admin_unit_access`: Acesso total e de gestão apenas na sua unidade designada.
- `manage_users`: Permite cadastrar, inativar e gerenciar cargos/permissões de usuários.
- `manage_inventory`: Permissão total sobre produtos, movimentações e inventário.
- `manage_finance`: Permite lançar, editar e aprovar transações financeiras.
- `manage_schedule`: Gestão completa de distribuição de serviços.

---

## 3. Jornada do Consultor Técnico

**Objetivo:** Realizar o atendimento direto ao cliente, registrar informações completas de veículos, criar orçamentos atraentes e precisos, e gerenciar a aprovação dos serviços.

**Telas Acessadas:**
- Agenda (Meus Agendamentos)
- Clientes e Veículos
- Orçamentos
- Ordens de Serviço (Acompanhamento)

**Ações Realizadas:**
- Cadastrar novos clientes (importação ou manual) e novos veículos (fotos, documentação, km).
- Analisar o histórico do cliente e do veículo.
- Criar novos orçamentos detalhados (peças, serviços e custos).
- Compartilhar orçamentos com o cliente e registrar o status (Aprovação/Reprovação).
- Converter orçamentos aprovados em Ordens de Serviço (OS).
- Acompanhar o status das Ordens de Serviço em andamento para atualizar o cliente.
- Utilizar IA como assistente interno para buscas ou diagnósticos preliminares baseados nos relatos do cliente.

**Permissões Necessárias:**
- `manage_customers`: Criar, visualizar e editar clientes e veículos.
- `manage_quotes`: Criar, editar, compartilhar e alterar status de orçamentos.
- `convert_quote_to_os`: Permissão para abrir ordem de serviço a partir de orçamento aprovado.
- `view_inventory`: Visualizar disponibilidade de peças para elaboração do orçamento (sem permissão de edição de estoque).
- `view_os`: Visualizar o andamento das ordens de serviço.

---

## 4. Jornada do Mecânico

**Objetivo:** Visualizar as Ordens de Serviço alocadas para si, registrar a execução do trabalho técnico, apontar horas, peças utilizadas e consultar históricos técnicos.

**Telas Acessadas:**
- Minha Agenda / Meus Serviços (Distribuição)
- Ordens de Serviço (Visão de Execução)
- Veículos (Histórico de Manutenção)
- Inteligência Artificial (Diagnóstico Assistido)

**Ações Realizadas:**
- Visualizar detalhes das Ordens de Serviço (OS) em que atua como responsável.
- Atualizar o andamento da OS por status (ex: "Em andamento", "Aguardando Peça", "Concluído").
- Registrar/apontar as peças e insumos efetivamente utilizados na execução do serviço.
- Registrar os serviços efetivamente executados e anexar observações técnicas/checklist.
- Consultar a Inteligência Artificial para obter sugestões de diagnósticos de falhas complexas.

**Permissões Necessárias:**
- `view_assigned_os`: Acessar ordens de serviço onde está nominalmente designado.
- `update_os_progress`: Alterar status e adicionar notas técnicas na ordem de serviço.
- `register_parts_used`: Apontar o uso de peças do estoque para a respectiva OS.
- `view_vehicle_history`: Visualizar o histórico de manutenção do veículo específico.

---

## 5. Jornada do Financeiro

**Objetivo:** Controlar rigorosamente todo o fluxo de caixa, monitorar pagamentos (físicos e gateways digitais), lançar despesas e gerar relatórios financeiros operacionais.

**Telas Acessadas:**
- Financeiro (Contas a Pagar/Receber, Fluxo de Caixa)
- Clientes (Histórico Financeiro)
- Relatórios (DRE Simplificado, Indicadores)
- Dashboard Financeiro

**Ações Realizadas:**
- Registrar receitas, incluindo a conciliação de recebimentos oriundos de OS concluídas.
- Validar transações via gateway PagArme (PIX, Cartão de Crédito).
- Lançar e conciliar despesas (pagamento de fornecedores, salários, contas de consumo).
- Analisar o histórico financeiro dos clientes para atuar na gestão de inadimplência.
- Gerar relatórios periódicos de DRE simplificado e Fluxo de Caixa para apresentar ao Proprietário/Administrador.

**Permissões Necessárias:**
- `manage_finance_full`: Acesso completo ao módulo financeiro (criação, edição e exclusão de recebimentos/pagamentos).
- `view_customer_finance`: Acesso ao histórico financeiro atrelado ao cadastro do cliente.
- `generate_financial_reports`: Permissão específica para extração de relatórios consolidados (DRE, Caixa).
