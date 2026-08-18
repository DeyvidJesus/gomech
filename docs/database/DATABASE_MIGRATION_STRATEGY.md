# Estratégia de Migrações de Banco de Dados (Flyway)

A GoMech V2 utiliza o **Flyway** como a única ferramenta oficial para versionamento e migração do esquema de banco de dados relacional (PostgreSQL).

Nenhuma alteração estrutural no banco de dados deve ser realizada manualmente em qualquer ambiente, e a propriedade `spring.jpa.hibernate.ddl-auto` deve estar permanentemente configurada como `validate` ou `none`.

---

## 1. Convenções Flyway

O Flyway baseia-se em nomenclatura estrita de arquivos para inferir a ordem de execução.

**Formato padrão:** `V<Versão>__<Nome_Descritivo>.sql`
*(Nota: São dois underscores `__` entre a versão e o nome)*

### Nomenclatura de Versão
Utilizamos versionamento semântico sequencial simplificado:
- **V1__Initial_Schema.sql**: Base do sistema (Tabelas essenciais).
- **V2__Add_Customer_Table.sql**: Criação de um novo módulo.
- **V2.1__Add_Phone_To_Customer.sql**: Alteração menor num módulo existente.

### Boas Práticas de Nomenclatura
- Seja descritivo e use inglês: `Add_Column_X_to_Table_Y`, `Create_Inventory_Tables`.
- Nunca modifique um arquivo de migração que já foi mergeado na `main` e implantado. O Flyway validará o checksum e falhará a subida da aplicação caso o arquivo tenha sido modificado.

---

## 2. Estrutura de Diretórios

Os scripts residem no diretório padrão do Spring Boot para o Flyway:

```text
backend/src/main/resources/
└── db/
    └── migration/
        ├── V1__Initial_Schema.sql
        ├── V2__Add_Subscription_Plans.sql
        └── V3__Create_Quotes_And_Work_Orders.sql
```

---

## 3. Ordem de Execução

1. Quando o Spring Boot inicializa, o Flyway assume o controle da conexão via JDBC.
2. O Flyway verifica a tabela interna `flyway_schema_history`.
3. Ele identifica quais scripts no diretório `db/migration` possuem versão superior à última registrada no banco.
4. Os scripts pendentes são executados sequencialmente em uma transação (quando suportado).
5. Após o sucesso de cada script, o Flyway atualiza a tabela de histórico. Se houver falha, ocorre o *rollback* transacional daquele script e o Spring Boot interrompe o start.

---

## 4. Rollback Strategy (Estratégia de Reversão)

Por padrão na versão Open Source, o Flyway não executa `Undo` automático (scripts U__).
Nossa estratégia em caso de falha de migração em produção é baseada em **Fix Forward (Avanço Corretivo)**.

### Se o erro ocorrer durante desenvolvimento local:
1. Apague/Droppe o schema ou container local.
2. Corrija o script.
3. Suba o container/Spring Boot novamente (o Flyway rodará do zero).

### Se o erro ocorrer em Staging/Produção:
1. **Nunca modifique o script problemático já comitado e falho na base.**
2. A aplicação falhará em subir, as requisições continuarão a ser atendidas pela versão/container anterior (Cloud Run não libera tráfego se o container quebra no start).
3. Crie uma **nova** migração (ex: `V3.1__Fix_Failed_Column.sql`) que resolva a anomalia deixada (se a transação falhou em um DDL não-transacional) ou reescreva o comando correto.
4. No caso de corrupção massiva de dados por um DML errado no script de migration, acione a rotina de **PITR (Point-in-Time Recovery)** do Cloud SQL.

---

## 5. Boas Práticas

- **Idempotência Limitada**: Diferente de um script autônomo, scripts de migração não precisam de `IF NOT EXISTS` a não ser que façam parte de um processo complexo de refatoração de dados antigos. O Flyway garante execução única.
- **Separação de DDL e DML**: Evite misturar criação de tabelas (DDL) e inserção massiva de dados (DML) no mesmo script.
- **Backward Compatibility (Retrocompatibilidade)**: Renomear uma coluna ou apagar uma tabela vai quebrar a aplicação que já está no ar antes do novo container subir. Sempre prefira:
  1. Adicionar nova coluna (V1).
  2. Alterar o código para ler da antiga e escrever em ambas.
  3. Migrar os dados em background (V2).
  4. Apagar a coluna antiga (V3).
- **Sem senhas em scripts**: Não insira DML que adicione senhas em plain-text de super-usuários, use `bcrypt` hasheado se precisar criar um usuário padrão via SQL.
