# ADR-002: Module Layering and Dependency Rules

## Status

Accepted

## Date

2026-08-18

## Context

GoMech V2 is being built as a single Spring Boot modular monolith with an independent AI service.

The repository already defines domain-oriented backend modules under `com.gomech.api.modules`, but module boundaries are not yet enforced consistently by code structure or automated tests. Without explicit layering and dependency rules, the monolith will drift toward shared persistence access, cyclic dependencies, and feature coupling that will be expensive to reverse once business modules are implemented.

The team needs one shared decision that makes the following explicit:

- how each backend module is layered
- who owns persistence and transactions
- which dependency directions are allowed
- how modules communicate
- how those rules map to architecture tests and forbidden imports

This ADR applies to the Spring Boot backend inside `gomech/backend`.

## Decision

Each business module will use the same internal layering model:

```text
com.gomech.api.modules.<module>
├── api
├── application
├── domain
└── infrastructure
```

Supporting cross-cutting code remains under `com.gomech.api.core`.

### Layer responsibilities

#### `api`

- Owns HTTP controllers, request/response DTOs, and public module contracts exposed to other modules.
- May depend on `application` and contract types from other modules.
- Must not depend directly on `infrastructure`.

#### `application`

- Owns use cases, orchestration, transactions, and application services.
- May depend on its own `domain`.
- May consume other modules only through explicit contracts in `api` or published events.
- Must not depend on another module's `domain` or `infrastructure`.

#### `domain`

- Owns business rules, aggregates, value objects, domain services, and invariants.
- Must not depend on `api`, `application`, Spring MVC, JPA repositories, or infrastructure adapters.
- Is the most stable layer and points only inward to itself or shared kernel types explicitly allowed in `core`.

#### `infrastructure`

- Owns persistence adapters, JPA entities, Spring Data repositories, external clients, messaging adapters, and framework integrations.
- May depend on `domain`.
- Must not be referenced directly by another module.

## Persistence ownership

Persistence ownership is module-local.

- Each module owns its tables, JPA entities, migrations, repositories, and persistence adapters.
- No module may read or write another module's repositories directly.
- No module may join against another module's tables through its own repository layer.
- Cross-module data access must occur through:
  - a public application contract exposed by the owning module's `api` package
  - a domain/application event consumed asynchronously

Examples:

- `operations` may not inject `inventory` repositories to decrement stock directly.
- `finance` may not query `operations` tables through a custom repository.
- `billing` may depend on `iam` contracts, but not on `iam` persistence types.

## Allowed dependency directions

Allowed dependencies inside a module:

- `api -> application`
- `application -> domain`
- `infrastructure -> domain`
- `infrastructure -> application` only for wiring adapters to application-defined ports when needed

Disallowed dependencies inside a module:

- `domain -> application`
- `domain -> api`
- `domain -> infrastructure`
- `application -> infrastructure` by concrete implementation type
- `api -> infrastructure`

Allowed dependencies across modules:

- `<module>.api -> <other-module>.api`
- `<module>.application -> <other-module>.api`
- `<module>.application -> <other-module>.events`

Disallowed dependencies across modules:

- `<module>.* -> <other-module>.domain`
- `<module>.* -> <other-module>.infrastructure`
- `<module>.* -> <other-module>.repositories`
- `<module>.* -> <other-module>.models`

## Communication rules

Cross-module communication uses explicit contracts only:

1. Synchronous calls through module-owned public contracts in `api`
2. Asynchronous integration through explicit events in `events`

No module may treat another module's entity model as a shared library.

The independent AI service is outside these in-process module rules. The backend may expose AI-facing application contracts, but the Python service does not receive direct database ownership through this ADR.

## Alternatives considered

### Keep the current controller/service/repository/model layout per module

Rejected because it does not distinguish public contracts from infrastructure and makes repository leakage likely.

### Full hexagonal architecture everywhere from day one

Rejected for now because it adds more indirection than the current team needs before the core business modules exist. The chosen four-layer model is a narrower rule set with simpler adoption.

### Allow cross-module repository access inside the monolith

Rejected because it couples persistence schemas, hides ownership boundaries, and makes future refactoring or extraction much harder.

## Trade-offs

### Benefits

- Makes persistence ownership explicit.
- Keeps domain rules insulated from transport and framework code.
- Gives the team one repeatable module template.
- Provides a direct path to automated architecture checks.

### Costs

- More packages and interfaces up front.
- Some use cases will require contract DTOs or events instead of direct repository reuse.
- Refactoring current early IAM code into the target package model will take follow-up work.

## Consequences

- New business modules must be created with `api/application/domain/infrastructure`.
- The former `controllers`, `dto`, `services`, `models`, and `repositories` packages are gone. IAM has been migrated to `api/application/domain/infrastructure` and `modules_must_follow_the_four_layer_layout` now prevents them from coming back.
- Architecture tests become part of the backend definition of done.
- Cross-module access requests should now be evaluated as contract design questions, not convenience imports.

## Enforcement rules

The following rules are enforced through ArchUnit tests. They run as part of `mvn test`, so a
forbidden dependency fails the build and fails CI.

| Rule | Enforcement target |
|------|--------------------|
| every module package is one of the four layers (or `events`) | `modules_must_follow_the_four_layer_layout` |
| controllers live in `api` | `controllers_must_reside_in_the_api_layer` |
| JPA entities live in `infrastructure` | `jpa_entities_must_reside_in_the_infrastructure_layer` |
| Spring Data repositories live in `infrastructure` | `spring_data_repositories_must_reside_in_the_infrastructure_layer` |
| `domain` does not depend on outer layers | `domain_must_not_depend_on_outer_layers` |
| `domain` does not depend on Spring, JPA, Hibernate, or the servlet API | `domain_must_not_depend_on_frameworks` |
| `application` does not depend on its own controllers or Spring web types | `application_must_not_depend_on_api_controllers` |
| `api` does not access `infrastructure` directly | `api_must_not_access_infrastructure_directly` |
| `core` does not depend on any business module | `core_must_not_depend_on_business_modules` |
| modules bind to core abstractions, not core implementations | `modules_must_not_depend_on_core_infrastructure` |
| modules do not import another module's persistence types | `cross_module_access_must_not_target_persistence` |
| modules reach other modules only through `api` and `events` | `cross_module_access_must_target_public_contracts_only` |
| modules do not call another module's controllers | `modules_must_not_depend_on_another_modules_controllers` |
| repositories are not imported outside their owning module | `repositories_must_not_be_imported_outside_their_module` |
| public contracts/events live in explicit packages | `module_contracts_must_live_in_api_or_events_packages` |
| no dependency cycle exists between modules | `modules_must_be_free_of_cycles` |

The layer rules apply to business modules **and** to the `core` slices, which use the same layer
names. Layer packages are matched as `..modules..<layer>..` and `..core..<layer>..` rather than a
bare `..api..`, because the application's own root package is `com.gomech.api` and the bare form
would match everything.

The four-layer layout is mandatory for business modules only. A core slice carries the layers it
actually needs, and the rules apply to whichever of them exist:

| Core slice | Layers present | Why |
|---|---|---|
| `audit` | `api`, `application`, `domain`, `infrastructure` | `AuditEntry` is a recorded fact with its own value semantics, so it has a domain type |
| `authorization` | `api`, `application`, `infrastructure` | its vocabulary (`ActorContext`, `AuthorizationRequest`, `AccessDecision`) *is* the published contract, so it lives in `api` |
| `entitlement` | `api`, `application`, `infrastructure` | same: `EntitlementSnapshot` is the contract |

An empty layer package is never created to satisfy the shape. Duplicating a contract type across
`api` and `domain` is what produced the dead `AuthorizationResult` and `EntitlementView` twins that
were removed; one representation per concept, in the layer that owns it.

Three rules classify by responsibility instead of package name — a `@RestController`, an `@Entity`,
and a Spring Data repository must each live in the right layer no matter which correctly-spelled
package it was dropped into. Because they carry a `that()` clause and no `allowEmptyShould`, they
also fail if the codebase ever contains none of that kind, so they cannot become vacuous.

Three properties of this rule set are deliberate.

**The allowed cross-module surface is defined by exclusion.** A module publishes its `api` and
`events` packages. Every other package behind `com.gomech.api.modules.<module>` is internal,
whatever it is called. A new internal package therefore needs no rule update to be protected.

**`application` may use its own `api` DTOs, but never its controllers.** This ADR places
request/response DTOs in `api`, and `application -> api` is not in the disallowed list above; the
enforcement target is `api` *implementations*. `application_must_not_depend_on_api_controllers`
therefore forbids a use case from depending on a `@RestController`/`@Controller` class or on any
`org.springframework.web` type, while leaving DTO records usable. This keeps HTTP out of use cases
without forcing a duplicate set of application-layer DTOs.

**Failures state the remedy.** Each rule carries a `because(...)` clause naming the way out, so a
violation reads as an instruction rather than a rejection:

```text
com.gomech.api.core.tenancy.SomeClass depends on
com.gomech.api.modules.iam.infrastructure.persistence.repository.UserRepository, but module 'iam'
owns that repository. Fix: ask the owning module for the data through its api contract instead of
importing its repository interface.
```

**The layer rules are no longer declared with `allowEmptyShould(true)`.** IAM now uses the target
layout, so `api`, `application`, `domain`, and `infrastructure` all match real production classes.
Dropping the flag means a rule that stops matching anything — after a package rename, or if a layer
is emptied — fails the build instead of passing vacuously. The violating fixtures described under
Testing remain the second guard.

### Known transitional deviation

`application` currently depends on Spring Data repository interfaces owned by `infrastructure`,
which the disallowed list above rules out "by concrete implementation type". Closing that gap needs
ports in `application` with adapters in `infrastructure`, and domain models kept separate from JPA
entities — the full hexagonal step this ADR deliberately deferred. No rule enforces that line yet;
it is tracked as follow-up work rather than silently treated as compliant.

## Testing

The rules are defined once in
[backend/src/test/java/com/gomech/api/architecture/ModuleArchitectureRules.java](/home/deyvid/Documents/work/gomech-project/gomech/backend/src/test/java/com/gomech/api/architecture/ModuleArchitectureRules.java)
and applied twice:

- [ModuleArchitectureRulesTest.java](/home/deyvid/Documents/work/gomech-project/gomech/backend/src/test/java/com/gomech/api/architecture/ModuleArchitectureRulesTest.java)
  checks them against production code.
- [ModuleArchitectureRuleFixturesTest.java](/home/deyvid/Documents/work/gomech-project/gomech/backend/src/test/java/com/gomech/api/architecture/ModuleArchitectureRuleFixturesTest.java)
  checks them against the deliberately violating fixtures in
  [architecture/fixtures/](/home/deyvid/Documents/work/gomech-project/gomech/backend/src/test/java/com/gomech/api/architecture/fixtures/),
  asserting that each rule still fails, names the offending class, and states its remedy.

The fixture test is what keeps the rule set honest. A rule that stops matching anything, after a
package rename or a typo in a package pattern, would otherwise keep passing against production code
forever. The fixtures live in test sources and are excluded from the production check by
`ImportOption.Predefined.DO_NOT_INCLUDE_TESTS`.

CI runs the architecture tests as a dedicated, separately named step in
[.github/workflows/ci.yml](/home/deyvid/Documents/work/gomech-project/.github/workflows/ci.yml)
before the full backend suite, so a boundary violation is reported as a boundary violation rather
than as one failure among many.

Follow-up work should extend these tests module by module as packages move from the current
transitional structure to the target layering.
