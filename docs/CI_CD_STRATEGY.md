# Estratégia de CI/CD - GoMech

Este documento detalha a estratégia completa de Integração Contínua e Entrega Contínua (CI/CD) para a plataforma GoMech, baseada em um stack moderno (React, Spring Boot, PostgreSQL, Docker) e provisionada no Google Cloud Platform (GCP).

---

## 1. Ambientes (Environments)

A infraestrutura é segregada em dois ambientes distintos, isolados logicamente para garantir segurança e validação adequada antes de qualquer impacto aos clientes finais.

*   **Development (Staging / Dev)**
    *   **Propósito:** Validação contínua, testes de integração, Quality Assurance (QA) e homologação.
    *   **Infraestrutura GCP:** Projeto isolado ou isolamento lógico via VPC/Cloud Run com banco de dados contendo dados anonimizados ou sintéticos.
    *   **Gatilho de Deploy:** **Automático** após qualquer *merge* na branch principal (`main`).

*   **Production (Prod)**
    *   **Propósito:** Ambiente live que atende os locatários reais (Tenants).
    *   **Infraestrutura GCP:** Projeto GCP de Produção totalmente isolado. Instâncias de Cloud SQL dedicadas com alta disponibilidade (HA) ativada.
    *   **Gatilho de Deploy:** Requer **aprovação manual** (Manual Approval) por um responsável antes da aplicação das mudanças.

---

## 2. Fluxo de Branches (Branch Flow)

Adotaremos um modelo derivado do **GitHub Flow**, focado em simplicidade e entregas rápidas (Trunk-Based Development), evitando branches de longa duração.

*   **`main`**: A branch principal que reflete o código implantável e dita a base para o ambiente de *Development*.
*   **Branches Efêmeras (`feature/*`, `bugfix/*`, `hotfix/*`)**: Criadas estritamente a partir da `main`. É onde o trabalho diário ocorre.
*   **Tags de Release (`v1.0.0`, `v1.1.0`)**: Pontos na história da `main` que demarcam o código exato submetido e aprovado para *Production*.

### Ciclo de Vida do Código:
1. O desenvolvedor cria uma branch `feature/novo-modulo` a partir da `main`.
2. Ao finalizar o desenvolvimento, abre-se um **Pull Request (PR)** para a `main`.
3. O PR dispara a etapa de Integração Contínua (CI) que barra o merge se algum teste falhar.
4. Após revisão humana (Code Review) e CI verde, o PR sofre merge.
5. O merge na `main` dispara o CD automático para **Development**.

---

## 3. Fluxo de Deploy (Deploy Flow)

O orquestrador escolhido para toda a esteira é o **GitHub Actions**. O ciclo é dividido nas etapas de validação e entrega.

### CI: Validação de Pull Request
Sempre que há commits ou abertura de PR:
1. **Frontend (React):** Executa linting (`eslint`), verificação do TypeScript (`tsc --noEmit`) e testes unitários.
2. **Backend (Spring Boot):** Executa compilação (Maven/Gradle), testes unitários (JUnit) e cobertura de código.
3. **Containerização (Docker):** Realiza o build de teste (sem push) da imagem para garantir que o `Dockerfile` está funcional.

### CD: Deploy Automático (Development)
Sempre que há um merge na `main`:
1. **Autenticação:** Conexão com o GCP feita via **Workload Identity Federation** (troca de tokens via OIDC, sem salvar senhas de longa vida no GitHub).
2. **Build & Push:** Construção das imagens Docker definitivas do Backend (e do Frontend, dependendo da estratégia de hospedagem) e envio para o **Google Artifact Registry (GAR)**, etiquetadas com o SHA do commit.
3. **Database Migration:** Execução das ferramentas de migração de schema (Flyway ou Liquibase) conectando ao Cloud SQL de Development, aplicando as alterações pendentes.
4. **Deploy Application:** Lançamento de uma nova revisão no **Google Cloud Run** utilizando a imagem do Artifact Registry gerada no passo anterior. Todo o tráfego é direcionado para ela automaticamente.

### CD: Deploy para Produção (Aprovação Manual)
Sempre que uma tag de release é criada (ex: `v2.1.0`) ou o deploy é disparado sob demanda:
1. **Manual Approval (GitHub Environments):** A pipeline é paralisada na etapa "Production". Um membro autorizado (ex: Tech Lead, DevOps) precisa acessar o GitHub e aprovar manualmente a continuação da execução.
2. **Promoção de Imagem:** Evita-se fazer rebuild. A mesma imagem testada em Dev no Artifact Registry é taggeada para a release atual.
3. **Migração Crítica (Cloud SQL):** O banco de produção recebe o Flyway/Liquibase.
4. **Deploy Final (Cloud Run):** A nova revisão é ativada no Cloud Run de produção com zero downtime.

---

## 4. Estratégia de Rollback

Incidentes em produção exigem resposta imediata. A infraestrutura do GCP provê mecanismos nativos para reversão rápida:

*   **Rollback de Aplicação (Cloud Run):**
    *   Sendo serverless e imutável, o Cloud Run retém revisões anteriores.
    *   Em caso de instabilidade (ex: pico de erros 500 na nova versão), o rollback consiste apenas em alterar a divisão de tráfego (Traffic Splitting) diretamente no console do Cloud Run, ou via comando/pipeline, apontando **100% do tráfego para a revisão anterior** que estava estável. A ação demora poucos segundos.
*   **Rollback de Banco de Dados (Cloud SQL):**
    *   *Prevenção (Regra de Ouro):* Migrações de banco **não devem ser destrutivas**. Ao renomear ou excluir tabelas/colunas, faça em múltiplas fases (ex: criar coluna nova e conviver com as duas, migrar os dados por background, e na próxima release excluir a antiga). Isso garante que o código antigo, via rollback do Cloud Run, não quebre ao encontrar uma tabela faltando.
    *   *Recuperação de Desastre:* Caso dados tenham sido efetivamente corrompidos, aciona-se o **Point-in-Time Recovery (PITR)** nativo do Cloud SQL para restaurar a instância inteira para os minutos que antecederam o deploy problemático.

---

## 5. Gestão de Secrets (Segurança)

Não guardamos configurações sensíveis em texto puro ou no repositório. A estratégia é descentralizada conforme a etapa:

1.  **GitHub Secrets:** Contém variáveis que viabilizam as pipelines (ex: Nomes de projetos, ID do Workload Identity Pool, URLs de banco temporárias para testes).
2.  **Google Secret Manager (GCP):** O cofre definitivo de produção. Armazena as reais credenciais do Cloud SQL (usuário, senha, conexão), as chaves secretas de assinatura de JWT e tokens de APIs de terceiros.
3.  **Resolução em Runtime:** O serviço do Cloud Run de Produção tem permissões IAM estritas (Service Account próprio). Ao iniciar o contêiner do Spring Boot, o GCP busca os valores do Secret Manager e os injeta transparentemente como variáveis de ambiente no container, mantendo o trânsito dessas chaves invisível para o ambiente de CI.

---

## 6. Observabilidade

O entendimento sobre a saúde da plataforma será consolidado na suíte nativa **Google Cloud Observability (antigo Stackdriver)**.

*   **Logs Estruturados (Cloud Logging):** O Spring Boot e o React estarão configurados para gerar logs no formato JSON. Isso permite que o GCP os indexe, facilitando a filtragem por severidade, ID do Tenant (`tenant_id`), ou ID da requisição em dashboards centralizados.
*   **Métricas de Saúde (Cloud Monitoring):** Monitoramento automático do uso de CPU, concorrência de requisições, latência de p95 e consumo de memória do Cloud Run. Monitoramento das transações do PostgreSQL (Cloud SQL).
*   **Alertas Inteligentes (Alerting):** Configuração de canais de notificação (Email/Slack/Discord) disparados por anomalias, como:
    *   Error Rate (erros HTTP 5xx) que ultrapassem 1% de todas as requisições em 5 minutos.
    *   Banco de dados alcançando limites preestabelecidos de CPU ou tamanho de disco.
    *   Falhas sistêmicas na pipeline do GitHub Actions no ambiente de *Production*.
