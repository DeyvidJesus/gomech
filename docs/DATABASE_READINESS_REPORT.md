# Relatório de Prontidão do Banco de Dados (Database Readiness Report)

Este documento sumariza as ações realizadas na fundação da arquitetura de Banco de Dados da GoMech V2, além dos problemas encontrados e os riscos mapeados para as próximas fases do projeto.

---

## 1. Melhorias Aplicadas

- **Adoção do Flyway:** A propriedade legada e perigosa `spring.jpa.hibernate.ddl-auto=update` foi removida em prol do controle estrito de versão via Flyway. A migração inicial (`V1__Initial_Schema.sql`) já reflete o Domain-Driven Design (DDD) com isolamento Multi-Tenant.
- **Isolamento de Ambientes:** Foram configurados perfis independentes no Spring Boot (`local`, `dev`, `staging`, `prod`) garantindo conexões seguras e limitadas.
- **Docker Compose Local:** Criado ambiente local autônomo (PostgreSQL 16) encapsulado no `docker-compose.yml`, desobrigando a instalação física do SGDB nos computadores dos desenvolvedores.
- **Tipagem UUID:** Todas as chaves primárias do sistema foram modeladas com `UUID` para assegurar unicidade global e proteção de scraping de APIs (vazamento de volumetria de negócio).
- **Trilha de Auditoria Universal:** Incorporação das colunas de rastreio de tempo (`created_at`, `updated_at`, `deleted_at`) e da tabela dedicada `audit_logs` para conformidade com a LGPD.

---

## 2. Problemas Encontrados no Código Legado

> [!WARNING]
> A inicialização da aplicação está falhando localmente com a exceção: `SessionFactory configured for multi-tenancy, but no tenant identifier specified`.

**Diagnóstico:** 
O artefato legado `DataLoader` tenta realizar injeções e consultas (`tenantRepository.count()`) durante o boot do Spring. Entretanto, como o Hibernate foi configurado (via anotação `@TenantId` da V2) para exigir contexto Multi-Tenant (ex: `CurrentTenantIdentifierResolver`), e como no boot não existe nenhuma requisição HTTP ou Token JWT para definir quem é o tenant logado, a query inicial quebra a inicialização da aplicação.

---

## 3. Riscos Mapeados (SaaS Multi-Tenant)

- **Idempotência no DataLoader:** O script de carga (`DataLoader`) precisa ser refatorado para ou (1) Mockar o contexto de Tenant durante sua execução injetando um ID temporário global ou (2) Ter sua lógica extraída puramente para scripts do Flyway (ex: `V2__Insert_System_Defaults.sql`).
- **Gargalo no Cloud SQL:** A modelagem atual em `production` dependerá puramente da indexação B-Tree. Como a plataforma escalará para milhares de oficinas, tabelas como `inventory_movements` se tornarão colossais, recomendando-se atenção no plano de monitoramento de *Slow Queries*.
- **Row Level Security (RLS) nativa:** A política do Hibernate (`@TenantId`) intercepta a aplicação, porém recomendamos avançar em breve para RLS *hard-coded* direto no PostgreSQL (CREATE POLICY) se os painéis analíticos precisarem conectar à base de dados fora da aplicação Spring Boot.

---

## 4. Próximos Passos

1. **Refatorar/Remover o `DataLoader`:** Para destravar a execução do Backend localmente, recomendasse substituir a injeção via código por scripts DML no Flyway (ex: `V2__Insert_Default_Data.sql`).
2. **Setup do CI/CD (GitHub Actions):** Utilizar as credenciais documentadas no `CLOUD_SQL_STRATEGY.md` para finalizar as pipelines de deploy.
3. **Implantação de Filtro de Tenant (IAM):** Finalizar o filtro de Autenticação (`OncePerRequestFilter`) que irá interceptar as requisições web, ler o JWT e popular o `TenantContext` de modo que o Hibernate volte a funcionar plenamente nas requisições REST da aplicação.
