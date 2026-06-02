# GoMech V2 - Frontend Architecture

Este documento define os padrões arquiteturais, a estrutura de pastas e as convenções técnicas do Frontend (SPA) da GoMech V2. Foi baseado no Design System extraído do Figma e na Arquitetura Geral do sistema.

**Stack Principal:** React, TypeScript, TanStack Router (Roteamento), TanStack Query (Data Fetching / Server State).

---

## 1. Estrutura de Pastas e Feature Modules

A aplicação adotará uma arquitetura focada em **Feature Modules** (Feature Slices), espelhando os "Bounded Contexts" definidos no backend, garantindo que componentes fortemente acoplados a um domínio permaneçam coesos.

```text
src/
├── app/                  # Configurações globais (Providers, Router Config, QueryClient)
├── assets/               # Imagens estáticas, fontes (Inter, Manrope), ícones customizados
├── shared/               # Código compartilhado entre módulos (Agnóstico ao negócio)
│   ├── components/       # Component Library da GoMech (Botões, Inputs, Cards, Tabelas)
│   ├── hooks/            # Hooks utilitários globais (useWindowSize, useDebounce)
│   ├── layouts/          # Layouts base (AuthenticatedLayout, PublicLayout)
│   ├── lib/              # Adaptações de bibliotecas (Axios instance, formatações)
│   └── types/            # Tipagens TypeScript globais
│
├── features/             # Módulos Funcionais (Isolados)
│   ├── iam/              # Login, Perfis, Permissões
│   ├── crm/              # Clientes, Veículos
│   ├── operations/       # Orçamentos, Ordens de Serviço (OS), Timeline
│   ├── inventory/        # Catálogo, Movimentações
│   ├── finance/          # Transações, Contas
│   └── billing/          # Assinaturas SaaS
│
└── routes/               # Definições de rota do TanStack Router (File-based routing)
```

Dentro de cada **Feature Module**, a estrutura interna será:
- `api/` (Funções de requisição usando o cliente HTTP, mapeadas para hooks do React Query)
- `components/` (Componentes específicos do domínio, ex: `WorkOrderTimeline`)
- `hooks/` (Hooks customizados da feature)
- `stores/` (State management local do domínio, se necessário)
- `types/` (Interfaces TypeScript das entidades)

---

## 2. Routing (TanStack Router)

A navegação será gerenciada nativamente pelo **TanStack Router** utilizando a abordagem *File-Based Routing*.

- **Type-Safety Absoluto:** Links quebrados, parâmetros ausentes e query strings incorretas serão acusados em tempo de compilação (TypeScript).
- **Layout Routes:** Serão utilizadas rotas sem caminho (ex: `_authenticated.tsx` ou `_dashboard.tsx`) para envelopar partes do sistema com layouts e garantias de sessão sem sujar as URLs.
- **Data Loaders/Prefetching:** O ciclo de vida do router será integrado ao TanStack Query para fazer pré-carregamento de dados críticos antes da transição da página (evitando o "waterfall" de loaders de tela em cascata).

---

## 3. Layouts

Com base no Design System, teremos dois layouts primários:
1. **Public/Auth Layout:** Minimalista, focado na área central para páginas de login, cadastro ou recuperação de senha. Fundo cinza e card centralizado.
2. **Dashboard Layout (Autenticado):**
   - **Sidebar (Menu Lateral):** Elemento de navegação principal entre módulos, abrigando navegação rápida.
   - **Top Bar (Header):** Componente contendo saudações ("Morning, Alex"), indicador visual da Unidade Atual, Breadcrumbs automáticos do Router e perfil de usuário.
   - **Main Content Area:** Container para a renderização das rotas filhas. Todos os paddings e espaços seguirão o Grid padronizado (16px / 24px / 32px) na renderização principal.

---

## 4. Component Library (UI)

O repositório construirá uma biblioteca própria em `src/shared/components`, implementando os requisitos de `COMPONENT_LIBRARY.md` e `DESIGN_SYSTEM.md`. 
- **Tailwind CSS:** Utilizado como motor de estilos, onde os tokens do Figma (`#2563EB`, fontes Manrope/Inter) estarão configurados no `tailwind.config.js`.
- **Anatomia:** Componentes como *Buttons*, *Inputs*, *Badges*, *Modals* e *Data Tables* serão implementados priorizando flexibilidade e composição (podendo utilizar bibliotecas *Headless UI* como Radix UI ou React Aria como fundação acessível, estilizadas com Tailwind).
- Nenhum componente do `shared` fará chamadas à API, sendo puramente de apresentação (Dumb Components).

---

## 5. State Management

Para gerenciamento de estado, aplicaremos o princípio da separação de contextos:

- **Server State (TanStack Query):** É o cérebro da aplicação para dados. Lida com cache, background fetching, paginação e mutações. Nenhum dado do banco viverá em Redux ou Contextos.
- **Client/UI State (Zustand):** Usado apenas para estados globais puramente efêmeros do frontend que afetam múltiplas árvores (Ex: Estado aberto/fechado da Sidebar global, ID da "Unidade Física" atualmente selecionada no combobox global, Tema visual).
- **Component State (React `useState` / `useReducer`):** Estados isolados como o valor de um input sendo digitado, abas de uma tela, aberturas de modais únicos.

---

## 6. Data Fetching

A estratégia foca fortemente em UX proativa:
- **Keys Centralizadas:** As `QueryKeys` serão organizadas por features e entidades (`['workOrders', 'list', { status: 'PENDING' }]`).
- **Mutações (Mutations):** Ao finalizar uma OS ou registrar pagamento, chamaremos `useMutation`. O `onSuccess` dessa mutação deve obrigatoriamente chamar o `queryClient.invalidateQueries` apropriado para garantir que painéis de Dashboard e Tabelas atualizem em tempo real, sem refresh do usuário.
- **Prefetching no Hover:** Ícones ou botões críticos aplicarão `queryClient.prefetchQuery` durante o *onMouseEnter*, permitindo que modais ou novas páginas abram instantaneamente usando o cache momentâneo.

---

## 7. Formulários (Forms)

O sistema lida com cadastros pesados e orçamentos (ex: OS, Inventário).
- **Tecnologias:** `React Hook Form` (para performance de digitação e evitar renders desnecessários) + `Zod` (Validação de Esquemas de Dados).
- **Validação Tipo a Tipo:** O esquema Zod definirá as regras (Mínimo de caracteres, e-mails, validação de Placas ou CNPJ/CPF), gerando a tipagem TypeScript dos formulários e refletindo os DTOs do backend.
- Modais e telas ricas em digitação não perderão performance sob dezenas de campos no componente de Orçamento (Quote).

---

## 8. Permissions (Autorização de UI)

Para espelhar o PBAC do Backend de forma fluida:
- O Contexto de Sessão ou Store Global manterá um Array de permissões atreladas ao usuário (`user.permissions`).
- **Higher-Order Components (HOC) ou Wrappers (`<Can>`)**: Um componente renderizador condicional será criado: `<Can do="os:create"><Button>Add New</Button></Can>`. Caso a permissão não exista, o botão desaparece visualmente para o operador.
- O TanStack Router possuirá proteções em tempo de roteamento (`beforeLoad`), impedindo fisicamente e logicamente que o usuário acesse a página `/finance/reports` se não possuir os privilégios.

---

## 9. Error Handling

- **Error Boundaries:** A aplicação terá um *ErrorBoundary* global raiz (evitando a tela em branco total do React) e *ErrorBoundaries* em nível de rotas (TanStack Router fallback) e de componentes da UI.
- **Intercepção de Requisições:** A instância global do Axios (ou fetch) possuirá interceptadores. 
  - Status `401 Unauthorized`: Força o logout e redirecionamento de tela de login.
  - Status `403 Forbidden`: Aciona telas ou notificações locais de "Acesso Negado".
  - Status `422 Unprocessable Entity`: Os erros de Bean Validation capturados do backend (RFC 7807 Problem Details) serão automaticamente convertidos pelo interceptador para alimentar erros visuais nos campos do React Hook Form.
- **Toast Notifications:** Erros sistêmicos ou de mutações falhas mostrarão notificações efêmeras baseadas nas paletas de Alerta Vermelho/Laranja catalogadas no Design System.
