# Startup Guide

## Objective

This repository provides a one-command local development stack for:

- `frontend`
- `backend`
- `ai`
- `postgres`

## Prerequisites

- Docker Desktop or Docker Engine with Compose support

## First-Time Setup

From the repository root:

```bash
cp .env.example .env
docker compose up --build
```

## Service Endpoints

- Frontend: `http://localhost:5173`
- Backend API: `http://localhost:8080`
- Backend health: `http://localhost:8080/actuator/health`
- AI service: `http://localhost:8000`
- AI health: `http://localhost:8000/health`
- PostgreSQL: `localhost:5432`

## Environment Ownership

### Root `.env`

Shared local Docker Compose configuration:

- database name, user, password, and port
- exposed service ports
- backend profile
- frontend API base URL
- local JWT placeholder secret

### `ai/.env.example`

AI-service-specific example values that are safe to commit.

## Development Notes

- PostgreSQL data persists in the `postgres-data` Docker volume.
- Frontend dependencies persist in the `frontend-node-modules` Docker volume.
- Source code is bind-mounted for `frontend` and `ai` so code changes are reflected without rebuilding the whole image.
- The backend image is rebuilt when backend code changes are needed in the containerized flow.

## Common Commands

Start everything:

```bash
docker compose up --build
```

Run in the background:

```bash
docker compose up --build -d
```

Stop the stack:

```bash
docker compose down
```

Stop the stack and remove named volumes:

```bash
docker compose down -v
```

## Smoke Test

After startup, verify:

1. `docker compose ps` shows all four services as running.
2. `http://localhost:5173` loads the frontend.
3. `http://localhost:8080/actuator/health` returns an `UP` health response.
4. `http://localhost:8000/health` returns `{"status":"ok"}`.
