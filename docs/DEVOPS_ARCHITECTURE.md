# GoMech V2 - Arquitetura DevOps

Este documento define a estratégia, o pipeline e os fluxos de trabalho de DevOps para o ciclo de vida de desenvolvimento e entrega da GoMech V2. As práticas visam maximizar a agilidade e segurança na entrega contínua do SaaS.

**Ferramental:** GitHub, GitHub Actions, Docker, Google Cloud Run, Cloud SQL, Cloud Storage.

---

## 1. Branch Strategy (Estratégia de Ramificação)

A GoMech adotará o modelo de **GitHub Flow (Trunk-Based Development simplificado)**. O objetivo é evitar "Merge Hell" provocado por branches de vida longa.

- **`main`**: É a única ramificação perene (long-lived) e reflete a fonte oficial da verdade. O código nela contido deve estar sempre em estado implantável (deployable).
- **Branches Temporárias (`feature/*`, `fix/*`, `chore/*`)**: Desenvolvedores ramificam exclusivamente a partir de `main`. O trabalho local deve ser curto (idealmente merges diários ou a cada poucos dias).
- **Integração (Pull Requests)**: Nenhum push direto na `main` é permitido. Todo código deve ser mesclado através de um *Pull Request* (PR), obrigatoriamente aprovado por code review e passando nas checagens automáticas da pipeline de CI.

---

## 2. Environments (Ambientes)

- **`staging` (Homologação)**: Espelho funcional de produção com base de dados reduzida ou anonimizada. Usado internamente para Q.A. e testes finais antes da liberação. Pode ser abastecido automaticamente ao abrir ou aprovar um PR.
- **`production` (Produção)**: Ambiente real, isolado logicamente em um Projeto GCP à parte. Recebe tráfego exclusivo dos Tenants da GoMech. Modificações só ocorrem via *Continuous Deployment*.

---

## 3. Continuous Integration (CI Pipeline)

O Pipeline de Integração Contínua (gerenciado via **GitHub Actions**) roda a cada commit enviado a um Pull Request aberto.

**Passos do Workflow:**
1. **Linting e Code Analysis**: Validação estática de código (ESLint/Prettier no React e Checkstyle/SonarQube no Java).
2. **Build e Testes (Frontend)**: Validação de tipos do TypeScript e execução de testes unitários dos componentes React.
3. **Build e Testes (Backend)**: Compilação do Spring Boot, testes unitários (JUnit) e Testes de Integração automatizados (usando *Testcontainers* para subir instâncias efêmeras isoladas de PostgreSQL via Docker, testando queries do banco sem necessidade de mock).
4. **Validação de Build de Imagens**: O `Dockerfile` é testado localmente no runner do GitHub para garantir que não haverá quebras na compilação do container durante o CD.

---

## 4. Continuous Deployment (CD Pipeline)

O Pipeline de Entrega Contínua será acionado imediatamente após o merge de um Pull Request validado para a ramificação `main` (ou na geração de uma *Tag Release*, como `v1.2.0`).

**Passos do Workflow:**
1. **Autenticação Segura (GCP)**: O GitHub Actions não usará chaves JSON fixas (*Service Account Keys*). A integração será via **Workload Identity Federation**, emitindo tokens temporários curtos baseados na permissão estrita do repositório GitHub de agir sobre o Projeto Cloud.
2. **Construção de Artefatos**: A imagem Docker do Backend Spring Boot é compilada e enviada para o **Google Artifact Registry (GAR)**. O build final otimizado do React é gerado.
3. **Migração de Banco de Dados**: Um *Cloud Run Job* efêmero ou um comando de migração (ex: Flyway/Liquibase) roda as migrações mais recentes no banco **Cloud SQL**. O CD só prossegue se a migração ocorrer com sucesso.
4. **Implantação (Deployment)**: 
   - A nova imagem Docker é roteada para iniciar contêineres no **Cloud Run**.
   - Os arquivos estáticos gerados na compilação do React são sincronizados (upload) em um bucket do **Cloud Storage** protegido por CDN (Cloud CDN) ou via Firebase Hosting nativo, efetuando *cache invalidation* imediato.

---

## 5. Secrets Management (Gestão de Segredos)

- **Segredos de Infraestrutura/Deploy**: Tokens, nomes de projeto e credenciais que habilitam o GitHub Actions a falar com provedores, além de variáveis de Build temporárias, são salvos isoladamente nos **GitHub Secrets**.
- **Segredos de Execução (Runtime)**: Chaves de API de terceiros (Gemini, PagArme, SendGrid), chaves criptográficas JWT e as credenciais reais do Banco de Dados Cloud SQL **nunca** existirão no código ou no GitHub Actions. Elas residirão integralmente no **Google Secret Manager**. 
- **Injeção de Runtime**: Na subida da imagem no Cloud Run, o Google injeta os valores do Secret Manager de forma silenciosa como variáveis de ambiente no container Spring Boot, garantindo isolamento total.

---

## 6. Release Strategy (Estratégia de Liberação)

Para garantir estabilidade máxima no serviço multi-tenant:

1. **Zero-Downtime Deployments**: Tanto o banco de dados quanto a API suportam operações ininterruptas. As migrações do PostgreSQL devem ser sempre retrocompatíveis (ex: adicionar colunas não remove as antigas imediatamente).
2. **Canary Releases (Cloud Run)**: O Cloud Run suporta roteamento de tráfego percentual nativo. Atualizações sensíveis podem ser liberadas para `main` transferindo, por exemplo, apenas 10% ou 25% do tráfego para a nova versão da API. Se os logs de monitoramento acusarem pico de exceções (Error Rate alto), efetua-se um rollback sumário para a revisão anterior (que não é destruída). Se não houver problemas, 100% da carga é redirecionada.
3. **Rollbacks**: Em caso de anomalia catastrófica na `main`, o GitHub Actions pode ser acionado retroativamente em uma Tag anterior (ou via botão nativo no console do GCP) para forçar o direcionamento imediato para o container íntegro que já se encontra armazenado no Artifact Registry.
