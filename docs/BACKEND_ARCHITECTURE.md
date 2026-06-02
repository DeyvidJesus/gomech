# GoMech V2 - Backend Architecture

Este documento define os padrões arquiteturais, a estrutura do projeto e as convenções técnicas da API Backend da GoMech V2, com base na stack **Java, Spring Boot 3.x, PostgreSQL e Docker**. O sistema adotará a arquitetura de **Monolito Modular**, visando alto isolamento interno de regras de negócio, mas facilidade operacional de deploy.

---

## 1. Estrutura de Módulos e Pacotes (Package Structure)

A estrutura de diretórios adotará o padrão *Package-by-Feature/Domain* em vez de *Package-by-Layer* no nível superior, garantindo que o Monolito Modular mantenha as barreiras bem definidas.

**Pacote Raiz:** `com.gomech.api`

```text
com.gomech.api
├── core/                        # Infraestrutura Global compartilhada (Cross-Cutting Concerns)
│   ├── config/                  # Configurações globais (CORS, Jackson, Async)
│   ├── security/                # Autenticação (JWT), Autorização, Configs do Spring Security
│   ├── tenancy/                 # Filtros e Context Holder do Tenant (ThreadLocal)
│   ├── exceptions/              # RestControllerAdvice e Exceptions de Sistema Customizadas
│   └── logging/                 # Filtros de MDC, rastreamento de requisições e Auditoria
│
├── modules/                     # Módulos Funcionais (Isolados)
│   ├── iam/                     # Identity & Access Management (Users, Roles, Auth)
│   ├── crm/                     # Customer Relationship Management (Customers, Vehicles)
│   ├── operations/              # Ordens de Serviço (Work Orders), Orçamentos (Quotes)
│   ├── inventory/               # Estoque, Produtos, Movimentações, Fornecedores
│   ├── finance/                 # Fluxo de Caixa, Contas a Pagar/Receber
│   └── billing/                 # Pagamentos de Assinaturas (SaaS), Planos
```

### 1.1 Camadas Internas de um Módulo
Dentro de cada módulo (ex: `com.gomech.api.modules.crm`), a divisão respeitará uma arquitetura em camadas focada no domínio:
- `.controllers` (Endpoints REST)
- `.dto` (Data Transfer Objects: Requests e Responses)
- `.services` (Regras de negócio da aplicação)
- `.repositories` (Interfaces do Spring Data JPA)
- `.models` (Entidades mapeadas do Hibernate/JPA)
- `.events` (Spring Application Events - Integração com outros módulos via Pub/Sub)

---

## 2. Controllers e DTOs

### Controllers
- **Responsabilidade**: Expor Endpoints RESTful, gerenciar rotas, ler o JSON HTTP e retornar os códigos de status adequados (`200 OK`, `201 Created`, `204 No Content`).
- Não devem possuir regras de negócio; delegam estritamente para a camada de `Services`.
- Utilização agressiva da anotação `@PreAuthorize` do Spring Security para travar a rota pelas permissões do PBAC (Permission-Based Access Control).

### DTOs (Data Transfer Objects)
- Usados para desacoplar a representação de banco de dados (`Entity`) da resposta da API.
- Recomenda-se o uso de **Java Records** nativos (a partir do Java 14+) pela sua imutabilidade nativa e código limpo.
- Exemplo de nomenclatura: `CreateCustomerRequest`, `UpdateCustomerRequest`, `CustomerResponse`.
- Mapeamento (Entity <-> DTO): Pode ser manual (recomendado em Record) ou utilizando bibliotecas como `MapStruct`.

---

## 3. Validation

- O tratamento de inconsistências de entrada usará o ecossistema padrão **Jakarta Bean Validation**.
- **Annotations (`@Valid`)**: Aplicadas primariamente nas assinaturas dos Controllers nos DTOs de Request.
- Restrições embutidas nos campos: `@NotNull`, `@NotBlank`, `@Size`, `@Email`.
- Validações específicas do domínio brasileiro, como CPF/CNPJ válidos, devem implementar validadores customizados (`@Constraint`).

---

## 4. Services e Repositories

### Services
- Concentram toda a regra de negócios.
- São anotados com `@Service` e gerenciam transações via `@Transactional`.
- Devem injetar os *Repositories* necessários.
- Regra do Monolito Modular: Um serviço de um módulo só pode injetar Serviços Públicos ou publicar eventos se quiser se comunicar com outro módulo; nunca deve injetar o repositório diretamente do outro. (Ex: `WorkOrderService` não pode usar `InventoryRepository`, deve usar `InventoryMovementService` ou gerar um `WorkOrderCompletedEvent`).

### Repositories
- Estender `JpaRepository` (Spring Data JPA).
- Todo Repository que acesse entidades do Tenant injeta automaticamente o identificador de empresa através dos mecanismos do Hibernate.

---

## 5. Multi-Tenancy Strategy (Implementação Backend)

A lógica central de segregação de dados que suporta arquitetura.

1. **Contexto de Request (`TenantContext`)**: Um `Filter` intercepta cada chamada HTTP, extrai o *tenant_id* embutido no Token JWT, e o salva de forma segura na Thread atual via `ThreadLocal`.
2. **Integração Hibernate 6 (`@TenantId`)**: O Hibernate mais recente suporta *Shared Schema* de forma nativa. Ao anotar a entidade com `@TenantId private UUID tenantId;`, o Hibernate automaticamente restringe a geração do comando SQL e preenche o *insert* e *select* injetando o Tenant do contexto, mitigando falhas do programador ao omitir `WHERE tenant_id = ?`.
3. **Integração PostgreSQL (Row Level Security)**: Durante a inicialização da transação ou no pool de conexões (ex: HikariCP + *ConnectionInterceptor*), um comando `SET LOCAL app.current_tenant = 'tenant_uuid'` é chamado, ativando as `Policies` do PostgreSQL.

---

## 6. Security (Autenticação e Autorização)

- **Configuração**: Spring Security com arquitetura Stateless.
- **Filtro Customizado (`JwtAuthenticationFilter`)**: Valida o header `Authorization: Bearer <token>`, decodifica, confere a assinatura, extrai o *User ID*, *Tenant ID* e as *Authorities* (Permissões). Instancia um objeto `UsernamePasswordAuthenticationToken` no `SecurityContext`.
- **Criptografia**: `PasswordEncoder` utilizando Argon2 ou BCrypt para salvar senhas e tokens de forma irreversível.
- **Autorização (RBAC/PBAC)**: Avaliada por endpoint ou escopo de Unidade na camada *Service* caso a permissão varie de filial para filial.

---

## 7. Exception Handling

Centralizado para garantir que *StackTraces* não vazem para clientes e a API mantenha contratos consistentes.

- **Classe `@RestControllerAdvice`**: Intercepta exceções não tratadas da aplicação (no pacote `core/exceptions`).
- **Standard**: Utiliza a padronização *RFC 7807 (Problem Details for HTTP APIs)* do Spring Boot 3 (`ProblemDetail.forStatusAndDetail(...)`).
- **Hierarquia Customizada**:
  - `ResourceNotFoundException` -> Retorna `404 Not Found`.
  - `BusinessValidationException` -> Retorna `422 Unprocessable Entity` com arrays detalhados contendo qual campo exato falhou (mapeado de erros de banco ou Bean Validation).
  - `AccessDeniedException` -> Retorna `403 Forbidden`.

---

## 8. Logging & Auditoria

### Application Logging (Slf4j + Logback)
- **MDC (Mapped Diagnostic Context)**: O sistema injetará automaticamente um `correlation_id` e o `tenant_id` atual no log. Isso garante que a jornada da requisição possa ser filtrada facilmente em ferramentas como ELK Stack, Datadog ou AWS CloudWatch, separando logs por cliente com facilidade.
- A saída dos logs no ambiente Docker deve ser formatada estruturada (`JSON`), substituindo logs de string plana.

### Auditoria de Domínio Assíncrona
- Para as regras de gravação na tabela `audit_logs` descrita no Design do Banco:
  - O uso de interceptadores nativos do Hibernate (`EmptyInterceptor` ou Envers não servem por requerer JSON flexível).
  - Em vez disso, os Serviços (Services) responsáveis publicam Eventos Spring de Domínio (Ex: `ApplicationEventPublisher.publish(new AuditEvent(...))`).
  - Um `@Async @EventListener` escuta as mudanças em background, desserializa em JSONB e persiste em base na tabela isolada, garantindo *Zero-Impact Performance* para a requisição original.
