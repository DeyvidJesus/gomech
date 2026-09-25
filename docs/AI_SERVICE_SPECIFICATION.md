# Especificação técnica do serviço de IA do GoMech

Este documento define a especificação de arquitetura, contratos de serviço, governança, protocolos de segurança e catálogo de capacidades do **GoMech AI Service** (FastAPI / Python).

---

## 1. Princípios arquiteturais e isolamento (ADR-019)

1. **Serviço Totalmente Stateless & Zero Database**:
   - O AI Service **não possui** conexão com bancos de dados relacionais (PostgreSQL), ORMs ou repositórios internos de domínio.
   - Qualquer tentativa de importação de módulos de banco de dados (`psycopg`, `psycopg2`, `asyncpg`, `sqlalchemy`, `pg8000`, etc.) é bloqueada estaticamente e em tempo de execução via `verify_zero_database_isolation()`.
2. **Gateway Monolito como Único Cliente Autorizado**:
   - Clientes externos (frontend, mobile, parceiros) não acessam o AI Service diretamente.
   - Toda comunicação parte exclusivamente do Monolito Spring Boot através de cabeçalhos de autenticação interna (`X-GoMech-Service-Auth` ou `Authorization: Bearer <secret>`) e de contexto de tenancy (`X-Tenant-Id`, `X-User-Id`, `X-Correlation-Id`).
3. **Proposições Estruturadas em vez de Ações Autônomas**:
   - O serviço retorna dados e propostas estruturadas (`QuoteProposalResponse`, `DiagnosticResponse`, `PartsRecommendationResponse`), mantendo o ser humano no ciclo (Human-in-the-Loop) para qualquer mutação de negócio.
4. **Abstrações de Provedores Intercambiáveis**:
   - Todos os endpoints comunicam-se via interface abstrata `AiProvider`, permitindo alternância transparente entre provedor `mock` (para desenvolvimento e testes determinísticos) e provedores de nuvem (`openai`, `gemini`).

---

## 2. Autenticação e Headers Obrigatórios

| Header | Tipo | Obrigatório | Descrição |
| :--- | :--- | :--- | :--- |
| `X-GoMech-Service-Auth` | `String` | **Sim** | Segredo compartilhado entre o Monolito e o AI Service (`SERVICE_AUTH_SECRET`). |
| `X-Tenant-Id` | `UUID` | **Sim** | Identificador UUID do tenant da oficina solicitante. |
| `X-User-Id` | `UUID` | Não | Identificador do usuário que disparou a requisição. |
| `X-Unit-Id` | `UUID` | Não | Unidade física da oficina associada. |
| `X-Correlation-Id` | `String` | Não | ID de correlação para rastreamento distribuído ponta a ponta. |

---

## 3. Catálogo de Endpoints e Capacidades

### 3.1. Chat Assistente Automotivo
- **Endpoint**: `POST /api/v1/ai/chat`
- **Descrição**: Assistente conversacional para suporte a dúvidas mecânicas e navegação com citações de grounding técnico.
- **Request Body**:
  ```json
  {
    "messages": [
      {"role": "user", "content": "Qual o procedimento para sangria do freio ABS?"}
    ],
    "context_vehicle": "VW Gol 1.0 2021",
    "max_tokens": 500,
    "temperature": 0.7
  }
  ```

---

### 3.2. Diagnóstico Assistido de Sintomas & Códigos DTC
- **Endpoint**: `POST /api/v1/ai/diagnose`
- **Descrição**: Interpreta sintomas mecânicos e códigos de falha OBD-II (DTCs), propondo causas prováveis, checklist de inspeção e ações prévias.
- **Request Body**:
  ```json
  {
    "vehicle_make": "Volkswagen",
    "vehicle_model": "Golf 1.4 TSI",
    "vehicle_year": 2018,
    "odometer_km": 72000,
    "symptoms_description": "Motor falhando em subidas com luz de injeção piscando",
    "fault_codes": ["P0300", "P0302"]
  }
  ```

---

### 3.3. Recomendações de Peças & Manutenção Preventiva (Com Grounding e Confiança)
- **Endpoints**:
  - `POST /api/v1/ai/recommendations/parts`
  - `POST /api/v1/ai/recommendations/maintenance`
- **Descrição**: Analisa o histórico de intervenções do veículo e quilometragem atual para recomendar peças de desgaste crítico com pontuação de confiança (`confidence_score`) e referências do manual do fabricante (`citations`).
- **Request Body (Parts)**:
  ```json
  {
    "vehicle_make": "Toyota",
    "vehicle_model": "Corolla",
    "vehicle_year": 2020,
    "current_odometer_km": 62000,
    "reported_symptoms": "Revisão periódica recomendada",
    "vehicle_history": [
      {
        "date": "2025-08-10",
        "description": "Troca de óleo e filtro aos 50.000 km",
        "mileage_km": 50000,
        "parts_replaced": ["Filtro de Óleo", "Óleo 5W30"]
      }
    ]
  }
  ```

---

### 3.4. Assistência ao Mecânico (Torques e Procedimentos Passo a Passo)
- **Endpoint**: `POST /api/v1/ai/mechanic-assist`
- **Descrição**: Fornece sequências e especificações exatas de torque (Nm, aperto angular), ferramentas especiais e precauções de segurança.
- **Request Body**:
  ```json
  {
    "vehicle_make": "Chevrolet",
    "vehicle_model": "Onix 1.0 Turbo",
    "vehicle_year": 2022,
    "target_component": "Cabeçote do Motor",
    "question_or_procedure": "Qual a sequência e torque de aperto dos parafusos do cabeçote?"
  }
  ```

---

### 3.5. Busca de Vídeos Técnicos e Procedimentos
- **Endpoint**: `POST /api/v1/ai/video-search`
- **Descrição**: Retorna vídeos técnicos e tutoriais procedimentais relevantes para o veículo e serviço alvo.

---

### 3.6. Extração Estruturada de Documentos e Notas Fiscais
- **Endpoint**: `POST /api/v1/ai/extract`
- **Descrição**: Realiza parsing estruturado de textos de NF-e, orçamentos em PDF ou laudos, extraindo itens, quantidades e valores unitários.

---

### 3.7. Rascunhos de Comunicação com o Cliente
- **Endpoint**: `POST /api/v1/ai/draft-message`
- **Descrição**: Elabora mensagens cordiais e contextuais para WhatsApp/SMS sobre orçamentos prontos ou veículos liberados.

---

### 3.8. Geração de Proposta de Orçamento
- **Endpoint**: `POST /api/v1/ai/generate-quote-items`
- **Descrição**: Gera itens preliminares de peças e mão de obra a partir do diagnóstico técnico.

---

### 3.9. Sumarização de Ordens de Serviço
- **Endpoint**: `POST /api/v1/ai/summarize-work-order`
- **Descrição**: Elabora laudo técnico formal e resumo executivo em linguagem clara para o proprietário do veículo.

---

### 3.10. Insights e Análise Narrativa de KPIs
- **Endpoint**: `POST /api/v1/ai/analytics/insights`
- **Descrição**: Converte métricas brutas de desempenho da oficina em destaques, gargalos operacionais e recomendações acionáveis.

---

## 4. Guardrails de Segurança Automotiva & Redação de PII

| Guardrail / Regra | Código | Ação |
| :--- | :--- | :--- |
| **Bypass de Segurança Veicular** | `UNSAFE_SAFETY_SYSTEM_BYPASS` | Bloqueio com HTTP 422 caso haja instrução para desativar Airbag, ABS ou sensores vitais. |
| **Condução com Falha Crítica de Freio** | `UNSAFE_BRAKE_OPERATION` | Bloqueio com HTTP 422 caso seja sugerido conduzir veículo com vazamento ou ausência de freios. |
| **Reparo Estrutural Proibido** | `UNSAFE_STRUCTURAL_REPAIR` | Bloqueio com HTTP 422 caso haja instrução de solda em rodas de liga leve ou discos de freio. |
| **Redação Automática de PII** | `PII_SANITIZER` | Sanitização por regex de CPF, CNPJ, e-mails, telefones e tokens antes de envio aos modelos. |

---

## 5. Observabilidade & Métricas Prometheus

O endpoint `GET /metrics` expõe:
- `ai_requests_total{capability, provider, status}`: Contador de requisições.
- `ai_request_latency_seconds{capability, provider}`: Histograma de latência.
- `ai_tokens_total{capability, type}`: Consumo de tokens de prompt e completion.
- `ai_guardrail_violations_total{capability, rule}`: Violações de segurança interceptadas.
