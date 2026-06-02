# GoMech Design System

Este documento detalha as fundações visuais (Design Tokens) extraídas do arquivo Figma do projeto GoMech. Ele serve como a fonte da verdade para cores, tipografia, espaçamentos e grids, garantindo consistência em toda a aplicação.

## 1. Cores (Color Palette)

O sistema de cores da GoMech é focado em clareza, confiança e modernidade.

### Cores Primárias (Primary)
- **Primary Base:** `#2563EB` (Azul Interativo - usado em botões primários e links)
- **Primary Dark:** `#4285F4` (Variante hover/ativa)

### Cores de Sucesso e Ação (Success / Action)
- **Success Green:** `#34A853` (Indicadores positivos, status "Concluído")
- **Green Dark:** `#166534`, `#065F46` (Variações para contraste de texto)
- **Green Light:** `#A7F3D0` (Fundos de alertas positivos)

### Cores de Erro e Alerta (Danger / Warning)
- **Danger Red:** `#BA1A1A` (Ações destrutivas, erros, status "Atrasado")
- **Warning Orange:** `#A33E00` (Avisos, status "Pendente")

### Tons Neutros e Superfícies (Grays / Neutrals)
- **Background App:** `#F9FAFB` (ou similar muito claro, base da aplicação)
- **Surface / Cards:** `#FFFFFF`
- **Text Primary:** `#121C2A` (Textos de títulos e conteúdos principais)
- **Text Secondary:** `#3D4756`, `#555F6F` (Textos de apoio e labels secundárias)
- **Borders & Dividers:** `#BDC7D9`, `#6B7280` (Linhas de tabelas e separadores)

---

## 2. Tipografia (Typography)

O sistema tipográfico utiliza duas famílias principais de fontes para criar hierarquia visual:
- **Manrope:** Utilizada primariamente para Cabeçalhos (Headings) e Números de Destaque (KPIs).
- **Inter:** Utilizada primariamente para corpo de texto (Body), controles de interface e tabelas.
- **Liberation Mono:** Utilizada esporadicamente para dados tabulares estritos (ex: IDs de pedido, dados técnicos).

### Cabeçalhos (Headings - Manrope)
- **H1:** Bold (700), 48px, Line-height: 56px, Letter-spacing: -2%
- **H2:** Bold (700), 32px, Line-height: 40px, Letter-spacing: -1%
- **H3:** Bold (700) ou SemiBold (600), 24px, Line-height: 32px
- **H4:** Bold (700) ou SemiBold (600), 20px, Line-height: 28px

### Corpo de Texto (Body - Inter)
- **Body Large:** Regular (400) / Medium (500), 16px, Line-height: 24px
- **Body Default:** Regular (400) / Medium (500), 14px, Line-height: 20px
- **Body Small:** Regular (400) / Medium (500), 12px, Line-height: 18px
- **Micro / Caption:** Regular (400), 10px / 11px, Line-height: 14px/16px

### Casos Especiais
- **Status / Labels:** SemiBold (600), 11px/13px, Letter-spacing: 5%, TextCase: UPPER
- **Tabelas Headers:** Medium (500) ou SemiBold (600), 11px/13px, TextCase: UPPER

---

## 3. Espaçamentos (Spacing)

Os espaçamentos (paddings e margins/gaps) seguem estritamente um sistema de **Grid de 4px / 8px**.

### Escala de Espaçamento Base (Tokens)
- **xs:** 4px (Elementos muito próximos, ícones dentro de botões)
- **sm:** 8px (Paddings de células de tabela, botões pequenos, gap de listas)
- **md:** 12px / 16px (Paddings de botões padrão, espaçamento entre componentes filhos)
- **lg:** 24px (Paddings de cards, modais, seções de formulário)
- **xl:** 32px (Paddings estruturais, gaps entre seções grandes do layout)

*(Evidências: A análise dos autolayouts do Figma mostrou uma altíssima repetição de gaps e paddings em 4px, 8px, 12px, 16px e 24px.)*

---

## 4. Grid e Layout

- **Sistema:** Layout fluido com max-width (geralmente centrado a 1280px ou ocupando toda a largura útil em telas grandes).
- **Auto Layouts:** O Figma da GoMech utiliza pesadamente "Auto Layouts" (Flexbox) com direcionamentos em coluna (Column) e linha (Row) com preenchimento em espaço disponível (`Fill Container`).
- **Cards e Superfícies:** Utilizam bordas sutis (1px solid border em `#BDC7D9` ou similar) e *Border Radius* entre 4px e 8px.