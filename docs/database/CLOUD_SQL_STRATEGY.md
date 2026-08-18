# Estratégia Google Cloud SQL

A GoMech V2 hospedará seu banco de dados primário (PostgreSQL 16) no serviço totalmente gerenciado **Google Cloud SQL for PostgreSQL**.

Esta estratégia baseia-se na escalabilidade progressiva, dividindo a topologia por ambientes para equilibrar Custo vs Confiabilidade.

---

## 1. Ambientes

### 1.1 Development (Dev)
- **Objetivo:** Testes contínuos e ambiente isolado que os desenvolvedores conectam caso não utilizem o docker-compose, ou para o servidor de integração contínua (CI).
- **Topologia:**
  - Instância Single-Zone (Sem Alta Disponibilidade / Passiva).
  - Shape da máquina: *Shared Core* (`db-f1-micro` ou `db-g1-small`).
  - Armazenamento: SSD (Mínimo de 10GB).
  - Conexão: Apenas rede privada e Cloud SQL Auth Proxy.

### 1.2 Staging (Homologação)
- **Objetivo:** Réplica funcional exata de produção para QA e testes do cliente/PO. Pode sofrer resets sob demanda.
- **Topologia:**
  - Instância Single-Zone.
  - Shape da máquina: Customizada com baixa alocação (`db-custom-1-3840` - 1 vCPU, 3.75GB).
  - Armazenamento: SSD dinâmico escalável automaticamente (Auto-storage increase).

### 1.3 Production (Produção Real)
- **Objetivo:** O coração do SaaS Multi-Tenant. Requer SLAs garantidos e zero interrupção.
- **Topologia:**
  - Instância Multi-Zone (HA Habilitado).
  - Shape inicial: *Dedicated Core* (ex: `db-custom-2-7680` ou superior conforme crescimento).
  - Armazenamento: SSD provisionado com limite alto e Auto-increase ativo.
  - Conexões: Estritamente privadas (VPC Peering/Serverless VPC Access para o Cloud Run). IP Público desabilitado.

---

## 2. Configurações Estruturais da Cloud SQL

### 2.1 Alta Disponibilidade (High Availability - HA)
Para a instância de Produção, a configuração de HA do Google prevê a existência de uma instância passiva idêntica em uma zona adjacente (ex: `sa-east1-a` para `sa-east1-b`).

- **Mecanismo:** Os dados no disco síncrono são espelhados de forma síncrona.
- **Failover:** Se o Cloud SQL detectar falha no Master ou uma queda zonal do Google, ele redireciona a conexão automaticamente para o Standby em ~60 segundos. Como utilizamos `HikariCP` no Spring Boot, ele reestabelecerá os pools assim que a conexão retornar.

### 2.2 Política de Backup
Para Produção:
- **Backups Automatizados:** Snapshot diário (agendado fora do horário de pico, ex: 03:00 AM).
- **Retenção:** 7 a 30 dias de snapshots retidos.

### 2.3 Disaster Recovery (PITR)
- O **Point-in-time recovery (PITR)** estará ativado para a instância de produção.
- O PITR salva os registros de Write-Ahead Log (WAL) contínuos no Cloud Storage.
- **Vantagem:** Se um bug na aplicação rodar um `DELETE FROM customers` (sem soft delete) as 15:43, a equipe pode realizar um PITR instruindo o Cloud SQL a gerar uma nova instância exatamente com os dados restabelecidos de 15:42:59, salvando os dados dos clientes e gerando um downtime apenas na re-configuração de IP/Hostname.
