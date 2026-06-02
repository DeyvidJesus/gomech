# GoMech Component Library

Este documento cataloga os principais componentes reutilizáveis identificados no design da GoMech. Eles devem ser implementados no frontend (ex: React) como componentes isolados e altamente configuráveis.

## 1. Componentes Estruturais

### 1.1 Cards de KPI (KPI Cards)
- **Função:** Exibir métricas de alto nível no Dashboard (ex: "Active Jobs", "Revenue Today", "CSAT Score").
- **Estrutura:** 
  - Título/Label da métrica (Inter, Uppercase).
  - Valor em destaque (Manrope, grande).
  - Ícone representativo.
  - Indicador de crescimento/queda percentual (Opcional).
- **Variações:** Com e sem overlay de background colorido por trás do ícone.

### 1.2 Timeline do Service Bay (Service Bay Timeline)
- **Função:** Visualização diária de agendamentos por box/mecânico.
- **Estrutura:**
  - Eixo X com horários do dia.
  - Eixo Y com a lista de Bays (Box 1, Box 2).
  - Blocos de serviço (Appointments) coloridos de acordo com o tipo ou status do serviço.
  - Indicador de horário atual (Linha tracejada).

## 2. Formulários e Inputs

### 2.1 Botões (Buttons)
- **Primary Button:** Fundo sólido azul ou verde (dependendo do contexto).
- **Secondary / Outline Button:** Fundo transparente com borda visível, para ações secundárias.
- **Ghost / Text Button:** Apenas texto, geralmente para links como "View Calendar" ou ações menores em tabelas.
- **Icon Buttons:** Botões que contêm apenas um ícone (ex: ações em tabelas, configurações).

### 2.2 Campos de Texto e Inputs
- **Estrutura Padrão:** Label superior, Container do input com borda sutil, ícone interno opcional (ex: ícone de busca).
- **Variações Identificadas:**
  - `Search Input` (Com ícone de lupa e texto de placeholder "Search workshop, jobs, or parts...").
  - `Select/Dropdown` (Com ícone de chevron).

## 3. Exibição de Dados (Data Display)

### 3.1 Tabelas de Dados (Data Tables)
- **Função:** Exibir listas de "Service Orders", "Invoices", etc.
- **Estrutura:**
  - Header da tabela com background ligeiramente mais escuro (ex: `#F9FAFB`). Títulos de coluna em caixa alta (Inter SemiBold).
  - Linhas de dados divididas por borda sutil de 1px.
  - Coluna de Ações dedicada à direita (geralmente com Icon Buttons).
- **Componentes Internos das Tabelas:**
  - **Status Badges:** Pílulas coloridas para indicar status (ex: "In Progress", "Pending").

### 3.2 Badges / Status Pills
- **Função:** Indicação visual rápida de estados ou contagens.
- **Estrutura:** Container com pequeno border-radius, background claro com borda e texto coloridos referentes ao estado.
- **Tipos (Inferidos):** In Progress, Delayed, Completed.

## 4. Navegação

### 4.1 Barra Lateral (Sidebar / Menu)
- Contém itens de navegação principais e configuração de contexto.

### 4.2 Cabeçalho (Top Bar)
- Traz informações do usuário ("Morning, Alex"), breadcrumbs, seletor de perfil e ícones de notificação.

## 5. Feedback e Modais

### 5.1 Modais (Overlays)
- **Função:** Formulários de adição rápida ("ADD NEW") ou confirmação de ações destrutivas.
- **Estrutura:** Overlay escuro na tela toda, container branco centralizado, título, botões de ação na base (Cancelar / Confirmar).

### 5.2 Alertas de Sistema
- Usados para mensagens proativas do sistema (ex: "Seasonal demand expected to drop. Recommend delaying next bulk order.").
