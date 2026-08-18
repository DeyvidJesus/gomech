# Desenvolvimento Local de Banco de Dados

Para garantir um ambiente de desenvolvimento limpo, isolado e consistente entre a equipe, o desenvolvimento local da GoMech V2 utiliza um banco de dados PostgreSQL executado via **Docker Compose**.

## 1. PostgreSQL Local

A stack local imita a versão alvo da produção (PostgreSQL 16) sem a necessidade de instalar binários diretamente na máquina host do desenvolvedor.

- **Porta:** 5432 (Mapeada para o host local).
- **Usuário Padrão:** `postgres`
- **Senha Padrão:** `postgres`
- **Nome do Banco:** `gomech_db`

*(Nota: Estas credenciais são exclusivas do ambiente local. Ambientes superiores possuem senhas injetadas via Secret Manager).*

---

## 2. Docker Compose

O arquivo `docker-compose.yml` localizado na raiz da pasta `backend/` configura o serviço:

```yaml
version: '3.8'

services:
  postgres:
    image: postgres:16-alpine
    container_name: gomech_postgres
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: gomech_db
    ports:
      - "5432:5432"
    volumes:
      - pg_data:/var/lib/postgresql/data
    restart: unless-stopped

volumes:
  pg_data:
```

### Comandos de Gestão

- Subir o banco em background: `docker-compose up -d`
- Parar o banco: `docker-compose stop`
- Derrubar o banco e apagar os dados (Wipe total do db local): `docker-compose down -v`

---

## 3. Volumes (Persistência)

Ao observar o arquivo compose, o volume nomeado `pg_data` é criado.
Ele garante que mesmo que o container `gomech_postgres` pare ou seja deletado, os dados continuarão existindo e serão re-anexados quando ele subir novamente.

**Para resetar o banco do zero**, destruindo o volume e re-executando as migrations limpas pelo Flyway:
`docker-compose down -v && docker-compose up -d`

---

## 4. Backup Local (Opcional para desenvolvedores)

Caso o desenvolvedor tenha gerado uma massa de dados muito específica para um teste e precise salvá-la:

**Para criar um dump do schema + dados (usando a ferramenta de dentro do container):**
```bash
docker exec -t gomech_postgres pg_dump -U postgres -d gomech_db -F c > dump_local_$(date +%Y%m%d).sql
```

*(O comando extrai os dados via stdout para um arquivo na máquina local).*

---

## 5. Restore Local

Para carregar o dump na máquina de outro desenvolvedor, garantindo que o volume local foi criado e a base está limpa:

```bash
docker exec -i gomech_postgres pg_restore -U postgres -d gomech_db -1 < dump_local.sql
```
