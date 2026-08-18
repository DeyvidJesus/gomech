# ADR-003: Domain Events

## Status

Accepted

## Date

2026-08-18

## Context

GoMech V2 is a modular monolith. Business modules need a way to react to meaningful consequences raised by other modules without creating direct repository dependencies or service-level coupling.

ADR-001 established the modular monolith. ADR-002 established module layering, persistence ownership, and the rule that cross-module communication must happen through explicit contracts or events.

This ADR defines when in-process domain/application events should be used, what they mean, and what delivery assumptions consumers are allowed to rely on.

The goal is decoupled cross-module behavior, not generic eventification of every write operation.

## Decision

GoMech will use in-process Spring application events for meaningful cross-module consequences inside the backend monolith.

Events are:

- initially in-process only
- published inside the same JVM
- intended for meaningful business consequences across modules
- not created by default for CRUD operations

This ADR applies to the Spring Boot backend in `gomech/backend`.

## When to publish an event

An event should be published when all of the following are true:

1. One module completes a business action with consequences relevant to another module.
2. The consequence should remain decoupled from the publisher's persistence implementation.
3. The consumer does not need to participate by directly calling the publisher's repository layer.
4. The event name expresses a business fact that already happened.

Events should not be published for:

- every create, update, or delete by default
- internal method choreography inside the same module
- technical lifecycle notifications with no business meaning
- cases where a direct synchronous module contract is clearer than an event

## Event selection

Use events for meaningful cross-module consequences such as:

- `WorkOrderCompleted`
  - Example consequence: finance creates an accounts-receivable entry
  - Example consequence: inventory finalizes stock consumption reporting
- `InventoryPurchaseRecorded`
  - Example consequence: finance records supplier payable intent
  - Example consequence: analytics refreshes purchase trends

These are examples of business facts, not transport payload conventions.

## Event meaning

An event describes something that has already happened from the publisher's point of view.

Event names must:

- use past-tense business language
- reflect a completed business fact
- be meaningful without referencing transport details

Good examples:

- `WorkOrderCompleted`
- `InventoryPurchaseRecorded`
- `InvoiceIssued`

Bad examples:

- `WorkOrderUpdated`
- `SaveInventoryThing`
- `AfterControllerReturned`

## Delivery assumptions

The initial delivery model is explicitly limited:

- delivery is in-process
- delivery is inside the same application runtime
- events are not durable
- events are not replayable by default
- events are not broker-backed

Consumers may assume:

- the publisher and consumer share the same codebase and JVM process
- the event payload is available immediately to Spring listeners

Consumers must not assume:

- message durability after a process crash
- automatic retries
- cross-process delivery
- broker semantics such as partitions, offsets, or dead-letter queues

If the process crashes after the business transaction commits but before a listener completes, the event consequence may be lost. That is an accepted limitation of the V1 in-process model.

## Consumer behavior

Consumers must:

- belong to the module that owns the consequence
- treat the event as an input contract, not as permission to reach into another module's tables
- remain idempotent when feasible
- keep processing focused and fast
- avoid interactive or long-running orchestration in the listener itself

Consumers should prefer:

- creating their own records using their own repositories
- calling their own application services
- logging enough context for diagnosis

Consumers must not:

- mutate the publisher's persistence model directly
- import another module's repositories or entities
- rely on event ordering across unrelated listeners unless explicitly designed and tested

## Transaction and publication behavior

By default, GoMech events are in-process Spring events.

For cross-module consequences that must observe committed state, publication/consumption should prefer transaction-aware listener behavior such as `@TransactionalEventListener` with `AFTER_COMMIT`.

That means:

- the publisher owns the primary business transaction
- consumers observe a completed business fact
- consumers should not assume they can roll back the publisher's write after commit

Module-specific implementations must test the chosen listener style explicitly.

## Alternatives considered

### Direct cross-module service calls only

Rejected because some consequences are better modeled as reactions to completed business facts than as synchronous orchestration chains.

### Kafka or RabbitMQ from the start

Rejected for V1. Broker infrastructure adds operational and delivery complexity that the current system does not yet need.

### Emit CRUD events for every write

Rejected because it creates noise, weakens event meaning, and encourages accidental coupling to persistence churn rather than business outcomes.

## Trade-offs

### Benefits

- Decouples cross-module consequences from direct persistence access.
- Keeps module ownership intact.
- Makes business reactions explicit in the codebase.
- Fits the modular monolith without extra infrastructure.

### Costs

- Delivery is not durable.
- Failures in listeners require deliberate handling.
- Poor event selection would create noise quickly.
- Some behaviors still need synchronous contracts instead of events.

## Consequences

- Cross-module reactions must be designed intentionally, not inferred from CRUD.
- Event consumers become part of module behavior and should be tested as first-class code.
- If future requirements need durability, replay, or independent scaling, a new ADR must revisit the delivery model.
- The current architecture keeps events as a modular-monolith tool, not a distributed-systems abstraction.

## Enforcement and usage rules

- Events live in explicit module packages such as `events` or another clearly public contract package.
- Event payloads should contain the identifiers and business context needed by consumers without exposing internal persistence structures.
- Consumers use their own module services and repositories only.
- No module may depend on another module's persistence types in order to consume an event.

This ADR complements the rules in [ADR-002: Module Layering and Dependency Rules](/home/deyvid/Documents/work/gomech-project/gomech/docs/adr/ADR-002-module-layering-and-dependency-rules.md).

## Testing

Reference event consumer tests live in:

- [backend/src/test/java/com/gomech/api/events/InProcessDomainEventConsumerTest.java](/home/deyvid/Documents/work/gomech-project/gomech/backend/src/test/java/com/gomech/api/events/InProcessDomainEventConsumerTest.java)

That reference test validates the baseline assumption that named business events such as `WorkOrderCompleted` and `InventoryPurchaseRecorded` are consumed in-process by dedicated listeners.

Module-specific event consumers should add their own tests for:

- listener side effects
- idempotent handling where required
- transaction-aware publication/consumption behavior
- failure handling for the chosen consequence path

## Out of scope

This ADR does not:

- introduce Kafka, RabbitMQ, or another broker for V1
- require CRUD events by default
- define an outbox pattern
- define cross-service integration events for the independent AI service
