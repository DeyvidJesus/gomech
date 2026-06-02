# PROJECT_CONTEXT.md

# GoMech

## Visão Geral

GoMech é uma plataforma SaaS especializada na gestão operacional, financeira e estratégica de oficinas mecânicas.

O objetivo da plataforma é centralizar todos os processos da oficina em um único sistema moderno, intuitivo e escalável, permitindo que empresas de diferentes tamanhos gerenciem clientes, veículos, estoque, finanças, equipes, serviços e operações diárias.

A plataforma deverá atender desde oficinas independentes até redes com múltiplas unidades.

---

# Público-Alvo

## Oficinas Mecânicas

* Pequenas oficinas
* Médias oficinas
* Grandes oficinas
* Redes de oficinas

## Perfis de Usuário

* Proprietário
* Administrador
* Gerente
* Consultor técnico
* Mecânico
* Estoquista
* Financeiro
* Atendente

---

# Problemas Resolvidos

* Controle operacional descentralizado
* Falta de histórico dos veículos
* Controle inadequado de estoque
* Falta de acompanhamento financeiro
* Baixa conversão de orçamentos
* Ausência de indicadores gerenciais
* Falta de integração entre setores
* Dificuldade na tomada de decisão

---

# Estrutura Multi-Tenant

A plataforma deverá operar em modelo SaaS Multi-Tenant.

Cada empresa possui:

* Usuários próprios
* Clientes próprios
* Veículos próprios
* Estoque próprio
* Financeiro próprio
* Assinatura própria

Os dados de diferentes empresas nunca poderão se misturar.

---

# Multiunidade

Uma empresa poderá possuir uma ou mais unidades.

Exemplos:

* Matriz
* Filiais
* Centros de serviço

Os módulos deverão permitir:

* Visualização consolidada
* Visualização individual por unidade
* Comparativos entre unidades

---

# Módulos do Sistema

## Autenticação e Segurança

Funcionalidades:

* Login
* Cadastro
* Recuperação de senha
* Gestão de sessões
* Gestão de dispositivos
* Controle de permissões
* Gestão de cargos

---

## Dashboard

Funcionalidades:

* Indicadores operacionais
* Indicadores financeiros
* Atividades recentes
* Gráficos
* Widgets customizáveis
* Visão consolidada por empresa
* Visão por unidade

---

## Clientes

Funcionalidades:

* Cadastro
* Importação
* Histórico
* Dados de contato
* Relacionamento com veículos
* Histórico financeiro

---

## Veículos

Funcionalidades:

* Cadastro
* Histórico de manutenção
* Histórico de serviços
* Quilometragem
* Documentação
* Fotos
* Relacionamento com clientes

---

## Orçamentos

Funcionalidades:

* Criação
* Edição
* Aprovação
* Reprovação
* Compartilhamento
* Conversão para Ordem de Serviço

---

## Ordens de Serviço

Funcionalidades:

* Abertura
* Planejamento
* Execução
* Conclusão
* Acompanhamento por status
* Responsáveis
* Peças utilizadas
* Serviços executados

---

## Estoque

Funcionalidades:

* Controle de produtos
* Entradas
* Saídas
* Inventário
* Fornecedores
* Alertas de estoque mínimo
* Movimentações

---

## Financeiro

Funcionalidades:

* Receitas
* Despesas
* Fluxo de caixa
* Contas a pagar
* Contas a receber
* DRE simplificado
* Indicadores financeiros

---

## Agenda

Funcionalidades:

* Agendamentos
* Distribuição de serviços
* Calendário
* Controle de ocupação

---

## Inteligência Artificial

Funcionalidades:

* Diagnóstico assistido
* Sugestões de possíveis falhas
* Geração de relatórios
* Consultas operacionais
* Assistente interno da oficina

---

## Administração

Funcionalidades:

* Gestão de usuários
* Gestão de cargos
* Gestão de permissões
* Gestão de unidades
* Gestão de assinaturas

---

## Assinaturas

Funcionalidades:

* Gestão de planos
* Contratação
* Upgrade
* Downgrade
* Cancelamento
* Histórico de pagamentos

---

## Integrações

Funcionalidades:

* Importação via planilhas
* Integrações externas
* API pública futura
* Integrações com CRMs
* Integrações financeiras

---

# Checkout

A plataforma deverá possuir checkout próprio.

O processamento financeiro será realizado através do gateway PagArme.

Requisitos:

* Cartão de crédito
* PIX
* Assinaturas recorrentes
* Gestão de inadimplência
* Renovação automática

---

# Comunicação

Funcionalidades futuras:

* E-mail
* WhatsApp
* Notificações internas
* Alertas operacionais

---

# Auditoria

Toda ação crítica deverá possuir rastreabilidade.

Exemplos:

* Alteração de valores
* Alteração de estoque
* Alteração financeira
* Exclusões
* Alteração de permissões

---

# Objetivos do Produto

* Reduzir tempo operacional das oficinas
* Melhorar controle financeiro
* Aumentar produtividade
* Melhorar experiência do cliente final
* Centralizar operações
* Fornecer inteligência de negócio
* Escalar para milhares de empresas
* Tornar-se referência em gestão para oficinas mecânicas