# ADR-004: Convenções de API REST

- **Status:** Aceita
- **Data:** 2026-08-18
- **Relacionadas:** [ADR-001 — Monolito modular](ADR-001-monolito-modular.md), [ADR-002 — Camadas e regras de dependência](ADR-002-camadas-e-regras-de-dependencia.md), [ADR-003 — Eventos de domínio](ADR-003-eventos-de-dominio.md)

## Contexto

O GoMech V2 expõe as capacidades do backend como uma API REST/JSON sob `/api/v1`, consumida pelo frontend web, por futuros clientes mobile e pelo serviço de IA independente.

A [ADR-001](ADR-001-monolito-modular.md) estabeleceu o monolito modular. A [ADR-002](ADR-002-camadas-e-regras-de-dependencia.md) estabeleceu as camadas dos módulos e colocou os controllers HTTP e os DTOs de request/response no pacote `api` de cada módulo. A [ADR-003](ADR-003-eventos-de-dominio.md) estabeleceu eventos in-process para consequências entre módulos.

Ainda falta uma decisão única e compartilhada sobre como a própria superfície HTTP se comporta. Hoje:

- `/api/v1/users` e `/api/v1/auth/login` já existem, mas as convenções só existem na cabeça de quem revisa o código.
- O `GlobalExceptionHandler` já retorna `ProblemDetail` (RFC 7807), mas apenas para dois tipos de exceção e com um formato de `invalidParams` que não corresponde à especificação da API (`docs/API_SPECIFICATION.md`).
- Paginação, filtros e ordenação são descritos endpoint a endpoint na especificação da API, mas não têm um contrato compartilhado.
- Vários endpoints planejados têm efeitos colaterais reais sobre dinheiro ou estoque (`/quotes/{id}/approve`, `/work-orders/{id}/status`, `/inventory/movements`, `/financial-transactions/{id}/pay`), e uma requisição repetida em um retry não pode cobrar em dobro nem baixar o estoque duas vezes.
- Ainda não há geração de OpenAPI configurada no backend.

Sem uma decisão única, cada novo módulo de negócio vai inventar o próprio envelope, o próprio formato de erro e os próprios parâmetros de consulta, e o frontend vai absorver essa inconsistência.

Esta ADR se aplica ao backend Spring Boot em `gomech/backend`.

## Decisão

O GoMech V2 expõe uma **API REST orientada a recursos, sobre JSON**, versionada no path da URI sob `/api/v1`, com comportamento padronizado para erros, paginação, filtros, ordenação e idempotência, e documentada por uma especificação OpenAPI gerada a partir do código.

Essas convenções são obrigatórias para todos os módulos de negócio. Nenhum módulo pode definir o próprio envelope, o próprio corpo de erro ou os próprios parâmetros de paginação.

## Transporte e representação

- Os corpos de request e de response são JSON, em UTF-8.
- Respostas de sucesso usam `application/json`.
- Respostas de erro usam `application/problem+json` (RFC 7807).
- Timestamps seguem ISO-8601 em UTC (`Instant`), por exemplo `2026-06-01T14:00:00Z`. Datas locais usam `yyyy-MM-dd`.
- Valores monetários são serializados como números JSON baseados em `BigDecimal`, nunca como ponto flutuante no código da aplicação.
- Os identificadores expostos aos clientes são UUIDs. Valores de sequence do banco de dados nunca são expostos como identificadores públicos.
- Os nomes de propriedades JSON usam `camelCase`.
- Propriedades desconhecidas no corpo da requisição são rejeitadas, e não ignoradas, para que erros de digitação do cliente apareçam como falhas de validação em vez de campos descartados silenciosamente.
- Os clientes devem tolerar propriedades desconhecidas no corpo da resposta. Adicionar um campo à resposta não é uma breaking change.

## Convenções de recursos e URLs

- Coleções de recursos ficam no plural, em `kebab-case`: `/api/v1/work-orders`, `/api/v1/financial-transactions`.
- Instâncias de recurso são endereçadas pelo identificador: `/api/v1/work-orders/{id}`.
- Sub-recursos são aninhados em no máximo um nível: `/api/v1/inventory/movements`.
- Parâmetros de query usam `camelCase`.
- Verbos não aparecem nos paths de recurso. Transições de negócio que não são simples atualizações são modeladas como uma ação explícita em um sub-recurso, usando `POST` ou `PUT`:
  - `POST /api/v1/quotes/{id}/approve`
  - `PUT /api/v1/work-orders/{id}/status`
  - `PUT /api/v1/financial-transactions/{id}/pay`
- O escopo de tenant nunca é um parâmetro de path ou de query. Ele é derivado do principal autenticado e do contexto de tenant, tratados por `TenantFilter` e `TenantContextHolder`.

### Métodos HTTP

| Método | Significado | Idempotente |
|---|---|---|
| `GET` | Lê um recurso ou uma coleção. Sem efeitos colaterais. | Sim |
| `POST` | Cria um recurso ou executa uma ação de negócio em um path de sub-recurso. | Não, a menos que uma chave de idempotência seja enviada |
| `PUT` | Substitui um recurso ou aplica uma transição de estado declarada. | Sim |
| `PATCH` | Atualiza parcialmente um recurso. Usado com moderação. | Não |
| `DELETE` | Remove ou desativa um recurso. | Sim |

### Uso dos status HTTP

| Status | Quando |
|---|---|
| `200 OK` | Leitura, atualização ou ação bem-sucedida que retorna corpo |
| `201 Created` | Recurso criado. Deve incluir um header `Location` apontando para o novo recurso |
| `204 No Content` | Operação bem-sucedida sem corpo, tipicamente `DELETE` |
| `400 Bad Request` | JSON malformado, parâmetro impossível de interpretar, campo de filtro ou de ordenação não suportado |
| `401 Unauthorized` | Credenciais ausentes, expiradas ou inválidas |
| `403 Forbidden` | Autenticado, mas sem a permissão necessária |
| `404 Not Found` | O recurso não existe ou não é visível para o tenant de quem chama |
| `409 Conflict` | Violação de unicidade, transição de estado inválida ou reuso de chave de idempotência com payload diferente |
| `422 Unprocessable Entity` | Requisição sintaticamente válida que falha na validação ou em uma invariante de negócio |
| `429 Too Many Requests` | Requisição limitada (throttling), por exemplo após repetidas falhas de login |
| `500 Internal Server Error` | Falha não tratada. Nunca expõe stack traces |

Um recurso que pertence a outro tenant é reportado como `404`, e não `403`, para que a API não confirme a existência de dados de outros tenants.

## DTOs

Os DTOs são o contrato da API. Eles não são uma visão serializada do modelo de persistência.

Regras:

- DTOs de request e de response são `record`s Java e ficam no pacote `api` do módulo dono, conforme a ADR-002.
- Controllers nunca recebem nem retornam entidades JPA, e nunca retornam `Optional`, `Map<String, Object>` ou coleções cruas como corpo de nível superior.
- Todo DTO é direcional. `CreateUserRequest` e `UserResponse` são tipos separados, mesmo quando seus campos hoje coincidem.
- Nomenclatura: `<UseCase>Request`, `<Resource>Response` e `<Resource>SummaryResponse` para projeções de listagem.
- Segredos nunca aparecem em respostas: senhas, hashes de senha, material de refresh token e chaves internas de tenant ficam de fora por omissão no DTO, e não por anotação na entidade.
- Um DTO de resposta expõe apenas os campos de que o cliente precisa. Ampliar uma resposta depois é barato; reduzi-la é uma breaking change.
- Endpoints de listagem podem retornar um `SummaryResponse` mais leve do que o endpoint de recurso único. Essa diferença deve estar documentada no OpenAPI.

## Validação

A validação acontece em dois lugares distintos, e essa divisão é deliberada:

1. **Validação de formato** na fronteira `api`, usando anotações do Jakarta Bean Validation no DTO de request, mais `@Valid` no parâmetro do controller. Isso cobre campos obrigatórios, formatos, tamanhos e intervalos.
2. **Invariantes de negócio** em `domain` ou `application`, conforme a ADR-002. Unicidade dentro de um tenant, transições de estado válidas, disponibilidade de estoque e verificações de escopo de acesso não são anotações em um DTO.

As duas chegam ao cliente pelo mesmo contrato de problem detail:

- Uma falha de validação de formato produz `422` com `invalidParams`.
- Uma invariante de negócio violada produz `422` quando a requisição está bem formada mas não é aceitável, ou `409` quando conflita com o estado atual de um recurso.
- JSON malformado ou um parâmetro de query impossível de interpretar produz `400`.

As mensagens de validação são estáveis e voltadas ao cliente. Elas não devem incluir SQL, nomes de classe nem stack traces.

## Modelo de erros

Todos os erros seguem a RFC 7807 e são produzidos de forma centralizada pelo `GlobalExceptionHandler`. Controllers não montam corpos de erro.

```json
{
  "type": "https://gomech.com/docs/errors/validation-failed",
  "title": "Validation Failed",
  "status": 422,
  "detail": "Input validation failed for some parameters.",
  "instance": "/api/v1/customers",
  "invalidParams": [
    { "name": "document", "reason": "must be a valid CPF or CNPJ format" }
  ]
}
```

Regras:

- `type` é uma URI estável e documentada sob `https://gomech.com/docs/errors/<slug>`. Ela faz parte do contrato: os clientes podem tomar decisões com base nela, então seu significado não pode mudar dentro de uma versão major.
- `title` é um resumo curto, estável e legível, vinculado ao `type`.
- `detail` explica esta ocorrência específica e pode variar.
- `instance` é o path da requisição.
- `invalidParams` é um **array de objetos** com `name` e `reason`, para que vários problemas no mesmo campo possam ser representados e a ordem seja estável.
- Membros de extensão além de `invalidParams` são permitidos, mas devem ser documentados no OpenAPI.

## Paginação

Todo endpoint de coleção é paginado. Um array JSON puro nunca é retornado como corpo de nível superior, porque não carrega metadados e não pode ser estendido sem quebrar os clientes.

Parâmetros de request:

| Parâmetro | Padrão | Restrição |
|---|---|---|
| `page` | `0` | Base zero, `>= 0` |
| `size` | `20` | `1..100`. Um valor maior é rejeitado com `400`, em vez de ser limitado silenciosamente |

Envelope de resposta, fornecido pelo `com.gomech.api.core.api.PageResponse<T>` compartilhado:

```json
{
  "content": [],
  "page": 0,
  "size": 20,
  "totalElements": 0,
  "totalPages": 0,
  "sort": "createdAt,desc"
}
```

O `Page`/`PageImpl` do Spring Data não é serializado diretamente. Os controllers o convertem em `PageResponse<T>`, de modo que o formato trafegado (wire format) pertence ao projeto e não muda com um upgrade de framework.

Endpoints que também precisam de valores agregados, como a listagem de fluxo de caixa do financeiro, os expõem como uma propriedade de extensão documentada no envelope, e não como headers ad hoc.

## Filtros

- Filtros são parâmetros de query explícitos e tipados, com o nome do campo de resposta que filtram: `?status=PENDING`, `?customerId=<uuid>`, `?licensePlate=ABC1234`.
- Filtros de intervalo usam os sufixos `<field>From` e `<field>To`: `?dueDateFrom=2026-06-01&dueDateTo=2026-06-30`. Os dois limites são inclusivos e opcionais de forma independente.
- Filtros com múltiplos valores repetem o parâmetro: `?status=PENDING&status=OVERDUE`. Valores separados por vírgula não são usados, porque colidem com conteúdo de texto livre.
- A busca em texto livre usa um único parâmetro `q`, e cada endpoint documenta em quais campos o `q` busca.
- Um parâmetro de filtro não suportado ou com erro de digitação é rejeitado com `400`. Ele nunca é ignorado: descartar um filtro silenciosamente retorna um conjunto de resultados mais amplo do que o solicitado, e essa é a falha mais perigosa.
- Os filtros são sempre aplicados dentro do escopo de tenant de quem chama. Um filtro pode restringir a visibilidade, nunca ampliá-la.
- Nenhuma linguagem de consulta genérica é aceita dos clientes. O conjunto de campos filtráveis de cada endpoint é fixo e documentado.

## Ordenação

- A ordenação usa o parâmetro repetível `sort`, no formato já conhecido do Spring: `?sort=createdAt,desc&sort=name,asc`.
- A direção é opcional e o padrão é `asc`.
- Cada endpoint aceita apenas uma whitelist explícita de campos ordenáveis. Qualquer outro campo é rejeitado com `400`, o que também impede que a ordenação seja usada para sondar colunas que não fazem parte do contrato.
- Todo endpoint declara uma ordenação padrão determinística, e toda ordenação desempata por `id`, para que a paginação não repita nem pule linhas entre páginas.
- Alterar a ordenação padrão de um endpoint é uma breaking change.

## Idempotência

`GET`, `PUT` e `DELETE` são idempotentes por construção, e as implementações devem mantê-los assim: repetir uma transição de estado via `PUT` que já foi aplicada retorna a representação atual, em vez de falhar.

Endpoints `POST` com efeitos colaterais relevantes devem, além disso, suportar o header de request `Idempotency-Key`. Isso vale, no mínimo, para:

- criação de recursos com consequências de negócio (`POST /api/v1/quotes`, `POST /api/v1/customers`)
- transições de estado que movimentam dinheiro ou estoque (`POST /api/v1/quotes/{id}/approve`, `PUT /api/v1/work-orders/{id}/status`, `POST /api/v1/inventory/movements`, `PUT /api/v1/financial-transactions/{id}/pay`)

Semântica:

- O cliente gera um UUID por operação lógica e o reutiliza em todos os retries dessa mesma operação.
- O servidor registra a chave com escopo por tenant e endpoint, junto com um fingerprint do payload da requisição e com o status e o corpo da resposta original.
- Um replay com a mesma chave e o mesmo payload retorna a **resposta original registrada** e não executa nenhum efeito colateral adicional.
- Um replay com a mesma chave e um payload **diferente** é rejeitado com `409`, porque a chave deixou de identificar uma única operação lógica.
- Os registros são mantidos por 24 horas. Depois disso, a chave é tratada como nova.
- Uma requisição sem o header em um endpoint que o suporta é processada normalmente. O header é um mecanismo de segurança do cliente, e não uma etapa de autenticação.

O armazenamento de idempotência é transversal e pertence ao `core`, sem duplicação por módulo.

Concorrência em atualizações é uma questão separada: endpoints de transição de estado validam o estado atual como parte da transição e podem adotar optimistic locking com `If-Match`/ETag quando surgir um problema real de atualização perdida (lost update).

## Versionamento e compatibilidade de contrato

A versão da API fica no path da URI: `/api/v1`. Todos os recursos compartilham uma única versão.

**Compatível com versões anteriores, permitido dentro de `/api/v1`:**

- adicionar um novo endpoint
- adicionar um novo campo de request **opcional**
- adicionar um novo campo de resposta
- adicionar um novo filtro, campo de ordenação ou parâmetro de query opcional
- relaxar uma restrição de validação
- adicionar um novo `type` de erro documentado para um caso que antes retornava um erro genérico com o mesmo status

**Breaking change, exige `/api/v2`:**

- remover ou renomear um campo, endpoint ou parâmetro
- tornar obrigatório um campo de request opcional
- alterar o tipo de um campo, ou tornar anulável um campo de resposta que antes nunca era nulo
- endurecer uma restrição de validação
- alterar o status HTTP ou o `type` de erro retornado para um caso existente
- alterar a ordenação padrão, o tamanho de página padrão ou a semântica de paginação de um endpoint
- adicionar um valor a um enum de resposta, a menos que o campo esteja documentado como extensível e os clientes tenham sido orientados a tolerar valores desconhecidos

Quando `/api/v2` for introduzida, `/api/v1` continuará suportada durante uma janela de depreciação acordada com o frontend, e as operações depreciadas serão marcadas como `deprecated` no OpenAPI antes da remoção.

## Expectativas para a documentação OpenAPI

- A especificação OpenAPI 3 é **gerada a partir do código** via springdoc-openapi. Os controllers e DTOs anotados são a única fonte da verdade; a especificação nunca é editada à mão.
- A especificação gerada é servida em `/v3/api-docs`, com a UI interativa em `/swagger-ui`. As duas ficam abertas em `local` e `dev`, e com acesso restrito em `staging` e `prod`.
- Toda operação documenta: `operationId`, resumo, a permissão exigida, o schema de request, o schema da resposta de sucesso e todos os status de erro que pode retornar.
- Todo campo de DTO que não seja autoexplicativo tem uma descrição e, quando útil, um exemplo.
- O CI exporta a especificação gerada como artefato de build, para que as diferenças de contrato entre commits possam ser revisadas. Um diff que se enquadre na lista de breaking changes acima deve ser justificado no review ou movido para uma nova versão.
- O `docs/API_SPECIFICATION.md` continua sendo a descrição narrativa da intenção de cada módulo. Quando os dois divergirem sobre o formato de um payload, vale a especificação gerada, e o documento narrativo é corrigido.

## Alternativas consideradas

### Versionamento por header ou media type em vez de versionamento na URI

Rejeitada. A versão no path é trivialmente visível em logs, navegadores, cURL e snapshots de contrato no CI, e não custa nada para rotear. A negociação por header é mais elegante, mas bem mais difícil de depurar para um time pequeno.

### Nenhum versionamento, evoluindo `/api` no lugar

Rejeitada. O frontend e o serviço de IA fazem deploy de forma independente do backend, então pelo menos um consumidor sempre estará rodando contra um contrato mais antigo.

### Um envelope de erro customizado em vez da RFC 7807

Rejeitada. `ProblemDetail` já está em uso e é nativo do Spring Boot 3, então adotar o padrão não custa nada e dá aos clientes um formato documentado que eles talvez já conheçam.

### Envolver toda resposta de sucesso em `{ "data": ..., "meta": ... }`

Rejeitada. Isso adiciona um nível de aninhamento a toda leitura de recurso único para resolver um problema que só as coleções têm, e as coleções já estão resolvidas pelo `PageResponse`.

### Paginação baseada em cursor

Rejeitada para a V2. A paginação por página combina com a UI, que precisa de números de página e de contagens totais, e se encaixa diretamente no Spring Data. Ela será revisitada se uma listagem append-only de alto volume, como movimentações de estoque ou histórico de auditoria, ultrapassar o que a paginação por offset suporta; isso seria uma nova ADR.

### Uma linguagem de consulta genérica, como RSQL ou OData

Rejeitada. Ela expõe o modelo de persistência aos clientes, torna a superfície de consulta ilimitada e difícil de indexar, e transforma a aplicação do escopo de tenant em um problema de parsing. Filtros explícitos e tipados mantêm revisáveis tanto o contrato quanto o plano de execução das consultas.

### Identificadores de recurso gerados pelo cliente em vez de `Idempotency-Key`

Rejeitada como mecanismo geral. Isso resolve apenas a criação duplicada, e não transições de estado duplicadas, como pagar uma transação duas vezes, que é onde está o risco financeiro real.

### OpenAPI design-first, com a especificação escrita à mão

Rejeitada por enquanto. Com um time pequeno e ainda sem consumidores externos da API, uma especificação escrita à mão se distancia da implementação, e documentação desatualizada é pior do que nenhuma. Revisitar se surgir uma API pública ou para parceiros.

## Trade-offs

### Benefícios

- Um único formato de contrato em todos os módulos: o frontend escreve sua camada HTTP uma única vez.
- O tratamento de erros é centralizado e legível por máquina, e stack traces não têm como vazar.
- Paginação, filtros e ordenação são previsíveis o bastante para serem implementados por helpers compartilhados, e não endpoint a endpoint.
- A idempotência torna os retries seguros exatamente nos endpoints em que uma duplicação sai cara.
- O OpenAPI gerado torna o desvio de contrato visível no code review, e não em produção.

### Custos

- Rejeitar campos de request desconhecidos e parâmetros de filtro não suportados é mais rígido do que os padrões do framework, então um erro de digitação do cliente vira uma falha visível em vez de um no-op silencioso. Essa é a intenção, mas exige configuração explícita e mensagens de erro claras.
- Paginar sempre significa que até listas pequenas e claramente limitadas carregam o overhead do envelope.
- A idempotência exige armazenamento compartilhado, uma política de retenção e disciplina em cada endpoint.
- A abordagem de whitelist para campos de filtro e de ordenação faz com que adicionar um filtro seja uma mudança deliberada, e não um parâmetro de query livre.
- O versionamento na URI duplica uma superfície de controllers no dia em que `/api/v2` chegar.

## Consequências

- Novos endpoints são revisados com base nesta ADR, e não no que o controller existente mais próximo por acaso faz.
- `PageResponse<T>` passa a ser o formato de retorno obrigatório para endpoints de coleção, e o `Page` do Spring Data nunca atravessa a fronteira HTTP.
- O `GlobalExceptionHandler` passa a cobrir casos de autenticação, autorização, recurso não encontrado, conflito e fallback, com URIs de `type` estáveis, em vez dos dois handlers atuais.
- O mapa `invalidParams` existente é substituído pelo formato de array documentado aqui, alinhando a implementação à especificação da API.
- O springdoc-openapi precisa ser adicionado ao build do backend; até lá, as expectativas de OpenAPI desta ADR não estão atendidas e ficam registradas como trabalho futuro.
- O suporte a idempotência exige um store pertencente ao `core` antes que o primeiro endpoint que movimenta dinheiro ou estoque entre em produção.
- Os filtros de intervalo padronizam `<field>From`/`<field>To`, então os parâmetros `startDate`/`endDate` esboçados para a listagem financeira serão renomeados antes de esse endpoint ser entregue.
- Se um consumidor futuro precisar de um modelo de consulta ou de entrega substancialmente diferente, isso será uma nova ADR, e não uma exceção aberta em `/api/v1`.

## Regras de uso e aplicação

| Regra | Expectativa |
|---|---|
| Controllers ficam no pacote `api` do módulo | Camadas da ADR-002, verificadas por `ModuleArchitectureRulesTest` |
| Nenhuma entidade JPA na assinatura de um controller | Code review, podendo virar uma regra ArchUnit |
| Endpoints de coleção retornam `PageResponse<T>` | Code review e testes de contrato |
| Erros são produzidos apenas pelo `GlobalExceptionHandler` | Nenhum corpo de erro montado com `ResponseEntity` nos controllers |
| Todo endpoint é anotado para o OpenAPI | Especificação gerada revisada no CI |
| Breaking changes incrementam a versão no path | Revisão do diff de contrato com base nas regras de compatibilidade acima |

## Testes

Os testes de referência do contrato da API ficam em:

- [backend/src/test/java/com/gomech/api/api/RestApiContractTest.java](https://github.com/DeyvidJesus/gomech-backend-v2/blob/master/src/test/java/com/gomech/api/api/RestApiContractTest.java)

Esse teste de referência fixa as convenções básicas definidas por esta ADR: o base path `/api/v1`, `201 Created` com header `Location`, o formato de problem detail da RFC 7807 incluindo o array `invalidParams`, o envelope `PageResponse`, a rejeição de um campo de ordenação não suportado e o replay com `Idempotency-Key` retornando a resposta original sem repetir o efeito colateral.

Os endpoints específicos de cada módulo devem ter seus próprios testes de contrato para:

- a permissão exigida por cada operação
- falhas de validação específicas daquele recurso
- comportamento de filtros e de ordenação, incluindo a rejeição de campos não suportados
- limites de paginação, incluindo o máximo de `size`
- replay idempotente em qualquer endpoint com efeitos colaterais financeiros ou de estoque

## Dependências

Esta ADR depende das seguintes decisões e documentos, e os estende:

- [ADR-001 — Monolito modular](ADR-001-monolito-modular.md)
- [ADR-002 — Camadas e regras de dependência](ADR-002-camadas-e-regras-de-dependencia.md)
- [ADR-003 — Eventos de domínio](ADR-003-eventos-de-dominio.md)
- [Arquitetura do backend](https://github.com/DeyvidJesus/gomech-backend-v2/blob/master/docs/arquitetura.md)
- `docs/API_SPECIFICATION.md`: especificação narrativa da API na época desta decisão. O documento foi removido do repositório depois; a especificação OpenAPI gerada (`/v3/api-docs`) é a referência de contrato.

Esta ADR não redefine fronteiras de módulo, camadas nem a semântica dos eventos.

## Fora do escopo

Esta ADR não:

- introduz GraphQL, gRPC nem qualquer transporte que não seja REST
- define o modelo de autenticação ou de permissões em si, que pertence à documentação de IAM e de segurança
- define webhooks de saída nem um programa de API pública ou para parceiros
- define política de rate limiting, além de indicar `429` como o status para requisições limitadas
- define o protocolo interno entre o backend e o serviço de IA independente
- introduz HATEOAS ou relações de links hipermídia
- define headers de cache ou comportamento de CDN
- define os endpoints individuais de cada módulo, que continuam sob responsabilidade da especificação da API e do design de cada módulo

## Critérios de aceite

- [x] ADR revisada e aprovada.
- [x] ADR armazenada junto à documentação de arquitetura.
- [x] REST/JSON e versionamento `/api/v1` decididos explicitamente.
- [x] Alternativas documentadas.
- [x] Trade-offs documentados.
- [x] Consequências documentadas.
- [x] Regras de DTO documentadas.
- [x] Divisão da validação entre transporte e domínio documentada.
- [x] Contrato de erro RFC 7807 documentado.
- [x] Contratos de paginação, filtros e ordenação documentados.
- [x] Expectativas de idempotência documentadas.
- [x] Regras de compatibilidade de contrato explícitas.
- [x] Expectativas de documentação OpenAPI definidas.
- [x] Testes de referência do contrato da API referenciados.

## Documentação relacionada

- Arquitetura central
- [Arquitetura do backend](https://github.com/DeyvidJesus/gomech-backend-v2/blob/master/docs/arquitetura.md)
- Especificação da API
- Especificação OpenAPI gerada em `/v3/api-docs`
