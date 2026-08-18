# Operações de Banco de Dados

Este documento rege a manutenção, monitoramento contínuo e tratativas operacionais no banco de dados da GoMech V2, visando desempenho com o crescimento massivo de volumes de dados provenientes de milhares de oficinas.

---

## 1. Monitoramento e Observabilidade

### 1.1 Cloud Operations Suite
O **Cloud SQL** no Google Cloud exporta continuamente telemetria para o Cloud Monitoring.

As métricas vitais a serem criadas via Dashboards Customizados incluem:
- **CPU Utilization:** Mantê-la operando com pico máximo de ~70%. Constante acima disso requer escalabilidade vertical.
- **Memória & Conexões Ativas:** Evitar estrangulamento. O HikariCP na aplicação regula conexões paradas (Idle), mas crescimento da API pode saturar o Connection Pool do Banco.
- **Slow Queries (Consultas Lentas):** O recurso *Cloud SQL Insights* e a extensão interna `pg_stat_statements` estarão ativos para ranquear queries que estão levando demasiados segundos. Se uma listagem de Clientes ou Estoque aparecer aqui, requer inserção de um índice apropriado.

---

## 2. Crescimento de Dados e Índices

Em arquiteturas B2B Multi-Tenant, o tamanho das tabelas cresce de forma logarítmica.

- **Criação Racional de Índices (B-Tree):** Todo índice ocupa memória RAM e reduz a velocidade de `INSERT`s em prol da leitura. Um índice só deve ser criado em colunas frequentemente usadas no `WHERE` de rotas intensivas da API.
- Todos os índices globais **devem** ser pré-fixados com `tenant_id` para bater exatamente com a execução do RLS do Hibernate. Exemplo: `CREATE INDEX idx_vehicle_tenant_license ON vehicles(tenant_id, license_plate) WHERE deleted_at IS NULL;`

### 2.1 Estratégia de Particionamento (Future Scale)
Tabelas transacionais de alto volume e que não são editadas retroativamente adotarão particionamento de tabela do PostgreSQL (`PARTITION BY RANGE`).
- Tabela candidata 1: `audit_logs` (Particionada por Mês).
- Tabela candidata 2: `financial_transactions` (Particionada por Ano fiscal).

Isso impede que uma pesquisa transacional trave lendo 50 milhões de linhas antigas do sistema, mantendo ativas no escopo de acesso apenas as partições recentes.

---

## 3. Gestão de Backup e Restore Manual

Apesar da automação do GCP (veja `CLOUD_SQL_STRATEGY.md`), em eventos críticos as operações de DevOps poderão exigir manipulação manual via **Cloud Storage**.

- **Exportação:** Dumps de Staging/Prod usam o formato nativo com compactação para enviar ao Storage via utilitário CLI `gcloud`.
  - Ex: `gcloud sql export sql gomech-prod-db gs://gomech-backups/dump_$(date).sql.gz --database=gomech_db`

- **Importação Controlada (para Staging):** Caso necessário copiar os dados anonimizados da Produção para a base de Staging:
  - Ex: `gcloud sql import sql gomech-staging-db gs://gomech-backups/dump_anonimizado.sql.gz --database=gomech_db`

---

## 4. Otimização Periódica

A manutenção de tabelas (Vacuuming) no PostgreSQL limpa as tuplas invisíveis/órfãs geradas pelos UPDATEs/DELETEs. O `autovacuum` estará ativado e configurado de forma moderadamente agressiva no Cloud SQL, de modo a evitar "Table Bloat" que corrompe o uso da indexação.
