# GoMech V2 - Arquitetura de Infraestrutura (GCP)

Este documento projeta a infraestrutura cloud da plataforma GoMech baseada no **Google Cloud Platform (GCP)**. O design equilibra o menor custo inicial para o MVP, mantendo uma fundação sólida de alta disponibilidade e caminhos diretos para escalabilidade (Growth e Enterprise).

A stack considerada compõe-se de React (Frontend SPA), Spring Boot + Docker (Backend API), PostgreSQL (Banco Relacional) e integrações com Gemini API (Inteligência Artificial).

---

## 1. Definição de Serviços Base (GCP Ecosystem)

Os seguintes serviços gerenciados foram selecionados para minimizar o custo operacional (NoOps/Serverless) mantendo os mais altos padrões de segurança e escala:

- **Frontend Hosting (React)**: **Firebase Hosting**. Extremamente barato, provisiona CDN global automática, SSL gratuito e invalidação de cache atômica a cada deploy.
- **Backend Hosting (Spring Boot Docker)**: **Cloud Run**. Plataforma *Serverless* para containers. Cobra apenas durante o processamento das requisições (*Pay-per-use*), suporta escala até zero (economizando custos fora do horário comercial das oficinas) e escala automaticamente frente a picos de tráfego.
- **Banco de Dados (PostgreSQL)**: **Cloud SQL for PostgreSQL**. Banco de dados totalmente gerenciado.
- **Object Storage**: **Cloud Storage (GCS)**. Para o upload de arquivos da oficina (ex: fotos de avarias, avatares, PDFs de notas fiscais).
- **Secrets Management**: **Secret Manager**. Armazenamento criptografado de credenciais sensíveis (Senha do Banco de Dados, Chave de Assinatura JWT, Chaves de API de Pagamento e Gemini API).
- **Logs & Monitoring**: **Cloud Operations Suite (Cloud Logging & Monitoring)**. Absorve logs do Cloud Run nativamente (estruturados em JSON) e monitora a integridade do banco sem necessidade de instalar agentes.
- **CI/CD**: **GitHub Actions** (integrado via *Workload Identity Federation* ao GCP) ou **Cloud Build** para construir os containers Docker e publicar no Cloud Run e Firebase automaticamente.
- **DNS e SSL**: Domínios gerenciados no **Cloud DNS**. Certificados SSL são provisionados, associados e renovados automaticamente tanto no Firebase Hosting quanto no domínio customizado mapeado ao Cloud Run.

---

## 2. Estratégias de Proteção de Dados

- **Backup**: O Cloud SQL contará com Backups Automatizados diários retidos por no mínimo 7 dias. Habilita-se o **Point-In-Time Recovery (PITR)** baseando-se em WAL (Write-Ahead Logs), permitindo restaurar o banco para qualquer milissegundo em caso de corrupção de dados ou ataque malicioso.
- **Disaster Recovery (DR)**: 
  - *Cold DR (MVP)*: Restauração manual baseada em Snapshot/Backup diário para uma nova região em caso de queda de um datacenter (RTO - Tempo de Retorno de algumas horas).
  - *Hot DR (Enterprise)*: Banco rodando em HA Zonal com réplica inter-regional de *failover* (RTO de minutos).

---

## 3. Evolução Arquitetural

Abaixo o projeto detalhado que permite arrancar com custo ínfimo e escalar gradativamente conforme a aquisição de novas oficinas parceiras.

### Fase 1: Arquitetura MVP (Cost-Effective & Agile)
**Foco**: Viabilidade, custo baixo (cerca de ~US$ 30 - 50/mês a depender do uso), validação de mercado.
- **Frontend**: Firebase Hosting (Plano Spark - Grátis).
- **Backend API**: Cloud Run na região primária (ex: `southamerica-east1` - São Paulo). 
  - Configuração: O mínimo de instâncias será `0` (Scale-to-zero ativado). Custo apenas computado nos milissegundos em que uma requisição está ativa. Para melhorar o tempo de *Cold Start* do Java, recomenda-se a compilação nativa com *GraalVM/Spring Native* ou uso de Tiered Compilation e containers leves.
  - Conexão de Banco: O Cloud Run utilizará o conector Cloud SQL Proxy privado nativo (via Unix Domain Sockets) para bater direto no banco sem passar pela internet pública.
- **Banco de Dados**: Cloud SQL PostgreSQL. Instância da família *Shared Core* (ex: `db-f1-micro` ou `db-g1-small`). Single-Zone (Zonal) para não pagar a redundância dobrada durante os primeiros testes beta.
- **Inteligência Artificial**: O módulo de AI baterá na API externa da **Google Gemini** diretamente pelo Spring Boot via requisições HTTPS.

### Fase 2: Arquitetura Growth (Alta Disponibilidade & Performance)
**Foco**: Segurança do dado e resposta rápida para os clientes pagantes estabelecidos.
- **Frontend**: Mantém Firebase Hosting.
- **Backend API**: Cloud Run. 
  - Configuração: Min-instances `> 1` garantindo que não haverá mais penalidade de *Cold Start* para as primeiras requisições matinais. 
  - Integração via Serverless VPC Access Connector ativada, bloqueando acesso direto à internet para os recursos internos (Zero Trust real).
- **Banco de Dados**: Cloud SQL com upgrade para família *Dedicated Core* (ex: 2vCPUs, 8GB RAM). 
  - Habilitação obrigatória da feature **High Availability (HA)** do Google (Provisiona uma instância passiva idêntica em uma zona adjacente da mesma região, roteando a conexão na casa de 30-60 segundos automaticamente caso o servidor primário trave).
- **Cache Local**: Introdução do **Memorystore (Redis)** gerenciado, servindo para invalidação global de sessão JWT, Rate Limiting contra os Tenants (protegendo a infra), e cache de relatórios táticos pesados do Dashboard.

### Fase 3: Arquitetura Enterprise (Escala Massiva & Multi-Região)
**Foco**: Acordos rígidos de SLA (99.99%), processamento maciço multi-tenant de dezenas de milhares de oficinas simultâneas e análises OLAP.
- **Backend API**: 
  - Migração para **GKE (Google Kubernetes Engine) Autopilot** caso a complexidade dos jobs assíncronos e mensageria exija instâncias persistentes finamente controladas, ou adoção de implantação ativa-ativa do Cloud Run em duas regiões (`sa-east1` e `us-east1`).
- **Load Balancing**: **Global Cloud Load Balancer (GCLB)** operando com Cloud Armor (WAF - Web Application Firewall) na borda, barrando DDoS e ataques SQLi/XSS em todos os end-points globais antes de atingirem a API de operações.
- **Banco de Dados**: Instalação de *Read Replicas* em regiões secundárias do Cloud SQL para desviar todas as requisições de Leitura (Consultas, Relatórios Gerenciais e Ordens de Serviço fechadas) enquanto as escritas ocorrem no nó Master (Redução imensa do gargalo principal).
- **Dados & IA (Módulo Analytics)**: Como operações rodarão intensamente, os dados transacionais de relatórios são exportados assincronamente (*Change Data Capture - CDC*) para o **BigQuery**. O BigQuery alimenta de forma eficiente e veloz o **Vertex AI** (Gemini) dentro de contexto corporativo estrito, entregando insights para as oficinas (ex: precificação flutuante de peças sob alta demanda).
