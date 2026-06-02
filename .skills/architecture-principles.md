# Architecture Principles

Toda implementação deve seguir:

## Modular Monolith

Os módulos devem ser isolados.

Exemplos:

- IAM
- CRM
- Vehicles
- Quotes
- Work Orders
- Inventory
- Financial

Nunca acessar tabelas de outros módulos diretamente.

Sempre utilizar serviços de domínio.

---

## Multi-tenancy

Toda entidade de negócio deve possuir:

tenantId

Nenhuma consulta pode ignorar tenantId.

---

## Soft Delete

Nenhuma entidade crítica deve ser removida fisicamente.

Utilizar:

deletedAt
deletedBy

---

## Audit

Toda alteração crítica deve gerar auditoria.