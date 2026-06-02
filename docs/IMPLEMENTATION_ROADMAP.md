# GoMech V2 - Roadmap de Implementação

Este documento estabelece o fluxo de entrega do sistema em 10 fases modulares e sequenciais. O objetivo é garantir que cada fundação seja estabilizada antes de prosseguir, mitigar riscos logo no início (como RLS e Tenancy) e acelerar o Time to Market do MVP operacional.

---

## Fase 1: IAM (Identity & Access Management)
Construção do alicerce de acesso e credenciais de operadores da aplicação.
* **Dependências**: Setup inicial de Repositórios (React/Spring Boot), Banco de Dados (PostgreSQL) e Pipelines CI/CD configurados.
* **Critérios de conclusão**:
  - Filtros de segurança e rotas JWT (Login, Refresh) operacionais.
  - CRUD restrito de Usuários, Roles e Permissions.
  - Testes de ponta-a-ponta certificando emissão e revogação de sessão.
* **Riscos**: Implementação complexa e de alto risco de segurança nas configurações estritas do Spring Security.
* **Prioridade**: **Crítica 🔴** (Sem isso, o sistema não é acessível).

## Fase 2: Tenant + Units
Estruturação da segregação de dados entre oficinas distintas e do conceito de filiais.
* **Dependências**: Fase 1 (IAM).
* **Critérios de conclusão**:
  - Cadastros base de Empresas (`Tenants`) e Filiais (`Units`).
  - Row Level Security (RLS) plenamente aplicada e testada no nível do PostgreSQL.
  - O filtro backend (TenantContext) em funcionamento injetando transparência em cada query do Hibernate.
* **Riscos**: Falhas no RLS podem causar vazamento catastrófico de dados de clientes cruzados (o pior cenário em um SaaS).
* **Prioridade**: **Crítica 🔴**

## Fase 3: Customers + Vehicles
Início do módulo de negócio, abrindo espaço para recebimento de frota da oficina.
* **Dependências**: Fase 2 (para garantir o isolamento).
* **Critérios de conclusão**:
  - CRUD otimizado de Clientes (CPF/CNPJ validados via anotações costumizadas).
  - CRUD de Veículos amarrados ao cliente, com lógica de soft-delete ativada.
  - Validação garantindo placas únicas por empresa (`Tenant`).
* **Riscos**: Modelagem comum, risco de engenharia muito baixo.
* **Prioridade**: **Alta 🟠**

## Fase 4: Quotes (Orçamentos)
A entrada de faturamento da oficina, orquestrando propostas comerciais.
* **Dependências**: Fase 3.
* **Critérios de conclusão**:
  - Tela rica de adição/remoção dinâmica de itens e mão-de-obra no formulário de Orçamento (React Hook Form fluído).
  - Ciclo de vida estrito implementado (Criação -> Pendente -> Aprovação -> Rejeição).
* **Riscos**: Acoplamento temporário. Como a "Fase 6 - Inventory" ainda não ocorreu, o catálogo de itens do orçamento precisará de uma estrutura *mockada* ou simplificada inicialmente no backend.
* **Prioridade**: **Alta 🟠**

## Fase 5: Work Orders (Ordens de Serviço)
O coração da oficina. Transformação de acordos em operações técnicas executáveis em boxes de atendimento.
* **Dependências**: Fase 4.
* **Critérios de conclusão**:
  - Conversão automatizada de um Quote Aprovado para uma Work Order.
  - Painel de status em tempo real (Timeline / Kanban de Box) atualizando mecânicos.
  - Regras de domínio ativas, impedindo a regressão impossível de status (Ex: Fechado para Em Andamento).
* **Riscos**: Colisões de concorrência ou atualizações sujas quando múltiplos operadores tentam salvar o mesmo card da OS simultaneamente.
* **Prioridade**: **Alta 🟠**

## Fase 6: Inventory
Controle patrimonial de autopeças e automação de saídas.
* **Dependências**: Fase 5.
* **Critérios de conclusão**:
  - Catálogo formal de Produtos e cadastro de Fornecedores.
  - Tabelas de `InventoryMovements` funcionando exclusivamente como *Append-Only* (Imutabilidade transacional).
  - A integração mágica: Quando a Work Order (Fase 5) for marcada como "Concluída", os itens da OS devem dar baixa assíncrona automática no banco de Inventário.
* **Riscos**: Complexidade de bloqueio pessimista ou otimista na hora de debater o estoque físico exato para não zerar quantidades de modo irreal.
* **Prioridade**: **Média 🟡**

## Fase 7: Financial
Mapeamento de despesas da loja, pagamentos da OS e DRE inicial.
* **Dependências**: Fase 5 e Fase 6.
* **Critérios de conclusão**:
  - Livro base de Receitas e Despesas (Contas a Pagar/Receber).
  - Automação: Integração que gera boletos/pendências no momento da finalização de uma Work Order.
  - Estornos automáticos se a originadora (OS) for reaberta ou invalidada.
* **Riscos**: Inconsistências de dados ou desdobramento de pagamentos fracionados difíceis de rastrear na auditoria.
* **Prioridade**: **Média 🟡**

## Fase 8: Billing (Pagamento do SaaS GoMech)
Integração com a infraestrutura corporativa de vocês como provedores do SaaS.
* **Dependências**: Fase 2 (Tenants consolidados).
* **Critérios de conclusão**:
  - Planos e limites amarrados ao Tenant.
  - Integração por Webhooks concluída com Gateway (PagArme).
  - O sistema consegue suspender sumariamente e revogar sessão JWT de clientes cujo webhook alertou sobre falta de pagamento.
* **Riscos**: Alta instabilidade se a rede do webhook externo for falha; transações órfãs gerando cortes de serviço incorretos dos donos da oficina.
* **Prioridade**: **Baixa 🟢** (Pode atrasar no cronograma MVP, as cobranças dos primeiros clientes betas podem ser guiadas via boleto manual).

## Fase 9: Dashboard
Módulo agregador e de análise tática do gerente da Oficina.
* **Dependências**: Todas as fases operacionais (3 a 7).
* **Critérios de conclusão**:
  - Implementação completa dos KPI Cards e Gráficos solicitados pelo Figma.
  - Cálculo de performance técnica em tela inicial (`Active Jobs`, `Revenue Today`, `Low Stock Alerts`).
* **Riscos**: Queries agregadas complexas (`GROUP BY` e `SUM`) podem apresentar lentidão crítica em produção afetando todo o tenant se executadas na base principal, talvez exigindo read-replicas ou materialized views no banco.
* **Prioridade**: **Baixa 🟢** (Refinamento analítico).

## Fase 10: AI
Assistência preditiva em rotinas pesadas baseadas em LLMs.
* **Dependências**: Fases maduras e com massa de dados já preenchida pelas operações históricas.
* **Critérios de conclusão**:
  - Assistente capaz de resumir históricos de veículos ou sugerir autopeças comumente substituídas baseado na quilometragem e anotações.
* **Riscos**: Alucinação de dados críticos gerando prejuízo contábil; custo imprevisto das requisições via API de IA em um modelo SaaS se o limite estourar.
* **Prioridade**: **Mínima 🔵** (Pura inovação pós-PMF - Product-Market Fit).
