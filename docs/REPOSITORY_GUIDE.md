# Repository Guide

## Purpose

This repository is the shared engineering foundation for GoMech V2.

It standardizes:

- monorepo layout
- repository ownership boundaries
- Git conventions
- local development expectations
- secrets handling rules

## Monorepo Layout

```text
gomech/
├── ai/          # FastAPI AI service
├── backend/     # Spring Boot modular monolith
├── docs/        # Shared documentation
└── frontend/    # Web application
```

## Directory Ownership

### `frontend/`

- Contains the web application source code and UI-specific tooling.
- Owns browser-facing assets, frontend tests, and package-manager configuration.

### `backend/`

- Contains the Spring Boot application source code.
- Owns domain modules, persistence, migrations, API contracts, and backend tests.

### `ai/`

- Contains the independent FastAPI service and AI-specific dependencies.
- Owns AI prompts, agent orchestration, service-level tests, and Python tooling.

### `docs/`

- Contains shared product, architecture, setup, and repository documentation.
- Documentation should describe how to work in the repo without tribal knowledge.

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
