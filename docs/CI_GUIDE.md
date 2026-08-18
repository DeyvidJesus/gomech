# CI Guide

## Purpose

The baseline CI workflow validates each service independently so failures are easy to locate and fix.

The workflow lives at `.github/workflows/ci.yml` and runs on:

- pushes to `main`
- every pull request

## What CI Checks

### Frontend

Working directory: `frontend/`

Commands:

```bash
npm ci
npm run lint
npm run build
```

### Backend

Working directory: `backend/`

Commands:

```bash
./mvnw -B -ntp test -Dtest='ModuleArchitectureRulesTest,ModuleArchitectureRuleFixturesTest' -DfailIfNoTests=false
./mvnw -B -ntp test
./mvnw -B -ntp test-compile failsafe:integration-test failsafe:verify
./mvnw -B -ntp -DskipTests package
```

The backend has two test lanes:

- **Unit lane** (`./mvnw test`, Surefire): every test that needs no infrastructure. It must stay
  runnable with nothing else started.
- **Integration lane** (Failsafe, class names ending in `IT`): tests that boot the full application
  context, which runs Flyway against PostgreSQL. The backend job provides PostgreSQL as a service
  container using the same image and credentials as `backend/docker-compose.yml`.

Architecture rules run first, as their own named step, so a module boundary violation is reported
as a boundary violation rather than as one failure among many.

### AI

Working directory: `ai/`

Commands:

```bash
python -m pip install --upgrade pip
pip install -r requirements.txt -r requirements-dev.txt
ruff check app
python -m compileall app
python -c "from app.main import app; print(app.title)"
```

## Why Failures Are Actionable

- Each service has its own job in GitHub Actions.
- Each validation step has an explicit name.
- Build and lint failures point to the service directory and exact command that failed.

## Local Reproduction

Run the same commands locally before opening a pull request:

### Frontend

```bash
cd frontend
npm ci
npm run lint
npm run build
```

### Backend

```bash
cd backend

# Unit lane: needs nothing running
./mvnw -B -ntp test

# Integration lane: needs PostgreSQL, started from this repository's own compose service
docker compose up -d postgres
./mvnw -B -ntp verify
```

### AI

```bash
cd ai
python -m pip install --upgrade pip
pip install -r requirements.txt -r requirements-dev.txt
ruff check app
python -m compileall app
python -c "from app.main import app; print(app.title)"
```

## Notes

- The workflow has no cloud dependency. The backend PostgreSQL service container runs inside the
  GitHub Actions runner.
- The backend validation uses the Maven wrapper already committed in the repository.
- The AI validation currently focuses on linting, syntax, and importability for fast baseline feedback.
