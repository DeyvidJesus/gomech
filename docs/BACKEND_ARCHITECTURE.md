# GoMech V2 - Backend Architecture

Este documento define os padrões arquiteturais, a estrutura do projeto e as convenções técnicas da API Backend da GoMech V2, com base na stack **Java, Spring Boot 3.x, PostgreSQL e Docker**. O sistema adotará a arquitetura de **Monolito Modular**, visando alto isolamento interno de regras de negócio, mas facilidade operacional de deploy.

---

## 1. Estrutura de Módulos e Pacotes (Package Structure)

A estrutura de diretórios adotará o padrão *Package-by-Feature/Domain* em vez de *Package-by-Layer* no nível superior, garantindo que o Monolito Modular mantenha as barreiras bem definidas.

**Pacote Raiz:** `com.gomech.api`

```text
com.gomech.api
├── core/                        # Infraestrutura Global compartilhada (Cross-Cutting Concerns)
│   ├── api/                     # Contratos HTTP compartilhados (ex.: PageResponse)
│   ├── security/                # Autenticação (JWT), filtros e Configs do Spring Security
│   ├── tenancy/                 # Context Holders de Tenant/Unit (ThreadLocal) e seu filtro
│   ├── logging/                 # Correlation ID: filtro de entrada e chave de MDC
│   ├── events/                  # Abstração de evento e barramento in-process (ADR-008)
│   ├── audit/                   # Contrato de auditoria (api/application/domain/infrastructure)
│   ├── authorization/           # ActorContext e contrato de autorização
│   ├── entitlement/             # Contrato de entitlements
│   └── exceptions/              # RestControllerAdvice e Exceptions de Sistema Customizadas
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
Dentro de cada módulo (ex: `com.gomech.api.modules.crm`), a divisão segue as quatro camadas
definidas pela [ADR-002](adr/ADR-002-module-layering-and-dependency-rules.md):

- `.api` (Endpoints REST, DTOs de Request/Response e contratos públicos do módulo)
- `.application` (Casos de uso, orquestração e transações)
- `.domain` (Conceitos e regras de negócio, sem dependência de framework)
- `.infrastructure` (Entidades JPA, repositórios Spring Data, adaptadores e configuração)
- `.events` (Eventos publicados para outros módulos — ver [ADR-003](adr/ADR-003-domain-events.md))

Exemplo, já aplicado ao módulo IAM:

```text
com.gomech.api.modules.iam
├── api/                  # AuthController, UserController, OnboardingController
│   └── dto/              # LoginRequest, AuthResponse, CreateUserRequest, UserResponse, ...
├── application/          # AuthService, UserService, OnboardingService
├── domain/               # UserStatus
└── infrastructure/
    ├── config/           # DataLoader
    └── persistence/
        ├── model/        # User, Role, Permission, Tenant, Unit, UserRole, UserSession
        └── repository/   # UserRepository, RoleRepository, ...
```

Essa estrutura é verificada mecanicamente por testes ArchUnit: o layout e as direções de
dependência entre camadas falham o build quando violados.

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

### 5.1 Modelo de confiança do tenant (Tenant trust model)

A identidade de tenant é **autoritativa apenas quando vem de estado autenticado**. `TenantSource`
registra a origem do tenant em escopo e define o que pode ser confiado:

| Origem | Estabelecida por | Confiável | Chega ao `ActorContext` |
|---|---|---|---|
| `AUTHENTICATED` | `JwtAuthenticationFilter`, a partir da claim `tenantId` de um token verificado | Sim | Sim |
| `SYSTEM` | Servidor, ex.: o onboarding que acabou de criar o tenant | Sim | Sim |
| `REQUESTED` | Header `X-Tenant-ID` enviado pelo chamador | **Não** | **Não** |

Regras aplicadas:

1. **Um tenant escolhido pelo chamador nunca substitui um tenant provado.**
   `TenantContextHolder.setRequestedTenant(...)` é ignorado quando já existe um tenant confiável. A
   garantia está no holder, não na ordem dos filtros, então vale independentemente de como a cadeia
   for reordenada.
2. **O header `X-Tenant-ID` é um recurso de desenvolvimento, não do fluxo de autenticação.** Nenhum
   cliente o envia: o login resolve o tenant a partir das credenciais. Ele existe para exercitar
   endpoints por tenant manualmente enquanto o login *tenant-aware* não está concluído.
3. **Desligado por padrão.** Só é aceito quando `gomech.tenancy.trust-request-header: true`, o que
   apenas o profile `local` faz. `dev`, `staging` e `prod` herdam `false` de `application.yml`.
4. **Escopo mínimo.** Mesmo habilitado, só é lido em `/api/v1/auth/login`, o único endpoint público
   que precisa de um tenant antes de haver autenticação. O registro cria o próprio tenant e não
   depende dele.
5. **Limpeza garantida.** `TenantFilter` é o filtro mais externo e limpa tenant e unit em `finally`,
   inclusive quando o header está desabilitado ou o handler lança exceção.

Consequência: um tenant fornecido pelo chamador pode, no máximo, escolher contra qual tenant uma
tentativa de login é avaliada — e essa tentativa ainda exige credenciais válidas daquele tenant.
Ele nunca atua como identidade nem desloca uma identidade autenticada.

> **Pendência conhecida:** o login *tenant-aware* em si continua em aberto. Sem o header, e sem um
> tenant no contexto, `HibernateTenantIdentifierResolver` cai no Tenant Zero, então o login só
> encontra usuários daquele tenant. Resolver isso é uma mudança no IAM (resolver o tenant a partir
> das credenciais) e não faz parte do modelo de confiança descrito aqui.

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
- **MDC (Mapped Diagnostic Context)**: O sistema injeta automaticamente um `correlation_id` no log. Isso garante que a jornada da requisição possa ser filtrada facilmente em ferramentas como ELK Stack, Datadog ou AWS CloudWatch.
- A saída dos logs no ambiente Docker deve ser formatada estruturada (`JSON`), substituindo logs de string plana.

#### Correlation ID (implementado)

`CorrelationIdFilter` (`core.logging`) é o filtro mais externo da cadeia, antes de `TenantFilter`:

1. **Entrada**: aceita `X-Correlation-ID` quando o valor é seguro e limitado (`[A-Za-z0-9_-]{1,64}`),
   permitindo que um serviço a montante correlacione seus logs com os nossos. Qualquer outro valor —
   vazio, com quebra de linha, longo demais — é substituído por um id gerado. A requisição nunca é
   rejeitada por causa desse header.
2. **Escopo**: o id vai para o MDC sob a chave `correlation_id` e é devolvido no header da resposta.
   O padrão de log em `application.yml` (`logging.pattern.level`) o inclui em toda linha.
3. **Eventos**: `EventMetadataFactory` lê essa mesma chave, então todo `EventEnvelope` publicado
   durante a requisição carrega o `correlationId`. `SpringDomainEventDispatcher` executa os handlers
   dentro do id do envelope e restaura o anterior ao final.
4. **Limpeza**: o MDC é limpo no `finally` do filtro mais externo, inclusive quando o handler lança
   exceção, de modo que nenhum id sobrevive na thread do container.

Não há dependência de tracing externo: `CorrelationId` (`core.logging`) é a única fonte da chave de
MDC, compartilhada entre filtro, padrão de log e metadados de evento.

### Auditoria de Domínio Assíncrona (destino final)
- Para as regras de gravação na tabela `audit_logs` descrita no Design do Banco:
  - O uso de interceptadores nativos do Hibernate (`EmptyInterceptor` ou Envers não servem por requerer JSON flexível).
  - Em vez disso, os Serviços (Services) responsáveis publicam Eventos Spring de Domínio (Ex: `ApplicationEventPublisher.publish(new AuditEvent(...))`).
  - Um `@Async @EventListener` escuta as mudanças em background, desserializa em JSONB e persiste em base na tabela isolada, garantindo *Zero-Impact Performance* para a requisição original.

### Fundação de auditoria (estado atual)

O core expõe o contrato `AuditRecorder` (`core.audit.application`), que recebe um `ActorContext` e um
`AuditRecordRequest` e devolve um `AuditEntry` contendo apenas metadados que o core consegue
estabelecer sozinho: **ator, tenant, unit, correlation id**, ação, recurso e instante.

A implementação atual, `LoggingAuditRecorder`, é um **sink real**: cada entrada é emitida no logger
dedicado `com.gomech.audit`, que pode ser roteado e filtrado separadamente dos logs de aplicação.
Combinada com o correlation id, cada entrada é rastreável até a requisição que a originou.

**Por que ainda não grava em `audit_logs`:** a tabela é chaveada por transição de estado de entidade
(`old_state_json` / `new_state_json`), o que exige uma *política de auditoria de domínio* — decidir
quais entidades são auditadas e como capturar o antes/depois. `AuditRecordRequest` não carrega esse
estado, e essa política não faz parte da fundação. O writer persistente descrito acima substitui o
bean atual sem alterar nenhum chamador, porque os módulos dependem de `AuditRecorder`, nunca da
implementação — regra verificada por `modules_must_not_depend_on_core_infrastructure`.

Restrições verificadas mecanicamente:

- auditoria não depende de repositórios de negócio (`core_must_not_depend_on_business_modules`);
- módulos consomem o contrato, não a implementação (`modules_must_not_depend_on_core_infrastructure`).
