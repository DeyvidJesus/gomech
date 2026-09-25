# ADR-008: Barramento de eventos de domínio in-process

- **Status:** Aceita
- **Data:** 2026-08-18

## Contexto

A [ADR-003](ADR-003-eventos-de-dominio.md) estabeleceu que o GoMech usa eventos in-process para as consequências relevantes entre módulos dentro do monolito modular.

Essa decisão ainda precisa de um mecanismo concreto em runtime para que os módulos possam publicar eventos tipados, preservar metadados de auditoria, registrar handlers de forma explícita e despachar eventos sem acoplamento direto entre publicador e consumidor.

O backend precisa de um event bus V1 que:

- permaneça in-process
- use contratos explícitos
- preserve metadados de auditoria para os listeners
- suporte registro tipado de handlers
- mantenha brokers externos fora do escopo

## Decisão

O GoMech implementa um barramento de eventos de domínio in-process, apoiado no Spring, em `com.gomech.api.core.events`.

O barramento é composto por:

- `DomainEvent`: contrato marcador para payloads de eventos tipados
- `EventMetadata`: metadados orientados à auditoria, capturados no momento da publicação
- `EventEnvelope<T>`: wrapper tipado que carrega o payload e os metadados
- `DomainEventHandler<T>`: contrato explícito de handler
- `DomainEventBus`: contrato de publicação
- `EventHandlerRegistry`: registro e busca de handlers
- `SpringDomainEventBus`: implementação do publicador
- `SpringDomainEventDispatcher`: implementação do dispatcher in-process

## Envelope do evento

Todo evento despachado é encapsulado em um envelope contendo:

- `eventId`
- `eventType`
- `occurredAt`
- `tenantId`
- `userId`
- `correlationId`

O payload continua tipado e implementa `DomainEvent`.

Isso preserva os metadados necessários para auditoria, rastreamento e logging do lado do consumidor, sem obrigar os handlers a recorrer à infraestrutura com escopo de requisição.

## Contrato e registro de handlers

Os handlers implementam:

```java
DomainEventHandler<T extends DomainEvent>
```

Cada handler declara:

- o tipo de evento que suporta
- seu método `handle(EventEnvelope<T>)`

O registro é automático, via descoberta de beans do Spring. O registry agrupa os handlers pelo tipo de evento declarado e despacha apenas para os handlers correspondentes.

## Comportamento do despacho

- os publicadores chamam `DomainEventBus.publish(event)`
- o bus cria um `EventEnvelope`
- os metadados são capturados imediatamente a partir do contexto ativo de tenant, segurança e logging
- o envelope é publicado dentro da mesma aplicação Spring
- o dispatcher roteia o envelope para todos os handlers registrados para aquele tipo de payload

A correspondência é feita pela classe do payload em runtime. Um handler que declara um supertipo não recebe subtipos, o que mantém os contratos entre módulos explícitos e verificados pelo compilador.

### Semântica de falha dos handlers

Os handlers são isolados entre si. Quando um handler lança uma exceção, a falha é registrada em log no nível ERROR, com a causa, o tipo e o id do evento, sob o correlation id da requisição que publicou o evento, e o despacho continua para os demais handlers.

Isso decorre de duas decisões já tomadas, e não de uma decisão nova:

- um envelope vai para *todos* os handlers registrados, então um consumidor com defeito não pode suprimir os consumidores que por acaso estejam registrados depois dele — o que, com a descoberta de beans do Spring, passaria a depender da ordem dos beans;
- a [ADR-003](ADR-003-eventos-de-dominio.md) estabelece que um consumidor reage a um fato de negócio que já aconteceu, não deve provocar rollback no publicador e é responsável pelo tratamento deliberado das próprias falhas.

Portanto, uma falha de handler não é ocultada nem propagada ao publicador. Um consumidor que precise de retries, compensação ou dead-letter implementa isso por conta própria e o testa, como exige a ADR-003.

## Premissas de entrega

O modelo de entrega segue a [ADR-003](ADR-003-eventos-de-dominio.md):

- somente in-process
- somente na mesma JVM
- sem broker
- sem garantia de durabilidade
- sem garantia de replay

Os handlers registrados devem esperar receber o envelope tipado de forma síncrona, pelo mecanismo de eventos in-process do Spring, a menos que uma estratégia específica de listener altere esse comportamento.

## Alternativas consideradas

### Publicar eventos crus do Spring diretamente em todo lugar

Rejeitada porque deixaria implícitos e inconsistentes o formato do contrato, a preservação de metadados e as convenções de registro de handlers.

### Introduzir Kafka ou RabbitMQ agora

Rejeitada porque a V1 exige apenas comunicação modular in-process.

### Usar payloads de evento não tipados, baseados em map

Rejeitada porque os contratos entre módulos devem permanecer explícitos e verificados pelo compilador.

## Trade-offs

### Benefícios

- Contratos tipados para publicadores e consumidores
- Metadados de auditoria compartilhados em todo evento despachado
- Registro automático de handlers
- Separação clara entre o payload de negócio e os metadados de transporte

### Custos

- Mais uma abstração do Core para manter
- O Spring continua fazendo parte do mecanismo de despacho in-process
- As garantias de entrega continuam intencionalmente limitadas

## Consequências

- Os módulos devem publicar payloads `DomainEvent` em vez de objetos de evento do Spring criados ad hoc.
- Os consumidores recebem envelopes em vez de payloads crus, para que os metadados continuem disponíveis.
- As implementações de handlers permanecem explícitas, detectáveis e testáveis.
- Uma futura migração para garantias de entrega mais fortes exigiria uma nova ADR, em vez de alterar este contrato silenciosamente.

## Testes

O comportamento do despacho é coberto por:

- [`src/test/java/com/gomech/api/events/DomainEventBusDispatchTest.java`](https://github.com/DeyvidJesus/gomech-backend-v2/blob/master/src/test/java/com/gomech/api/events/DomainEventBusDispatchTest.java)

Esse teste valida que:

- os handlers registrados recebem os eventos tipados correspondentes
- os metadados são preservados no envelope
- tipos de evento sem handler registrado são ignorados

A semântica de despacho e de falha é garantida por:

- [`src/test/java/com/gomech/api/events/DomainEventDispatchSemanticsTest.java`](https://github.com/DeyvidJesus/gomech-backend-v2/blob/master/src/test/java/com/gomech/api/events/DomainEventDispatchSemanticsTest.java)

que valida que todo handler registrado para um tipo recebe o evento, que handlers de outros tipos não o recebem, que um handler com falha não interrompe os demais handlers nem quebra o publicador, e que a falha é registrada em log com sua causa.

A separação entre contrato e implementação é imposta pela regra de arquitetura `modules_must_use_the_event_bus_contract_not_its_implementation`: os módulos dependem de `DomainEventBus` e `DomainEventHandler`, nunca de `SpringDomainEventBus`, do dispatcher, do registry ou da factory de metadados.

## Fora do escopo

Esta ADR não:

- introduz brokers externos
- define entrega via outbox
- garante retries ou durabilidade
- substitui os testes de consumidor específicos de cada módulo
