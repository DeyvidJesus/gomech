# GoMech

GoMech is the orchestration repository for the GoMech V2 platform used by mechanical workshops to manage operations, customers, services, finances, and AI-assisted workflows in one place.

## Repository Architecture

This workspace orchestrates independent domain repositories via **Git Submodules**:

```text
gomech/
├── ai/        # Git Submodule -> DeyvidJesus/gomech-ai-service-v2 (FastAPI AI Service)
├── backend/   # Git Submodule -> DeyvidJesus/gomech-backend-v2 (Spring Boot 3.3 Modular Monolith)
├── frontend/  # Git Submodule -> DeyvidJesus/gomech-frontend-v2 (React 18 + Vite Web App)
├── docs/      # Shared architecture ADRs, blueprints, and database specifications
└── docker-compose.yml # Unified local development stack
```

### Component Repositories

| Submodule | Repository | Technology | Description |
| :--- | :--- | :--- | :--- |
| **`ai`** | [`gomech-ai-service-v2`](https://github.com/DeyvidJesus/gomech-ai-service-v2) | Python 3.12, FastAPI | Autonomous diagnostic agents and AI processing |
| **`backend`** | [`gomech-backend-v2`](https://github.com/DeyvidJesus/gomech-backend-v2) | Java 21, Spring Boot 3.3, PostgreSQL 16 | Core business logic, Clean Architecture, RLS multi-tenancy |
| **`frontend`** | [`gomech-frontend-v2`](https://github.com/DeyvidJesus/gomech-frontend-v2) | React 18, TypeScript, Vite, TanStack | Modern workshop management web application |

---

## Cloning & Working with Submodules

### Clone with Submodules

To clone the entire project including all service repositories:

```bash
git clone --recurse-submodules git@github.com:DeyvidJesus/gomech.git
```

### If Already Cloned

To initialize and fetch all submodules:

```bash
git submodule update --init --recursive
```

### Pulling Latest Changes for All Submodules

```bash
git submodule update --remote --merge
```

---

## Local Development Stack

The local development stack is orchestrated from the repository root with Docker Compose:

1. Copy the shared environment template:
   ```bash
   cp .env.example .env
   ```

2. Start the full stack:
   ```bash
   docker compose up --build
   ```

### Active Services:

- **Frontend**: [http://localhost:5173](http://localhost:5173)
- **Backend API**: [http://localhost:8080](http://localhost:8080)
- **AI Service**: [http://localhost:8000](http://localhost:8000)
- **PostgreSQL 16**: `localhost:5432` (`gomech_db`)

---

## Documentation

- [docs/adr/README.md](docs/adr/README.md) — Architecture Decision Records (ADRs 001–012)
- [docs/BACKEND_ARCHITECTURE.md](docs/BACKEND_ARCHITECTURE.md) — Modular monolith & Clean Architecture guide
- [docs/DATABASE_READINESS_REPORT.md](docs/DATABASE_READINESS_REPORT.md) — PostgreSQL, Flyway, and RLS specifications
- [docs/STARTUP_GUIDE.md](docs/STARTUP_GUIDE.md) — Local environment setup and execution
- [docs/CI_GUIDE.md](docs/CI_GUIDE.md) — CI/CD validation baseline

