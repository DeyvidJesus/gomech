# GoMech UI Conventions & Visual Patterns

Este documento foca nas práticas, padrões e convenções de interface mapeadas do design, além de apontar oportunidades para simplificação ou melhoria técnica na hora de implementar a plataforma GoMech.

## 1. Padrões Visuais (Visual Patterns)

### 1.1 Hierarquia de Texto
- **Dados Principais vs Secundários:** O sistema frequentemente agrupa dois textos: um valor principal grande e chamativo (Manrope Bold), e uma pequena label explicativa abaixo ou acima (Inter, cor secundária mais clara). 
- **Letras Maiúsculas em Meta-dados:** Cabeçalhos de tabelas, status de badges e labels de KPIs utilizam estritamente texto em maiúsculas (UPPERCASE) com maior espaçamento entre letras (Letter-spacing: 5%). Isso confere um visual mais técnico, estruturado e organizado, ideal para softwares B2B.

### 1.2 Agrupamento de Conteúdo (Cards)
- **Cenário Branco em Fundo Cinza:** Quase todos os blocos de conteúdo são envelopados em containers com background branco e borda sutil ou sombra muito leve, colocados em contraste contra um background geral de aplicação num tom cinza claro (`#F9FAFB`).
- **Gaps Consistentes:** O uso sistemático de `16px` e `24px` de padding cria uma respiração visual contínua, fundamental para densidade de dados sem parecer confuso.

### 1.3 Ícones
- Ícones são usados ostensivamente não apenas para navegação, mas como auxiliares visuais de leitura rápida (ex: gráficos pequenos nos KPI cards, avatares, ou chevrons de status).

---

## 2. Inconsistências Identificadas (Inconsistencies)

- **Famílias de Fontes Concorrentes:** Embora Inter e Manrope sejam as principais, o Figma apresenta pontualmente o uso de `Liberation Mono`. O uso de monoespaço é válido para dados numéricos, porém a mistura de muitas famílias de fontes pode causar peso na performance (carregamento web) e fragmentação visual se não for muito bem restrito a "apenas identificadores únicos" (ex: #ORD-9012).
- **Variações de Padding:** Existem valores incomuns como paddings de `37.77px` ou `3.99px`. Isso provavelmente provém de arrastamento manual ou ícones não padronizados dentro do Figma. 
- **Excesso de Estilos de Texto:** Existem mais de 50 variações brutas de estilo de texto (combinações de tamanho, peso e altura de linha). Isso difere das convenções de sistemas maduros como o Tailwind, que operam com no máximo 10-15 tipos básicos de tamanho/peso.

---

## 3. Oportunidades de Simplificação

- **Padronização Estrita do Grid:** Ao codificar o CSS/Tailwind, todos os espaçamentos não-inteiros (como `3.99px` ou `16.5px`) devem ser ignorados e convertidos de forma coercitiva para os "tamanhos de camiseta" do sistema (ex: arredondar `3.99px` para `4px` (xs), e `16.5px` para `16px` (md)).
- **Consolidação Tipográfica:** Reduzir os 50+ estilos para um conjunto de 8 estilos padrão (`heading-1`, `heading-2`, `body-large`, `body-normal`, `body-small`, `caption`, `label`).
- **Uso de Variáveis CSS Globais:** Toda cor primária (`#2563EB`) e tons de cinza devem ser definidos na raiz do CSS (`:root`), nunca fixos nos componentes, preparando a aplicação desde o início para "Dark Mode" (Tema Escuro) e "White Label" (cores dinâmicas por oficina).
- **Simplificação de Fontes:** Considerar remover `Liberation Mono` e usar a funcionalidade CSS `font-variant-numeric: tabular-nums;` na fonte `Inter`. Isso garante o alinhamento de numerais em tabelas e faturamentos sem precisar carregar um terceiro arquivo de fonte inteiro.
