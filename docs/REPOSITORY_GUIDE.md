# Repository Guide

## Purpose

This repository is the shared engineering foundation for GoMech V2.

It standardizes:

- monorepo layout
- repository ownership boundaries
- Git conventions
- local development expectations
- secrets handling rules

## Repository Layout & Submodules

```text
gomech/
├── ai/          # Git Submodule -> DeyvidJesus/gomech-ai-service-v2 (FastAPI)
├── backend/     # Git Submodule -> DeyvidJesus/gomech-backend-v2 (Spring Boot 3.3)
├── frontend/    # Git Submodule -> DeyvidJesus/gomech-frontend-v2 (React 18 + Vite)
├── docs/        # Core engineering guides and ADRs
└── docker-compose.yml # Multi-service local stack
```

## Submodule & Directory Ownership

### `frontend/` (`gomech-frontend-v2`)

- Contains the web application source code and UI tooling (React 18, Vite, TypeScript, Tailwind).
- Owns browser-facing assets, frontend tests, and package-manager configuration.

### `backend/` (`gomech-backend-v2`)

- Contains the Spring Boot 3.3 modular monolith source code.
- Owns domain modules, persistence, Flyway migrations, API contracts, RLS policies, and backend tests.

### `ai/` (`gomech-ai-service-v2`)

- Contains the FastAPI Python 3.12 service.
- Owns AI prompts, agent orchestration, service-level tests, and Python tooling.

### `docs/`

- Contains shared engineering guides (`STARTUP_GUIDE.md`, `CI_GUIDE.md`, `BACKEND_ARCHITECTURE.md`) and Architectural Decision Records (`docs/adr/`).
- Higher-level product specifications, UX wireframes, and project roadmaps are maintained in **Linear Docs**.


## Git Conventions

### Branch Naming

Use short, descriptive branch names:

- `feature/<topic>`
- `fix/<topic>`
- `chore/<topic>`
- `docs/<topic>`

Examples:

- `feature/monorepo-foundation`
- `docs/repository-guide`

### Commit Style

Prefer focused commits with an imperative subject line:

- `feat: add monorepo scaffold`
- `docs: add repository guide`
- `chore: add shared editor conventions`

### Pull Request Expectations

Every PR should:

- have one clear purpose
- include setup or behavior notes when relevant
- update documentation when repository behavior changes
- avoid mixing infrastructure setup with unrelated product changes

## Secrets and Configuration

- Never commit real secrets.
- Keep machine-specific values in untracked `.env` files.
- Commit only examples such as `.env.example`.
- Document configuration ownership in `docs/` when a new variable is introduced.

## Clean-Clone Check

A clean clone should allow a developer to:

1. understand the repository structure from the root `README.md`
2. identify where frontend, backend, AI, and docs belong
3. find setup and convention documentation in `docs/`
4. create local environment files without copying secrets from source control

## Architectural Constraints

- One Spring Boot modular monolith in `backend/`
- One independent FastAPI service in `ai/`
- No Kubernetes assumptions in repository structure
