# ADR-008: In-Process Domain Event Bus

## Status

Accepted

## Date

2026-08-18

## Context

ADR-003 established that GoMech uses in-process events for meaningful cross-module consequences inside the modular monolith.

That decision still needs a concrete runtime mechanism so modules can publish typed events, preserve audit metadata, register handlers explicitly, and dispatch events without direct publisher-to-consumer coupling.

The backend needs a V1 event bus that:

- stays in-process
- uses explicit contracts
- preserves audit metadata for listeners
- supports typed handler registration
- keeps external brokers out of scope

## Decision

GoMech will implement a Spring-backed in-process domain event bus in `com.gomech.api.core.events`.

The event bus consists of:

- `DomainEvent`: marker contract for typed event payloads
- `EventMetadata`: audit-oriented metadata captured at publish time
- `EventEnvelope<T>`: typed wrapper carrying payload plus metadata
- `DomainEventHandler<T>`: explicit handler contract
- `DomainEventBus`: publishing contract
- `EventHandlerRegistry`: handler registration and lookup
- `SpringDomainEventBus`: publisher implementation
- `SpringDomainEventDispatcher`: in-process dispatcher implementation

## Event envelope

Every dispatched event is wrapped in an envelope containing:

- `eventId`
- `eventType`
- `occurredAt`
- `tenantId`
- `userId`
- `correlationId`

The payload remains typed and implements `DomainEvent`.

This preserves the metadata needed for auditing, tracing, and consumer-side logging without forcing handlers to reach back into request-scoped infrastructure.

## Handler contract and registration

Handlers implement:

```java
DomainEventHandler<T extends DomainEvent>
```

Each handler declares:

- the event type it supports
- its `handle(EventEnvelope<T>)` method

Registration is automatic through Spring bean discovery. The registry groups handlers by their declared event type and dispatches only to matching handlers.

## Dispatch behavior

- publishers call `DomainEventBus.publish(event)`
- the bus creates an `EventEnvelope`
- metadata is captured immediately from the active tenant/security/logging context
- the envelope is published inside the same Spring application
- the dispatcher routes the envelope to all registered handlers for that payload type

Matching is on the payload's runtime class. A handler declaring a supertype does not receive
subtypes, which keeps module contracts explicit and compiler-checked.

### Handler failure semantics

Handlers are isolated from one another. A handler that throws is logged at ERROR with its cause, the
event type and the event id, under the publishing request's correlation id, and dispatch continues
to the remaining handlers.

This follows from two decisions already made rather than adding a new one:

- an envelope goes to *all* registered handlers, so one broken consumer must not suppress the
  consumers that happen to be registered after it — which, with Spring bean discovery, would
  otherwise depend on bean ordering;
- ADR-003 states a consumer reacts to a business fact that has already happened, must not roll back
  the publisher, and owns the deliberate handling of its own failures.

So a handler failure is neither hidden nor propagated to the publisher. A consumer that needs
retries, compensation or a dead-letter path implements that itself, and tests it as ADR-003 requires.

## Delivery assumptions

The delivery model matches ADR-003:

- in-process only
- same JVM only
- no broker
- no durability guarantee
- no replay guarantee

Registered handlers should expect to receive the typed envelope synchronously through the in-process Spring event mechanism unless a specific listener strategy changes that behavior.

## Alternatives considered

### Publish raw Spring events directly everywhere

Rejected because it would leave contract shape, metadata preservation, and handler registration conventions implicit and inconsistent.

### Introduce Kafka or RabbitMQ now

Rejected because V1 requires in-process modular communication only.

### Use untyped map-based event payloads

Rejected because module contracts should stay explicit and compiler-checked.

## Trade-offs

### Benefits

- Typed contracts for publishers and consumers
- Shared audit metadata for every dispatched event
- Automatic handler registration
- Clear separation between business payload and transport metadata

### Costs

- Another core abstraction to maintain
- Spring remains part of the in-process dispatch mechanism
- Delivery guarantees remain intentionally limited

## Consequences

- Modules should publish `DomainEvent` payloads rather than ad hoc Spring event objects.
- Consumers receive envelopes instead of bare payloads so metadata stays available.
- Handler implementations remain explicit, discoverable, and testable.
- Future migration to stronger delivery guarantees would require a new ADR rather than silently changing this contract.

## Testing

Dispatch behavior is referenced by:

- [backend/src/test/java/com/gomech/api/events/DomainEventBusDispatchTest.java](/home/deyvid/Documents/work/gomech-project/gomech/backend/src/test/java/com/gomech/api/events/DomainEventBusDispatchTest.java)

That test validates:

- registered handlers receive matching typed events
- metadata is preserved in the envelope
- unregistered event types are ignored

Dispatch and failure semantics are pinned by:

- [backend/src/test/java/com/gomech/api/events/DomainEventDispatchSemanticsTest.java](/home/deyvid/Documents/work/gomech-project/gomech/backend/src/test/java/com/gomech/api/events/DomainEventDispatchSemanticsTest.java)

which validates that every handler registered for a type receives the event, that handlers for other
types do not, that a failing handler neither stops the remaining handlers nor breaks the publisher,
and that the failure is logged with its cause.

The contract/implementation split is enforced by the architecture rule
`modules_must_use_the_event_bus_contract_not_its_implementation`: modules bind to `DomainEventBus`
and `DomainEventHandler`, never to `SpringDomainEventBus`, the dispatcher, the registry or the
metadata factory.

## Out of scope

This ADR does not:

- introduce external brokers
- define outbox delivery
- guarantee retries or durability
- replace module-specific consumer tests
