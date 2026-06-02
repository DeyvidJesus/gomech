# Arquitetura do Sistema GoMech V2

Este documento detalha a arquitetura, estrutura e estratégias fundamentais para o desenvolvimento da **GoMech V2**, uma plataforma SaaS multi-tenant para gestão de oficinas mecânicas.

---

## 1. Arquitetura do Sistema

A GoMech V2 seguirá uma arquitetura de **Monolito Modular** no backend e uma **Single Page Application (SPA)** no frontend. Esta abordagem oferece a simplicidade de implantação de um monolito com a organização e isolamento de microsserviços, facilitando uma futura extração caso a escala exija.

### Stack Tecnológico
- **Frontend**: React com TypeScript, utilizando Vite como bundler. Gerenciamento de estado com Zustand e React Query para cache e chamadas de API. Componentização com TailwindCSS ou UI library (ex: shadcn/ui).
- **Backend**: Java ou Kotlin com Spring Boot 3.x. Comunicação via APIs RESTful.
- **Banco de Dados**: PostgreSQL (Relacional, robusto e excelente suporte a multi-tenant).
- **Infraestrutura**: Docker e Docker Compose para padronização de ambientes (desenvolvimento e produção). Implantação baseada em containers (ex: AWS ECS, Google Cloud Run ou Kubernetes).
- **Cache / Fila (Futuro)**: Redis (para controle de sessões, cache e filas de processos assíncronos como relatórios).

### Topologia de Alto Nível
1. **Cliente Web** (React) comunica-se com o **Backend** via HTTPS.
2. O **Backend** atua por trás de um **API Gateway / Load Balancer** (ex: Nginx, AWS ALB), que faz a terminação SSL.
3. O **Spring Boot** processa a requisição, valida a autenticação/tenant, interage com o **PostgreSQL** e retorna os dados.
4. Integrações externas (PagArme, IA) ocorrem via serviços REST no backend de forma assíncrona ou síncrona.

---

## 2. Estrutura de Módulos

A aplicação será dividida em domínios lógicos (Bounded Contexts do Domain-Driven Design), tanto no código frontend quanto no backend.

* **IAM (Identity & Access Management)**: Autenticação, usuários, cargos, permissões, sessões, empresas (tenants) e unidades.
* **CRM (Customer Relationship Management)**: Gestão de clientes e veículos.
* **Operations (Operações)**: Orçamentos, Ordens de Serviço (OS) e Agenda/Calendário.
* **Inventory (Estoque)**: Cadastro de produtos, peças, movimentações de estoque, inventário e fornecedores.
* **Finance (Financeiro)**: Receitas, despesas, fluxo de caixa, DRE, contas a pagar/receber.
* **Billing (Assinaturas)**: Gestão de planos, checkout próprio e integração com o gateway PagArme.
* **AI & Analytics**: Assistente virtual, diagnósticos assistidos, dashboards e indicadores consolidados.
* **Core / Commons**: Infraestrutura base (auditoria, tratamento de exceções, utilitários, envio de e-mails/WhatsApp).

---

## 3. Dependências entre Módulos

Para manter a saúde do monolito modular, as dependências devem ser unidirecionais, evitando acoplamento cíclico (ex: utilizando *Spring Modulith* para validação).

* **Core** e **IAM** são a base. Todos os outros módulos dependem deles para resolver o contexto (quem está acessando, de qual empresa e unidade).
* **Operations** depende de:
  * **CRM** (para associar uma OS a um Cliente/Veículo).
  * **Inventory** (para baixar peças usadas em uma OS).
  * **Finance** (para gerar contas a receber ao finalizar uma OS).
* **Billing** é relativamente isolado, dependendo apenas do **IAM** (para identificar a empresa/assinatura).
* **AI & Analytics** é um módulo "espectador". Ele consome dados (modo leitura) de todos os outros módulos para gerar relatórios e diagnósticos.

*Regra de Ouro*: Módulos não acessam o banco de dados de outros módulos diretamente. A comunicação ocorre através de interfaces (Services/APIs internas) bem definidas ou eventos (ApplicationEvents).

---

## 4. Estratégia Multi-Tenant

Para garantir que **"os dados de diferentes empresas nunca poderão se misturar"** mantendo a escalabilidade:

**Abordagem Escolhida:** Banco de Dados Compartilhado, Esquema Compartilhado (Shared Schema) com coluna discriminadora (`tenant_id`) **+ Row Level Security (RLS) do PostgreSQL.**

### Como funciona:
1. **Modelagem**: Toda tabela que pertence a uma empresa terá uma coluna `tenant_id`.
2. **Segurança no Banco (RLS)**: O PostgreSQL configurará políticas de segurança (Policies) para que uma query só possa ler/escrever linhas onde `tenant_id` seja igual ao do contexto atual. Mesmo se houver uma falha no código backend, o banco de dados bloqueia o vazamento de dados.
3. **Aplicação (Spring Boot)**: 
   - Um `Filter` intercepta a requisição, extrai o `tenant_id` do Token JWT e o define em um `ThreadLocal` (`TenantContext`).
   - O Hibernate automaticamente injeta esse `tenant_id` nas queries (via `@TenantId` do Hibernate 6) e configura o contexto do PostgreSQL.
4. **Multiunidade**: Além do `tenant_id`, entidades como Estoque e OS terão um `unit_id`. Consultas gerenciais podem omitir o filtro de unidade (vendo a empresa toda), enquanto usuários operacionais terão filtros automáticos baseados nas unidades que possuem acesso.

---

## 5. Estratégia de Autenticação

* **Modelo Stateless com JWT**: O backend não guardará estado de sessão em memória. O login gera um par de tokens: `Access Token` (JWT, vida curta, ex: 15 min) e `Refresh Token` (opaco, salvo no banco/Redis, vida longa, ex: 7 dias).
* **Conteúdo do JWT (Payload)**: Conterá o `user_id`, `tenant_id`, e uma lista enxuta de `roles`/`permissions` para evitar idas ao banco a cada requisição.
* **Gestão de Dispositivos**: Cada login gera um registro na tabela `user_sessions` vinculado ao `Refresh Token`. Para deslogar remotamente um dispositivo, basta invalidar o Refresh Token correspondente no banco.
* **Segurança Adicional**: Senhas encriptadas via Bcrypt/Argon2. Bloqueio temporário após N tentativas falhas (Brute-force protection).

---

## 6. Estratégia de Permissões

Um sistema híbrido de **RBAC (Role-Based Access Control)** e **PBAC (Permission-Based Access Control)** com escopo de unidade.

1. **Permissões (PBAC)**: São as ações granulares do sistema (ex: `os:create`, `os:read`, `finance:delete`, `inventory:read`).
2. **Cargos (RBAC)**: Agrupamentos de permissões. O sistema terá cargos padrão (Administrador, Mecânico, Recepcionista) e a possibilidade de o Proprietário criar cargos customizados.
3. **Atribuição Multiunidade**: Um usuário recebe um Cargo vinculado a uma ou mais Unidades. 
   - *Exemplo*: João é "Gerente" na Unidade A e "Mecânico" na Unidade B. O sistema avalia as permissões dinamicamente dependendo da unidade da ação atual.
4. **Super Admin (Proprietário)**: Ignora verificações e tem acesso total ao `tenant`.
5. **Auditoria**: O ID do usuário, `tenant_id`, timestamp e payload alterado serão gravados de forma assíncrona (via Spring Data Envers ou eventos de domínio) para todas as ações de escrita (POST/PUT/DELETE) nas entidades críticas (Financeiro, Estoque, Permissões).

---

## 7. Roadmap de Desenvolvimento

O desenvolvimento será focado em entregas incrementais de valor (MVP e Evoluções).

### Fase 1: Fundação & Autenticação (Semanas 1-4)
- Setup da infraestrutura (Docker, Repositórios, CI/CD).
- Implementação da arquitetura base (Spring Boot, React, roteamento).
- Módulo IAM: Autenticação, gestão de usuários, controle de permissões.
- Estrutura Multi-Tenant com RLS no PostgreSQL.

### Fase 2: CRM & Operações Core (Semanas 5-9)
- Módulo CRM: Clientes e Veículos (CRUD, histórico).
- Módulo Operations: Criação de Orçamentos, fluxo de aprovação e Ordens de Serviço (OS).
- Gestão de status de OS e delegação de responsáveis.

### Fase 3: Estoque & Integração Operacional (Semanas 10-13)
- Módulo Inventory: Cadastro de produtos/peças, entradas e saídas.
- Integração: Baixa automática de estoque ao utilizar peças em uma OS.
- Controle de fornecedores e alertas de estoque mínimo.

### Fase 4: Financeiro & Assinaturas (Semanas 14-18)
- Módulo Finance: Contas a pagar/receber, fluxo de caixa e DRE simplificado.
- Integração Financeira: Geração automática de contas a receber na conclusão da OS.
- Módulo Billing: Planos de assinatura do SaaS e integração do checkout próprio com PagArme.

### Fase 5: Dashboard, IA & Polimento (Semanas 19-22)
- Módulo Dashboard: Indicadores em tempo real, gráficos operacionais e financeiros (visão matriz/filial).
- Módulo AI: Implementação do assistente virtual para diagnósticos e extração de insights gerenciais.
- Auditoria avançada, testes de carga e ajustes de UX/UI.
