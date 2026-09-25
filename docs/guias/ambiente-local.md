# Ambiente local

Como subir a plataforma inteira (PostgreSQL, backend, AI Service e frontend) com um único comando.

## Pré-requisitos

- Docker Engine ou Docker Desktop com Compose v2
- Git (para clonar com submódulos)

Para rodar um serviço fora do Docker, veja o README do respectivo repositório: [backend](https://github.com/DeyvidJesus/gomech-backend-v2#readme), [frontend](https://github.com/DeyvidJesus/gomech-frontend-v2#readme) e [AI Service](https://github.com/DeyvidJesus/gomech-ai-service-v2#readme).

## Primeira execução

```bash
git clone --recurse-submodules https://github.com/DeyvidJesus/gomech.git
cd gomech
cp .env.example .env
docker compose up --build
```

Se o repositório já foi clonado sem os submódulos:

```bash
git submodule update --init --recursive
```

## Endereços

| Serviço | URL |
| :--- | :--- |
| Frontend | http://localhost:5173 |
| Backend (API) | http://localhost:8080/api/v1 |
| Backend (health) | http://localhost:8080/actuator/health |
| Backend (Swagger UI) | http://localhost:8080/swagger-ui.html |
| AI Service (health) | http://localhost:8000/health |
| AI Service (OpenAPI) | http://localhost:8000/docs |
| PostgreSQL | `localhost:5432` (banco `gomech_db`) |

As migrations do Flyway rodam automaticamente quando o backend sobe.

## Variáveis de ambiente

Tudo é configurado pelo `.env` da raiz, a partir do [`.env.example`](../../.env.example). O `docker-compose.yml` repassa a cada container **apenas** as variáveis de que ele precisa.

| Variável | Usada por | Descrição |
| :--- | :--- | :--- |
| `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_PORT` | postgres, backend | Banco local |
| `BACKEND_PORT`, `FRONTEND_PORT`, `AI_PORT` | compose | Portas publicadas no host |
| `SPRING_PROFILES_ACTIVE` | backend | Profile do Spring (`local` por padrão) |
| `JWT_SECRET` | backend | Chave de assinatura dos access tokens |
| `PAGARME_MOCK_ENABLED` | backend | `true` simula o gateway de pagamento sem chave real |
| `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_REDIRECT_URI` | backend | Login com Google (opcional) |
| `AI_SERVICE_AUTH_SECRET` | backend, ai | Segredo compartilhado entre o AI Gateway e o AI Service |
| `AI_DEFAULT_PROVIDER`, `GEMINI_API_KEY` | ai | Provider de IA (`mock` por padrão, sem custo) |
| `VITE_API_URL` | frontend | URL base da API consumida pelo navegador |

## Hot reload

- **Frontend:** o código é montado no container e o Vite recarrega a cada alteração. As dependências ficam no volume `frontend-node-modules`.
- **AI Service:** `ai/app` é montado no container e o `uvicorn --reload` reinicia o processo a cada alteração.
- **Backend:** a imagem é compilada no build. Depois de mudar código Java, rode `docker compose up --build backend`, ou execute o backend fora do Docker pela IDE.

## Comandos úteis

```bash
docker compose up --build -d      # sobe em background
docker compose ps                 # estado e health dos serviços
docker compose logs -f backend    # logs de um serviço
docker compose down               # para a stack
docker compose down -v            # para e apaga os volumes (banco zerado)
```

## Smoke test

1. `docker compose ps` mostra os quatro serviços como `healthy`.
2. http://localhost:5173 abre a tela de login.
3. http://localhost:8080/actuator/health responde `{"status":"UP"}`.
4. http://localhost:8000/health responde com status `ok`.
