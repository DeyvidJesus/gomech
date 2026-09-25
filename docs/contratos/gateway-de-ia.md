# Gateway de IA: contrato de serviço e política de resiliência

Contrato entre o frontend, o backend (AI Gateway, módulo `com.gomech.api.modules.ai` do monolito Spring Boot) e o AI Service (FastAPI). Ele define os endpoints REST autenticados que o frontend consome, as regras de governança aplicadas antes de qualquer inferência (autorização, cota e sanitização de PII) e a política de resiliência da chamada ao AI Service.

> [!IMPORTANT]
> **Integração implementada.** `FastApiAiServiceClient` chama os endpoints autenticados do serviço Python em `/api/v1/ai`. O gateway converte os DTOs Java para snake_case, encaminha o contexto de tenant/usuário/unidade e converte as respostas para os contratos públicos do backend. O endpoint público de completions usa a rota FastAPI `/chat`.
>
> A autenticação usa `X-GoMech-Service-Auth` e os headers `X-Tenant-Id` (obrigatório), `X-User-Id`, `X-Unit-Id` e `X-Correlation-Id`. Na GCP, o cliente também obtém e envia um ID token do Cloud Run para a audiência do serviço FastAPI; a identidade do backend tem `roles/run.invoker`. Timeouts e tentativas são configuráveis por variáveis de ambiente. No Compose local, os containers compartilham a rede e usam o segredo de desenvolvimento.
>
> **Provedor é uma configuração separada da integração.** O FastAPI continua com `mock` como padrão local. O adaptador Gemini só chama o modelo de forma real em `/chat`; as demais capacidades delegam ao provedor mock no estado atual. A chamada HTTP entre backend e FastAPI não significa que todas as operações já usam um modelo externo.

---

## 1. Princípios de segurança e governança

1. **Ponto único e autenticado de entrada**
   - Nenhuma chamada a modelos ou provedores de IA (OpenAI, Anthropic, Gemini, Vertex) é feita diretamente pelo cliente (frontend ou mobile).
   - O monolito Spring Boot (`com.gomech.api.modules.ai`) é o gateway exclusivo.
2. **Contexto de ator e de tenant**
   - Todo fluxo de IA exige um JWT válido. O gateway resolve `tenantId`, `userId` e `unitId` a partir do token e usa o `correlationId` da requisição (header `X-Correlation-ID`), ou gera um UUID novo quando ele não vem.
3. **Autorização e entitlement avaliados antes, sem bypass**
   - **RBAC**: cada endpoint exige `AI_QUERY` ou `AI_ACTION_EXECUTE` via `@PreAuthorize` no controller. O papel `Proprietário` tem acesso a todos. A permissão `AI_ADMIN` é criada pela migration V19, mas nenhum endpoint a exige hoje.
   - **Cota**: a cota mensal da dimensão `QuotaDimension.AI_USAGE` é verificada **antes** de qualquer chamada de rede externa. Uma assinatura fora de operação também bloqueia a chamada. O recurso `MODULE_AI` consta dos planos (migration V7), mas o gateway ainda não o verifica por requisição: o bloqueio vem apenas da cota.
   - Cota esgotada retorna HTTP `402 Payment Required` imediatamente.
   - Cada chamada bem-sucedida debita 1 unidade de `AI_USAGE`.
4. **Sanitização de dados sensíveis (PII) antes do envio**
   - O componente de domínio `SensitiveDataSanitizer` aplica expressões regulares para CPF, CNPJ, cartões de crédito, e-mails, telefones e tokens de autorização (Bearer, chaves `sk-`/`ak-`, `ghp_`), trocando cada ocorrência por um marcador como `[CPF_REDACTED]`. Isso acontece antes de o prompt seguir para o modelo e antes de o resumo ser gravado no log de auditoria (`ai_gateway_audit_logs`).

---

## 2. Contratos REST do AI Gateway

Todos os endpoints exigem `Authorization: Bearer <accessToken>`. Erros de validação dos campos marcados como obrigatórios retornam `422` (ver seção 3).

### 2.1. Diagnóstico assistido de anomalias veiculares
- **Endpoint**: `POST /api/v1/ai/diagnose`
- **Permissão**: `AI_QUERY` ou `Proprietário`
- **Validação**: `symptomsDescription` é obrigatório (até 2000 caracteres).
- **Request body**:
  ```json
  {
    "vehicleId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "vehicleMake": "Volkswagen",
    "vehicleModel": "Gol 1.0",
    "vehicleYear": 2021,
    "odometerKm": 65000,
    "symptomsDescription": "Motor falhando em retomadas de marcha e luz de injeção piscando",
    "faultCodes": ["P0300", "P0301"],
    "customerNotes": "Problema começou após abastecer em posto na rodovia"
  }
  ```
- **Response body**:
  ```json
  {
    "diagnosisSummary": "Identificado padrão de falha de ignição/injeção intermitente no ciclo de combustão.",
    "probableCauses": [
      "Desgaste excessivo nas velas de ignição",
      "Fuga de corrente nos cabos de vela ou bobinas de ignição",
      "Bicos injetores carbonizados ou com vazão irregular"
    ],
    "recommendedInspectionSteps": [
      "1. Efetuar teste de centelhamento e resistência ohmica das bobinas de ignição.",
      "2. Inspecionar estado dos eletrodos e folga das velas de ignição.",
      "3. Medir pressão e vazão da linha de combustível em manômetro."
    ],
    "confidenceScore": 0.92,
    "proposedAction": "PROPOSE_QUOTE_ITEMS",
    "proposedChecklist": ["Jogo de Velas", "Cabos de Ignição", "Limpeza de Bicos"],
    "usage": {
      "modelUsed": "gomech-reasoning-pro",
      "promptTokens": 180,
      "completionTokens": 220,
      "totalTokens": 400,
      "latencyMs": 120
    }
  }
  ```
  `proposedAction` é um valor de `AiActionType` (ver [confirmação de ações da IA](../AI_ACTION_CONFIRMATION_FLOW.md)).

---

### 2.2. Proposta estruturada de itens de orçamento
- **Endpoint**: `POST /api/v1/ai/generate-quote-items`
- **Permissão**: `AI_ACTION_EXECUTE` ou `Proprietário`
- **Validação**: `diagnosticSummary` é obrigatório.
- **Request body**:
  ```json
  {
    "workOrderId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "vehicleInfo": "Volkswagen Gol 1.0 2021",
    "diagnosticSummary": "Desgaste de velas e bicos injetores carbonizados",
    "customerBudgetLimit": 800.00
  }
  ```
- **Response body**:
  ```json
  {
    "summary": "Proposta gerada automaticamente com base no diagnóstico técnico de ignição e injeção.",
    "proposedItems": [
      {
        "type": "SERVICE",
        "description": "Mão de Obra: Diagnóstico Computadorizado e Revisão de Ignição/Injeção",
        "partNumber": "MO-DIAG-01",
        "quantity": 1,
        "estimatedPrice": 180.00,
        "rationale": "Tempo estimado de bancada e calibração: 1.5 horas"
      },
      {
        "type": "PART",
        "description": "Jogo de Velas de Ignição Iridium",
        "partNumber": "NGK-BKR6EIX",
        "quantity": 4,
        "estimatedPrice": 240.00,
        "rationale": "Substituição preventiva recomendada pelo diagnóstico"
      }
    ],
    "estimatedTotalLabor": 180.00,
    "estimatedTotalParts": 240.00,
    "totalEstimate": 420.00,
    "usage": {
      "modelUsed": "gomech-reasoning-pro",
      "promptTokens": 210,
      "completionTokens": 260,
      "totalTokens": 470,
      "latencyMs": 140
    }
  }
  ```

---

### 2.3. Resumo de ordem de serviço
- **Endpoint**: `POST /api/v1/ai/summarize-work-order`
- **Permissão**: `AI_QUERY` ou `Proprietário`
- **Request body**:
  ```json
  {
    "workOrderId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "orderNumber": "OS-2026-0042",
    "vehicleSummary": "Toyota Corolla 2.0 2022",
    "customerReportedIssues": "Ruído na frenagem e pedal baixo",
    "servicesPerformed": ["Troca de pastilhas e discos dianteiros", "Sangria e troca do fluido DOT 4"],
    "partsReplaced": ["Pastilhas Bosch", "Discos Fremax", "Fluido Varga DOT4"],
    "mechanicNotes": "Discos antigos estavam com 18.2mm, abaixo da tolerância de 19.0mm"
  }
  ```
- **Response body**:
  ```json
  {
    "technicalSummary": "OS #OS-2026-0042: Substituído conjunto de frenagem dianteiro (discos e pastilhas) devido a desgaste abaixo da espessura mínima de segurança. Fluido de freio renovado e circuito sangrado.",
    "executiveCustomerSummary": "Olá! O sistema de freios do seu veículo foi totalmente revisado e renovado com peças novas e calibradas. O pedal agora possui resposta imediata e segurança total.",
    "preventiveRecommendations": [
      "Evitar frenagens bruscas nos primeiros 200 km para assentamento das pastilhas.",
      "Próxima checagem do sistema de freios em 10.000 km."
    ],
    "warrantyTerms": "Garantia legal de 90 dias sobre peças aplicadas e serviços executados.",
    "usage": {
      "modelUsed": "gomech-turbo-fast",
      "promptTokens": 140,
      "completionTokens": 160,
      "totalTokens": 300,
      "latencyMs": 95
    }
  }
  ```

---

### 2.4. Rascunho de mensagens ao cliente
- **Endpoint**: `POST /api/v1/ai/draft-message`
- **Permissão**: `AI_ACTION_EXECUTE` ou `Proprietário`
- **Validação**: `topic` é obrigatório. Valores esperados: `QUOTE_READY`, `SERVICE_COMPLETED`, `ADDITIONAL_APPROVAL_NEEDED`, `INVOICE_READY`. Para `tone`: `CORDIAL`, `TECHNICAL`, `FORMAL`.
- **Request body**:
  ```json
  {
    "customerId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "customerName": "Mariana Santos",
    "vehiclePlate": "BRA2E19",
    "topic": "QUOTE_READY",
    "keyDetails": "Orçamento de R$ 650,00 aprovando troca de correia dentada e tensor",
    "tone": "CORDIAL"
  }
  ```
- **Response body** (`channel`: `WHATSAPP`, `EMAIL` ou `SMS`):
  ```json
  {
    "channel": "WHATSAPP",
    "subject": "GoMech: Atualização do seu veículo (BRA2E19)",
    "bodyMessage": "Olá, Mariana Santos! O orçamento detalhado para a manutenção do seu veículo já está pronto para sua análise e aprovação. Acesse o link seguro do portal ou responda esta mensagem para tirar dúvidas.",
    "usage": {
      "modelUsed": "gomech-turbo-fast",
      "promptTokens": 90,
      "completionTokens": 110,
      "totalTokens": 200,
      "latencyMs": 70
    }
  }
  ```

---

### 2.5. Processamento genérico (completions)
- **Endpoint público**: `POST /api/v1/ai/completions` (o backend chama `POST /api/v1/ai/chat` no FastAPI).
- **Permissão**: `AI_QUERY` ou `Proprietário`
- **Request body**: `prompt` (obrigatório, até 4000 caracteres), `model` (opcional: `FAST_TURBO`, `REASONING_PRO` ou `VISION_MULTIMODAL`), `maxTokens` e `temperature` (opcionais).
- **Response body**: `completionText`, `finishReason` e `usage` (mesmo formato das seções anteriores).

---

### 2.6. Status e saldo da cota de IA
- **Endpoint**: `GET /api/v1/ai/usage`
- **Permissão**: `AI_QUERY` ou `Proprietário`
- **Response body**:
  ```json
  {
    "tenantId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "planCode": "PRO",
    "quotaLimit": 5000,
    "quotaUsed": 120,
    "quotaRemaining": 4880,
    "isAllowed": true,
    "resetDate": "2026-09-05T00:00:00Z"
  }
  ```
- **Limitação atual**: só `tenantId` e `isAllowed` refletem o Core Entitlement. `planCode`, `quotaLimit`, `quotaUsed`, `quotaRemaining` e `resetDate` são valores fixos em `AiGatewayService.getUsageStatus` (`resetDate` = agora + 10 dias).

---

## 3. Política de resiliência e tolerância a falhas

Os erros seguem RFC 7807 (Problem Details) e trazem `errorCode` e `timestamp` como campos extras. O cliente FastAPI não repete respostas 4xx nem rate limits; falhas de rede e respostas 5xx usam backoff exponencial com jitter.

| Cenário de falha | Comportamento do gateway | Código de retorno |
| :--- | :--- | :--- |
| **Cota mensal esgotada** | Bloqueio imediato antes da invocação, sem chamada externa. Grava log de auditoria com status `REJECTED_QUOTA_EXCEEDED` e `errorCode` `AI_QUOTA_EXCEEDED`. | `402 Payment Required` |
| **Acesso não autorizado** | `@PreAuthorize` do Spring Security barra a chamada antes de o método do controller executar. | `403 Forbidden` |
| **Rate limit do provedor (429)** | Sem retentativa: `AiRateLimitException` é repassada na hora, com o header `Retry-After` e o campo `retryAfterSeconds`. | `429 Too Many Requests` |
| **Indisponibilidade / timeout de rede** | Retentativas automáticas com backoff exponencial e jitter: `backoffBaseMs * 2^(tentativa-1)` + 10 a 50 ms, até `maxRetries` tentativas no total (padrão: 3 tentativas, base de 150 ms). Esgotadas as tentativas, lança `AiServiceUnavailableException`. | `503 Service Unavailable` |
| **Erro de sintaxe / validação** | Jakarta Bean Validation (`@Valid`) devolve Problem Details com a lista `invalidParams`. | `422 Unprocessable Entity` |
| **Outro erro do gateway** (`AiException`) | Problem Details do tipo `ai-gateway-error`. | `400 Bad Request` |

---

## 4. Observabilidade e métricas (Micrometer)

O AI Gateway publica métricas padronizadas para monitoramento:
- `ai.gateway.requests.total`: contador de requisições por `capability`, `status` e `model` (sucesso) ou por `capability`, `status` e `error_code` (falha).
- `ai.gateway.latency`: timer do tempo de resposta da inferência por `capability` e `model`, registrado nas chamadas bem-sucedidas.
- `ai.gateway.tokens.total`: contador de tokens consumidos por `capability` e `type` (`prompt`, `completion`).
- `ai.gateway.errors.total`: contador de falhas por `capability` e `error_code`.

---

## 5. Referências

- [ADR-018: Gateway de IA](../adr/ADR-018-gateway-de-ia.md)
- [ADR-019: Isolamento do serviço de IA](../adr/ADR-019-isolamento-do-servico-de-ia.md)
- [ADR-007: Contrato de entitlement e billing](../adr/ADR-007-contrato-de-entitlement-e-billing.md)
- [ADR-006: RBAC e permissões](../adr/ADR-006-rbac-e-permissoes.md)
- [Confirmação de ações da IA](../AI_ACTION_CONFIRMATION_FLOW.md)
- [Especificação do AI Service](../AI_SERVICE_SPECIFICATION.md)
