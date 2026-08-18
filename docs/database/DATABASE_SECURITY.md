# Segurança do Banco de Dados

Tratando-se de um sistema SaaS B2B, a segurança do banco de dados na GoMech V2 não é apenas de perímetro, mas também granular dentro das próprias tabelas, assegurando aderência completa à LGPD.

---

## 1. Segregação de Tenants (RLS - Row Level Security)

O pilar máximo de isolamento de dados das oficinas baseia-se no recurso **RLS** do PostgreSQL.

### Implementação
1. Toda tabela corporativa obriga a inserção da coluna `tenant_id`.
2. O aplicativo Spring Boot nunca pesquisa dados indiscriminadamente. Um filtro do Hibernate intercepta a query e injeta via comando SET de conexão o parâmetro do Tenant logado (extraído do JWT de autorização do endpoint).
3. O PostgreSQL possui *Policies* (ex: `CREATE POLICY tenant_isolation ON customers USING (tenant_id = current_setting('app.current_tenant')::uuid);`).
4. **Benefício:** Evita incidentes catastróficos. Mesmo se um desenvolvedor escrever uma query falha no código como `SELECT * FROM customers`, o banco retornará unicamente os clientes daquele Tenant específico.

---

## 2. Auditoria de Ações Sensíveis

A Rastreabilidade é fundamental para LGPD e resolução de conflitos gerenciais da Oficina.

- **Tabela Transacional:** O banco conta com uma tabela `audit_logs`.
- Toda ação de mutação (CREATE, UPDATE, DELETE) em rotas críticas (Financeiro, Permissões, Planos) é capturada.
- O registro é em formato **Append-Only** armazenando: Identificador do Usuário (`user_id`), Ação, e as Strings em JSON do estado anterior e do novo estado.
- Estas inserções são assíncronas para não interferir na latência da API.

---

## 3. Conformidade com a LGPD

- **Direito ao Esquecimento:** Embora o padrão arquitetural seja o **Soft Delete** (`deleted_at`), os endpoints administrativos possuem chamadas especiais subjacentes que realizam ofuscação/anonimização de dados pessoais (Nome, CPF, Telefone do Cliente Final da Oficina) caso o mesmo invoque judicialmente seu direito.
- **Log de Acessos:** Leituras de painéis altamente sensíveis (Faturamento) ficam registrados no Logger do GCP (Access Logs estruturados) apontando quem e de onde acessou a informação.

---

## 4. Criptografia

- **Data at Rest (Dados em Repouso):** O Google Cloud SQL (e também os buckets do Cloud Storage) criptografam os discos nativamente através do algoritmo AES-256 no nível do hardware. Nenhuma configuração adicional é exigida.
- **Data in Transit (Dados em Trânsito):** A comunicação entre o Cloud Run (Spring Boot) e o Cloud SQL requer a flag `sslmode=verify-ca` e utiliza túnel privado. A comunicação não flutua em internet pública.
- **Senhas:** A coluna `password_hash` da tabela `users` usa a biblioteca robusta de Hashing nativa do Spring Security (`BCrypt` com work factor ajustável), frustrando tentativas de engenharia reversa via Rainbow Tables no caso altamente improvável de dump ilícito do banco.

---

## 5. Controle de Acesso (Database Users)

O banco na nuvem não opera com um único "Super User" nas rotinas.

- **Admin User:** Permissão integral para alterar esquemas (Usado pelo Flyway durante migrações apenas).
- **Application User:** Usado pelo Spring Boot. Tem poderes de DML (Insert/Update/Select/Delete) nas tabelas designadas, mas não pode usar comandos `DROP TABLE` ou `ALTER TABLE`.
- **Read-Only User (Analytics):** No futuro, para o dashboard analítico ou importação para BigQuery, será usado um usuário de acesso apenas de leitura (SELECT).
