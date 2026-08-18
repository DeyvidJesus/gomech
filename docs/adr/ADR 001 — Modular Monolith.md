# ADR 001 — Modular Monolith

## Status

Accepted

## Date

2026-08-17

## Context

V2 backend is implemented as a single Spring Boot application.

The system is expected to contain multiple business capabilities that require clear ownership and boundaries. However, the current architectural scope does not justify deploying each business capability as an independent microservice.

The architecture therefore needs to establish clear internal module boundaries while retaining a single deployable backend application.

The primary architectural constraint is:

> Business modules are not microservices.

The modular structure is intended to improve separation of concerns, maintainability, ownership, testing, and future evolution without introducing the operational complexity of a distributed system prematurely.

## Decision

V2 backend will follow a **Modular Monolith** architecture.

The backend will remain a single Spring Boot application and will be deployed as a single deployable unit. Internally, the application will be divided into business-oriented modules with explicit boundaries and ownership.

Each business module is responsible for its own:

- Domain logic
- Application/use-case logic
- Module-specific data access
- Module-specific infrastructure concerns
- Public internal contracts

Modules must not directly depend on internal implementation details of other modules.

Communication between modules should occur through explicit contracts, interfaces, application services, or other approved module APIs.

Business modules must not be treated as independently deployable services.

## Module Ownership

Each module must have a clearly defined owner and responsibility.

The architecture documentation must maintain a module ownership map containing, at minimum:

| Module | Responsibility | Owner | Public API | Dependencies |
|---|---|---|---|---|
| `<module>` | `<business responsibility>` | `<owner>` | `<contract>` | `<modules>` |

Ownership means responsibility for maintaining the module's business rules, internal implementation, tests, and architectural boundaries.

A module may depend on another module only through an explicitly defined contract.

## Deployment Implications

All business modules are packaged and deployed as part of the same Spring Boot application.

Therefore:

- Modules share the same application runtime.
- Modules are released together.
- Modules scale together.
- A deployment affects the complete backend application.
- A module cannot be independently deployed.
- Infrastructure complexity associated with distributed services is avoided.

The modular structure is therefore a **code and architectural boundary**, not a deployment boundary.

## Alternatives Considered

### Microservices

Rejected for V2.

Microservices would provide independent deployment and scaling boundaries, but would also introduce additional operational and architectural complexity, including service-to-service communication, distributed failure modes, deployment coordination, observability, and data ownership concerns.

The current requirements do not justify that complexity.

### Traditional Monolith

Rejected.

A traditional monolith without explicit module boundaries would keep deployment simple but would make business boundaries less explicit and increase the risk of tight coupling between unrelated functionality.

The modular monolith provides the operational simplicity of a monolith while establishing stronger internal boundaries.

### Modular Monolith

Selected.

The modular monolith provides:

- A single deployable application
- Explicit business boundaries
- Lower operational complexity
- Easier local development
- Simpler testing and debugging
- Clear module ownership
- The possibility of extracting a module into a service in the future if justified

## Trade-offs

### Advantages

- Simpler deployment
- Lower infrastructure complexity
- Easier local development
- Easier debugging
- Stronger separation of business responsibilities
- Clearer ownership
- Lower network communication overhead
- Easier transactional consistency within the application

### Disadvantages

- Modules share the same deployment lifecycle
- Modules cannot scale independently
- A failure in the application can affect multiple modules
- Strong discipline is required to prevent module boundaries from degrading
- The application may become tightly coupled if internal module APIs are bypassed

## Consequences

The team must treat module boundaries as architectural constraints rather than merely package organization.

Architecture tests should verify that modules do not access prohibited implementation details from other modules and that dependency rules are respected.

New functionality must be assigned to an existing module or introduce a new business module only when a clear business boundary exists.

The architecture should not introduce microservice infrastructure solely because the codebase contains multiple modules.

If a future module requires independent deployment, scaling, ownership, or operational isolation, that decision must be evaluated separately through a new architectural decision.

## Implementation Notes

The Spring Boot project should organize code around business modules rather than technical layers spanning the entire application.

For example:

```text
backend/
└── src/
    └── main/
        └── java/
            └── <base-package>/
                ├── <module-a>/
                │   ├── domain/
                │   ├── application/
                │   ├── infrastructure/
                │   └── api/
                │
                ├── <module-b>/
                │   ├── domain/
                │   ├── application/
                │   ├── infrastructure/
                │   └── api/
                │
                └── <module-c>/
                    ├── domain/
                    ├── application/
                    ├── infrastructure/
                    └── api/
```

The exact module names and internal structure are defined by the core architecture documentation and should not be invented by this ADR.

## Architecture Tests

Architecture tests exist and validate the modular boundaries defined by the core architecture.

The implementation verifies:

- Modules cannot access prohibited internal packages of other modules.
- Dependency direction follows the defined architecture.
- Business modules do not depend directly on infrastructure belonging to another module.
- Modules expose only their intended public API, meaning their `api` and `events` packages.
- Shared `core` scaffolding never depends back on a business module.
- No dependency cycle exists between modules, which is what would make a module impossible to
  extract into a service later.

The rules, the production check, and the deliberately violating fixtures that prove each rule still
detects its violation are documented in
[ADR-002: Module Layering and Dependency Rules](/home/deyvid/Documents/work/gomech-project/gomech/docs/adr/ADR-002-module-layering-and-dependency-rules.md)
and implemented in
[backend/src/test/java/com/gomech/api/architecture/](/home/deyvid/Documents/work/gomech-project/gomech/backend/src/test/java/com/gomech/api/architecture/).

They run in `mvn test` and in CI, so a violation blocks the build rather than being caught in review.

## Dependencies

This ADR depends on the core architecture documentation for:

- Defined business modules
- Module responsibilities
- Dependency direction
- Module ownership
- Public module contracts

This ADR does not redefine those boundaries.

## Out of Scope

This ADR does not:

- Redesign the backend architecture
- Define individual business modules
- Define database schemas
- Define API endpoints
- Introduce microservices
- Define deployment infrastructure
- Establish a service extraction strategy

## Acceptance Criteria

- [X] ADR is reviewed and approved.
- [X] ADR is stored with the architecture documentation.
- [X] The modular monolith decision is explicitly documented.
- [X] Alternatives are documented.
- [X] Trade-offs are documented.
- [X] Consequences are documented.
- [X] Module ownership is documented or refersenced from the core architecture.
- [X] Deployment implications are documented.
- [X] Existing architecture tests are referenced.
- [X] Architecture tests verify the defined module boundaries.

## Related Documentation

- Core Architecture
- Backend Architecture
- Module Ownership Map
- Architecture Tests