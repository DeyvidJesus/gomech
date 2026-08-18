# ADR-004: REST API Conventions

## Status

Accepted

## Date

2026-08-18

## Context

GoMech V2 exposes its backend capabilities as a REST/JSON API under `/api/v1`, consumed by the web frontend, by future mobile clients, and by the independent AI service.

ADR-001 established the modular monolith. ADR-002 established module layering and placed HTTP controllers and request/response DTOs in each module's `api` package. ADR-003 established in-process events for cross-module consequences.

What is still missing is a single shared decision about how the HTTP surface itself behaves. Today:

- `/api/v1/users` and `/api/v1/auth/login` already exist, but conventions live only in reviewers' heads.
- `GlobalExceptionHandler` already returns RFC 7807 `ProblemDetail`, but only for two exception types and with an `invalidParams` shape that does not match [docs/API_SPECIFICATION.md](/home/deyvid/Documents/work/gomech-project/gomech/docs/API_SPECIFICATION.md).
- Pagination, filtering, and sorting are described per endpoint in the API specification but have no shared contract.
- Several planned endpoints have real financial or stock side effects (`/quotes/{id}/approve`, `/work-orders/{id}/status`, `/inventory/movements`, `/financial-transactions/{id}/pay`), and a retried request must not double-charge or double-consume stock.
- No OpenAPI generation is wired into the backend yet.

Without one decision, every new business module will invent its own envelope, error shape, and query parameters, and the frontend will absorb that inconsistency.

This ADR applies to the Spring Boot backend in `gomech/backend`.

## Decision

GoMech V2 exposes a **resource-oriented REST API over JSON**, versioned in the URI path under `/api/v1`, with standardized response behavior for errors, pagination, filtering, sorting, and idempotency, documented by an OpenAPI specification generated from code.

These conventions are mandatory for every business module. A module does not get to define its own envelope, its own error body, or its own paging parameters.

## Transport and representation

- Request and response bodies are JSON, UTF-8.
- Success responses use `application/json`.
- Error responses use `application/problem+json` (RFC 7807).
- Timestamps are ISO-8601 in UTC (`Instant`), for example `2026-06-01T14:00:00Z`. Local dates use `yyyy-MM-dd`.
- Monetary values are serialized as JSON numbers backed by `BigDecimal`, never as floating point in application code.
- Identifiers exposed to clients are UUIDs. Database sequence values are never exposed as public identifiers.
- JSON property names are `camelCase`.
- Unknown properties in a request body are rejected, not ignored, so client typos surface as validation failures instead of silently dropped fields.
- Clients must tolerate unknown properties in a response body. Adding a response field is not a breaking change.

## Resource and URL conventions

- Resource collections are plural, `kebab-case`: `/api/v1/work-orders`, `/api/v1/financial-transactions`.
- Resource instances are addressed by identifier: `/api/v1/work-orders/{id}`.
- Sub-resources nest at most one level: `/api/v1/inventory/movements`.
- Query parameters are `camelCase`.
- Verbs do not appear in resource paths. Business transitions that are not plain updates are modeled as an explicit sub-resource action using `POST` or `PUT`:
  - `POST /api/v1/quotes/{id}/approve`
  - `PUT /api/v1/work-orders/{id}/status`
  - `PUT /api/v1/financial-transactions/{id}/pay`
- Tenant scope is never a path or query parameter. It is derived from the authenticated principal and the tenant context, as handled by `TenantFilter` and `TenantContextHolder`.

### HTTP methods

| Method | Meaning | Idempotent |
|---|---|---|
| `GET` | Read a resource or collection. No side effects. | Yes |
| `POST` | Create a resource, or perform a business action on a sub-resource path. | No, unless an idempotency key is supplied |
| `PUT` | Replace a resource, or apply a declared state transition. | Yes |
| `PATCH` | Partially update a resource. Used sparingly. | No |
| `DELETE` | Remove or deactivate a resource. | Yes |

### HTTP status usage

| Status | When |
|---|---|
| `200 OK` | Successful read, update, or action that returns a body |
| `201 Created` | Resource created. Must include a `Location` header pointing at the new resource |
| `204 No Content` | Successful operation with no body, typically `DELETE` |
| `400 Bad Request` | Malformed JSON, unparseable parameter, unsupported filter or sort field |
| `401 Unauthorized` | Missing, expired, or invalid credentials |
| `403 Forbidden` | Authenticated but lacking the required permission |
| `404 Not Found` | Resource does not exist, or is not visible to the caller's tenant |
| `409 Conflict` | Uniqueness violation, invalid state transition, or idempotency key reuse with a different payload |
| `422 Unprocessable Entity` | Syntactically valid request that fails validation or a business invariant |
| `429 Too Many Requests` | Throttled, for example repeated failed logins |
| `500 Internal Server Error` | Unhandled failure. Never leaks stack traces |

A resource belonging to another tenant is reported as `404`, not `403`, so the API does not confirm the existence of other tenants' data.

## DTOs

DTOs are the API contract. They are not a serialization view of the persistence model.

Rules:

- Request and response DTOs are Java `record` types and live in the owning module's `api` package, per ADR-002.
- Controllers never accept or return JPA entities, and never return `Optional`, `Map<String, Object>`, or raw collections as the top-level body.
- Every DTO is directional. `CreateUserRequest` and `UserResponse` are separate types, even when their fields currently coincide.
- Naming: `<UseCase>Request`, `<Resource>Response`, `<Resource>SummaryResponse` for list projections.
- Secrets never appear in responses: passwords, password hashes, refresh token material, and internal tenant keys are excluded by omission from the DTO, not by annotation on an entity.
- A response DTO exposes only the fields the client needs. Widening a response later is cheap; narrowing it is a breaking change.
- List endpoints may return a lighter `SummaryResponse` than the single-resource endpoint. That difference must be documented in OpenAPI.

## Validation

Validation happens in two distinct places, and the split is deliberate:

1. **Shape validation** at the `api` boundary, using Jakarta Bean Validation annotations on the request DTO plus `@Valid` on the controller parameter. This covers required fields, formats, sizes, and ranges.
2. **Business invariants** in `domain` or `application`, per ADR-002. Uniqueness within a tenant, valid state transitions, stock sufficiency, and scope-of-access checks are not annotations on a DTO.

Both surface to the client through the same problem detail contract:

- Shape validation failure produces `422` with `invalidParams`.
- A violated business invariant produces `422` when the request is well formed but not acceptable, or `409` when it conflicts with the current state of a resource.
- Malformed JSON or an unparseable query parameter produces `400`.

Validation messages are stable and client-facing. They must not include SQL, class names, or stack traces.

## Error model

All errors follow RFC 7807 and are produced centrally by `GlobalExceptionHandler`. Controllers do not build error bodies.

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

Rules:

- `type` is a stable, documented URI under `https://gomech.com/docs/errors/<slug>`. It is part of the contract: clients may branch on it, so its meaning must not change within a major version.
- `title` is a short, stable, human-readable summary tied to `type`.
- `detail` explains this specific occurrence and may vary.
- `instance` is the request path.
- `invalidParams` is an **array of objects** with `name` and `reason`, so multiple problems on the same field are representable and ordering is stable.
- Extension members beyond `invalidParams` are allowed but must be documented in OpenAPI.

## Pagination

Every collection endpoint is paginated. A bare JSON array is never returned as a top-level body, because it cannot carry metadata and cannot be extended without breaking clients.

Request parameters:

| Parameter | Default | Constraint |
|---|---|---|
| `page` | `0` | Zero-based, `>= 0` |
| `size` | `20` | `1..100`. A larger value is rejected with `400` rather than silently clamped |

Response envelope, served by the shared `com.gomech.api.core.api.PageResponse<T>`:

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

Spring Data's `Page`/`PageImpl` is not serialized directly. Controllers map it to `PageResponse<T>` so the wire format is owned by us and does not shift with a framework upgrade.

Endpoints that additionally need aggregate figures, such as the finance cash-flow listing, expose them as a documented extension property on the envelope rather than as ad-hoc headers.

## Filtering

- Filters are explicit, typed query parameters named after the response field they filter: `?status=PENDING`, `?customerId=<uuid>`, `?licensePlate=ABC1234`.
- Range filters use the `<field>From` and `<field>To` suffixes: `?dueDateFrom=2026-06-01&dueDateTo=2026-06-30`. Both bounds are inclusive and independently optional.
- Multi-value filters repeat the parameter: `?status=PENDING&status=OVERDUE`. Comma-separated values are not used, because they collide with free-text content.
- Free-text search uses a single `q` parameter, and each endpoint documents which fields `q` searches.
- An unsupported or misspelled filter parameter is rejected with `400`. It is never ignored: silently dropping a filter returns a broader result set than the caller asked for, which is the more dangerous failure.
- Filters are always applied within the caller's tenant scope. A filter can narrow visibility, never widen it.
- No generic query language is accepted from clients. The set of filterable fields per endpoint is fixed and documented.

## Sorting

- Sorting uses the repeatable `sort` parameter in Spring's familiar form: `?sort=createdAt,desc&sort=name,asc`.
- Direction is optional and defaults to `asc`.
- Only an explicitly whitelisted set of sortable fields is accepted per endpoint. Any other field is rejected with `400`, which also prevents sorting from being used to probe columns that are not part of the contract.
- Every endpoint declares a deterministic default sort, and every sort resolves ties on `id` so pagination cannot repeat or skip rows between pages.
- Changing an endpoint's default sort is a breaking change.

## Idempotency

`GET`, `PUT`, and `DELETE` are idempotent by construction, and implementations must keep them that way: repeating a `PUT` state transition that has already been applied returns the current representation rather than failing.

`POST` endpoints with material side effects must additionally support the `Idempotency-Key` request header. This applies to, at minimum:

- resource creation with business consequences (`POST /api/v1/quotes`, `POST /api/v1/customers`)
- state transitions that move money or stock (`POST /api/v1/quotes/{id}/approve`, `PUT /api/v1/work-orders/{id}/status`, `POST /api/v1/inventory/movements`, `PUT /api/v1/financial-transactions/{id}/pay`)

Semantics:

- The client generates a UUID per logical operation and reuses it across retries of that same operation.
- The server records the key scoped by tenant and endpoint, together with a fingerprint of the request payload and the original response status and body.
- A replay with the same key and the same payload returns the **original recorded response**, and performs no additional side effect.
- A replay with the same key and a **different** payload is rejected with `409`, because the key no longer identifies one logical operation.
- Records are retained for 24 hours. After that, a key is treated as new.
- A request without the header on an endpoint that supports it is processed normally. The header is a client safety mechanism, not an authentication step.

Idempotency storage is cross-cutting and owned by `core`, not duplicated per module.

Concurrency on updates is a separate concern: state-transition endpoints validate the current state as part of the transition, and may adopt optimistic locking with `If-Match`/ETag when a real lost-update problem appears.

## Versioning and contract compatibility

The API version lives in the URI path: `/api/v1`. All resources share one version.

**Backward-compatible, allowed within `/api/v1`:**

- adding a new endpoint
- adding a new **optional** request field
- adding a new response field
- adding a new optional filter, sort field, or query parameter
- relaxing a validation constraint
- adding a new documented error `type` for a case that previously returned a generic error of the same status

**Breaking, requires `/api/v2`:**

- removing or renaming a field, endpoint, or parameter
- making an optional request field required
- changing a field's type, or making a previously non-null response field nullable
- tightening a validation constraint
- changing the HTTP status or error `type` returned for an existing case
- changing an endpoint's default sort, default page size, or pagination semantics
- adding a value to a response enum, unless that field is documented as extensible and clients are told to tolerate unknown values

When `/api/v2` is introduced, `/api/v1` remains supported for a deprecation window agreed with the frontend, and deprecated operations are marked `deprecated` in OpenAPI before removal.

## OpenAPI documentation expectations

- The OpenAPI 3 specification is **generated from code** via springdoc-openapi. Annotated controllers and DTOs are the single source of truth; the specification is never hand-edited.
- The generated specification is served at `/v3/api-docs`, with the interactive UI at `/swagger-ui`. Both are open in `local` and `dev`, and access-restricted in `staging` and `prod`.
- Every operation documents: `operationId`, summary, the required permission, request schema, success response schema, and every error status it can return.
- Every DTO field that is not self-explanatory carries a description and, where useful, an example.
- CI exports the generated specification as a build artifact so contract diffs between commits are reviewable. A diff that matches the breaking-change list above must be justified in review or moved to a new version.
- [docs/API_SPECIFICATION.md](/home/deyvid/Documents/work/gomech-project/gomech/docs/API_SPECIFICATION.md) remains the narrative, per-module description of intent. Where the two disagree about the shape of a payload, the generated specification wins, and the narrative document is corrected.

## Alternatives considered

### Header or media-type versioning instead of URI versioning

Rejected. Version-in-path is trivially visible in logs, browsers, cURL, and CI contract snapshots, and it costs nothing to route. Header negotiation is more elegant and considerably harder to debug for a small team.

### No versioning at all, evolving `/api` in place

Rejected. The frontend and the AI service deploy independently of the backend, so at least one consumer will always be running against an older contract.

### A custom error envelope instead of RFC 7807

Rejected. `ProblemDetail` is already in use and is native to Spring Boot 3, so the standard costs nothing and gives clients a documented shape they may already know.

### Wrapping every success response in `{ "data": ..., "meta": ... }`

Rejected. It adds a level of nesting to every single-resource read to solve a problem that only collections have, and collections are already solved by `PageResponse`.

### Cursor-based pagination

Rejected for V2. Page-based paging matches the UI, which needs page numbers and total counts, and matches Spring Data directly. It is revisited if a high-volume append-only listing such as inventory movements or audit history outgrows offset paging; that would be a new ADR.

### A generic query language such as RSQL or OData

Rejected. It exposes the persistence model to clients, makes the queryable surface unbounded and hard to index, and turns tenant-scope enforcement into a parsing problem. Explicit typed filters keep the contract and the query plan both reviewable.

### Client-generated resource identifiers instead of `Idempotency-Key`

Rejected as the general mechanism. It only solves duplicate creation, not duplicate state transitions such as paying a transaction twice, which is where the real financial risk sits.

### Design-first OpenAPI, with the specification authored by hand

Rejected for now. With a small team and no external API consumers yet, a hand-authored specification drifts from the implementation, and drifted documentation is worse than none. Revisit if a partner or public API appears.

## Trade-offs

### Benefits

- One contract shape across every module: the frontend writes its HTTP layer once.
- Error handling is centralized and machine-readable, and stack traces cannot leak.
- Pagination, filtering, and sorting are predictable enough to be implemented by shared helpers instead of per endpoint.
- Idempotency makes retries safe on exactly the endpoints where a duplicate is expensive.
- Generated OpenAPI makes contract drift visible in code review rather than in production.

### Costs

- Rejecting unknown request fields and unsupported filter parameters is stricter than the framework defaults, so a client typo becomes a visible failure rather than a silent no-op. That is the intent, but it requires explicit configuration and clear error messages.
- Always paginating means even small, obviously bounded lists carry envelope overhead.
- Idempotency requires shared storage, a retention policy, and per-endpoint discipline.
- The whitelist approach to filter and sort fields means adding a filter is a deliberate change, not a free query parameter.
- URI versioning duplicates a controller surface the day `/api/v2` arrives.

## Consequences

- New endpoints are reviewed against this ADR, not against whatever the nearest existing controller happens to do.
- `PageResponse<T>` becomes the required return shape for collection endpoints, and Spring Data `Page` never crosses the HTTP boundary.
- `GlobalExceptionHandler` grows to cover authentication, authorization, not-found, conflict, and fallback cases, with stable `type` URIs, instead of the current two handlers.
- The existing `invalidParams` map is replaced by the array form documented here, aligning the implementation with the API specification.
- springdoc-openapi must be added to the backend build; until it is, the OpenAPI expectations in this ADR are unmet and tracked as follow-up work.
- Idempotency support requires a `core`-owned store before the first money- or stock-moving endpoint ships.
- Range filters standardize on `<field>From`/`<field>To`, so the `startDate`/`endDate` parameters sketched for the finance listing are renamed before that endpoint ships.
- If a future consumer needs a materially different query or delivery model, that is a new ADR, not an exception carved into `/api/v1`.

## Enforcement and usage rules

| Rule | Expectation |
|---|---|
| Controllers live in the module's `api` package | ADR-002 layering, checked by `ModuleArchitectureRulesTest` |
| No JPA entity in a controller signature | Code review, extendable to an ArchUnit rule |
| Collection endpoints return `PageResponse<T>` | Code review and contract tests |
| Errors are produced only by `GlobalExceptionHandler` | No `ResponseEntity` error bodies built in controllers |
| Every endpoint is annotated for OpenAPI | Generated specification reviewed in CI |
| Breaking changes bump the path version | Contract diff review against the compatibility rules above |

## Testing

Reference API contract tests live in:

- [backend/src/test/java/com/gomech/api/api/RestApiContractTest.java](/home/deyvid/Documents/work/gomech-project/gomech/backend/src/test/java/com/gomech/api/api/RestApiContractTest.java)

That reference test pins the baseline conventions this ADR defines: the `/api/v1` base path, `201 Created` with a `Location` header, the RFC 7807 problem detail shape including the `invalidParams` array, the `PageResponse` envelope, rejection of an unsupported sort field, and `Idempotency-Key` replay returning the original response without repeating the side effect.

Module-specific endpoints should add their own contract tests for:

- the permission required by each operation
- validation failures specific to that resource
- filter and sort behavior, including rejection of unsupported fields
- pagination boundaries, including the `size` maximum
- idempotent replay on any endpoint with financial or stock side effects

## Dependencies

This ADR depends on and extends:

- [ADR 001 — Modular Monolith](/home/deyvid/Documents/work/gomech-project/gomech/docs/adr/ADR%20001%20%E2%80%94%20Modular%20Monolith.md)
- [ADR-002: Module Layering and Dependency Rules](/home/deyvid/Documents/work/gomech-project/gomech/docs/adr/ADR-002-module-layering-and-dependency-rules.md)
- [ADR-003: Domain Events](/home/deyvid/Documents/work/gomech-project/gomech/docs/adr/ADR-003-domain-events.md)
- [docs/BACKEND_ARCHITECTURE.md](/home/deyvid/Documents/work/gomech-project/gomech/docs/BACKEND_ARCHITECTURE.md)
- [docs/API_SPECIFICATION.md](/home/deyvid/Documents/work/gomech-project/gomech/docs/API_SPECIFICATION.md)

It does not redefine module boundaries, layering, or event semantics.

## Out of scope

This ADR does not:

- introduce GraphQL, gRPC, or any non-REST transport
- define the authentication or permission model itself, which belongs to the IAM and security documentation
- define outbound webhooks or a partner/public API program
- define rate-limiting policy beyond noting `429` as the status for throttled requests
- define the internal protocol between the backend and the independent AI service
- introduce HATEOAS or hypermedia link relations
- define caching headers or CDN behavior
- define individual module endpoints, which remain the responsibility of the API specification and each module's design

## Acceptance Criteria

- [X] ADR is reviewed and approved.
- [X] ADR is stored with the architecture documentation.
- [X] REST/JSON and `/api/v1` versioning are explicitly decided.
- [X] Alternatives are documented.
- [X] Trade-offs are documented.
- [X] Consequences are documented.
- [X] DTO rules are documented.
- [X] Validation split between transport and domain is documented.
- [X] The RFC 7807 error contract is documented.
- [X] Pagination, filtering, and sorting contracts are documented.
- [X] Idempotency expectations are documented.
- [X] Contract compatibility rules are explicit.
- [X] OpenAPI documentation expectations are set.
- [X] Reference API contract tests are referenced.

## Related Documentation

- Core Architecture
- Backend Architecture
- API Specification
- Generated OpenAPI specification at `/v3/api-docs`
