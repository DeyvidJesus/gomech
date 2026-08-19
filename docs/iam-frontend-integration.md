# IAM (Identity & Access Management) - Frontend API Integration Contract

> **Document Version:** 1.0.0  
> **Target Audience:** Frontend Engineers & AI Agents (Google AI Studio / Codex)  
> **Backend Base URL:** `http://localhost:8080/api/v1` (configurable via `VITE_API_URL`)  
> **Architecture Reference:** ADR-001 (Multi-tenancy), ADR-003 (RBAC/PBAC), ADR-004 (REST Conventions), ADR-005 (Token Rotation)

---

## 1. Feature Context

### Feature Name
**IAM (Identity & Access Management, Authentication, Google OAuth 2.0/OIDC & Multi-Unit RBAC)**

### Feature Description
Provides first-party authentication (email/password), Google OAuth 2.0 / OIDC sign-in, session lifecycle management with rotating refresh tokens, multi-tenancy onboarding, branch/unit management, and role-based / permission-based access control (RBAC/PBAC).

### Backend Scope
- `com.gomech.api.modules.iam` (Auth, Users, Units, Roles, Permissions, Sessions, Google OAuth).
- `com.gomech.api.core.security` (JWT filter, TokenProvider, PasswordEncoder).

### Frontend Scope
- Login screen (email/password & Google button).
- Workshop onboarding / registration wizard.
- Google OAuth callback handler route (`/oauth/callback` or `/login`).
- Session management (active devices list & revocation).
- Unit/branch switcher in topbar.
- User management and role/permission assignment dashboard.
- Axios HTTP client with automated JWT injection and Refresh Token rotation interceptor.

---

## 2. Primary Objective

This document acts as the **single source of truth** for integrating any frontend client with the GoMech IAM backend. All endpoints, schemas, headers, status codes, and error formats documented herein reflect the actual, tested backend implementation.

---

## 3. Authentication & Token Architecture

### 3.1 Token Lifecycle & Structure
1. **Access Token (JWT)**:
   - **Lifespan**: 15 minutes (`900` seconds).
   - **Header**: `Authorization: Bearer <accessToken>`.
   - **Claims**: `sub` (User ID), `tenant_id` (UUID), `unit_id` (UUID), `roles` (array of strings), `permissions` (array of strings), `iat`, `exp`, `jti`.
   - **Security**: Never store in insecure storage. Persisted in frontend state (Zustand / memory).
2. **Refresh Token (Opaque UUID)**:
   - **Lifespan**: 30 days.
   - **Rotation**: Every call to `POST /api/v1/auth/refresh` issues a **new** Access Token and a **new** Refresh Token, invalidating the previous one.
   - **Reuse Detection (Anti-theft Protection)**: If a previously rotated refresh token is presented again, the backend automatically revokes the entire token family (`family_id`) and invalidates all user sessions.
3. **Active Unit Context & Unit Switching**:
   - The user belongs to a `Tenant` (Company) and can hold distinct roles across physical `Units` (Branches/Workshops).
   - Calling `POST /api/v1/auth/switch-unit` generates a new Access Token and Refresh Token scoped to the target unit **without requiring re-authentication**.

---

## 4. API Endpoints Contract

### 4.1 Authentication & Session Management (`/api/v1/auth`)

---

#### `POST /api/v1/auth/login`
**Purpose**: Authenticate an existing user with email and password.

- **Authentication**: None (Public)
- **Headers**: `Content-Type: application/json`
- **Request Body**:
```json
{
  "email": "carlos@turbopower.com.br",
  "password": "Password@123"
}
```
- **Response `200 OK`**:
```json
{
  "accessToken": "eyJhbGciOiJIUzM4NCJ9...",
  "refreshToken": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
  "tokenType": "Bearer",
  "expiresIn": 900,
  "user": {
    "id": "a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d",
    "name": "Carlos Alberto",
    "email": "carlos@turbopower.com.br",
    "tenantId": "e3b0c442-98fc-1c14-9afb-f4c599684501",
    "activeUnitId": "f4c59968-4501-4429-8fc1-c149afbf4c59",
    "roles": ["Proprietário"],
    "permissions": [
      "IAM_USER_READ", "IAM_USER_WRITE", "IAM_ROLE_READ", "IAM_ROLE_WRITE",
      "IAM_UNIT_READ", "IAM_UNIT_WRITE", "CRM_CUSTOMER_READ", "CRM_CUSTOMER_WRITE",
      "CRM_VEHICLE_READ", "CRM_VEHICLE_WRITE", "OPERATIONS_ORDER_READ",
      "OPERATIONS_ORDER_WRITE", "OPERATIONS_APPOINTMENT_READ", "OPERATIONS_APPOINTMENT_WRITE"
    ]
  }
}
```
- **Error Responses**:
  - `400 Bad Request` / `401 Unauthorized`: Invalid credentials or inactive user account.
  - `422 Unprocessable Entity`: Validation failure on `email` or `password`.

---

#### `POST /api/v1/auth/register`
**Purpose**: Initial registration and onboarding of a new auto repair workshop (Tenant, Headquarters Unit, Owner User, Default Roles & Trial Subscription).

- **Authentication**: None (Public)
- **Headers**: `Content-Type: application/json`
- **Request Body**:
```json
{
  "workshopName": "Oficina Turbo Power",
  "address": "Av. das Américas, 1000 - Barra da Tijuca, Rio de Janeiro - RJ",
  "bays": 4,
  "services": ["Mecânica Geral", "Injeção Eletrônica", "Freios e Suspensão"],
  "ownerName": "Carlos Alberto",
  "email": "carlos@turbopower.com.br",
  "password": "Password@123"
}
```
- **Response `201 Created`**:
```json
{
  "accessToken": "eyJhbGciOiJIUzM4NCJ9...",
  "refreshToken": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
  "tokenType": "Bearer",
  "expiresIn": 900,
  "user": {
    "id": "a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d",
    "name": "Carlos Alberto",
    "email": "carlos@turbopower.com.br",
    "tenantId": "e3b0c442-98fc-1c14-9afb-f4c599684501",
    "activeUnitId": "f4c59968-4501-4429-8fc1-c149afbf4c59",
    "roles": ["Proprietário"],
    "permissions": ["..."]
  }
}
```
- **Error Responses**:
  - `400 Bad Request` / `409 Conflict`: Email already in use (`"E-mail já cadastrado no sistema"`).
  - `422 Unprocessable Entity`: Validation failure on required fields.

---

#### `POST /api/v1/auth/refresh`
**Purpose**: Refresh an expired access token using the rotating refresh token.

- **Authentication**: None (Uses Refresh Token in body)
- **Headers**: `Content-Type: application/json`, `User-Agent`, `X-Device-Info` (optional)
- **Request Body**:
```json
{
  "refreshToken": "7c9e6679-7425-40de-944b-e07fc1f90ae7"
}
```
- **Response `200 OK`**:
```json
{
  "accessToken": "eyJhbGciOiJIUzM4NCJ9...",
  "refreshToken": "9d8e7766-5544-3322-1100-aabbccddeeff",
  "tokenType": "Bearer",
  "expiresIn": 900,
  "user": { ... }
}
```
- **Error Responses**:
  - `401 Unauthorized`: Token was revoked, expired or reused (triggers anti-theft family invalidation). Frontend must immediately purge local credentials and redirect to `/login`.

---

#### `POST /api/v1/auth/switch-unit`
**Purpose**: Switch the active physical unit context without requiring re-authentication.

- **Authentication**: Bearer Token required (`Authorization: Bearer <accessToken>`)
- **Headers**: `Content-Type: application/json`, `Authorization: Bearer <token>`
- **Request Body**:
```json
{
  "unitId": "f4c59968-4501-4429-8fc1-c149afbf4c59"
}
```
- **Response `200 OK`**:
```json
{
  "accessToken": "eyJhbGciOiJIUzM4NCJ9...",
  "refreshToken": "new-refresh-token-uuid",
  "tokenType": "Bearer",
  "expiresIn": 900,
  "user": {
    "id": "a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d",
    "name": "Carlos Alberto",
    "email": "carlos@turbopower.com.br",
    "tenantId": "e3b0c442-98fc-1c14-9afb-f4c599684501",
    "activeUnitId": "f4c59968-4501-4429-8fc1-c149afbf4c59",
    "roles": ["Gerente"],
    "permissions": ["..."]
  }
}
```
- **Error Responses**:
  - `400 Bad Request`: Unit does not exist or user does not belong to the tenant.
  - `401 Unauthorized`: Unauthenticated.

---

#### `POST /api/v1/auth/logout`
**Purpose**: Terminate current session and invalidate refresh token.

- **Authentication**: Optional / Public
- **Headers**: `Content-Type: application/json`
- **Request Body** (Optional):
```json
{
  "refreshToken": "7c9e6679-7425-40de-944b-e07fc1f90ae7"
}
```
- **Response `204 No Content`**

---

#### `POST /api/v1/auth/revoke-all`
**Purpose**: Revoke all active sessions and refresh tokens across all devices for the current user.

- **Authentication**: Bearer Token required
- **Headers**: `Authorization: Bearer <accessToken>`
- **Response `204 No Content`**

---

#### `GET /api/v1/auth/sessions`
**Purpose**: List all active sessions and devices for the logged-in user.

- **Authentication**: Bearer Token required
- **Query Params**: `currentRefreshToken` (optional, string) to mark `isCurrent: true`.
- **Response `200 OK`**:
```json
[
  {
    "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "familyId": "8c824353-91d6-4788-9c43-b0e206ca8fc9",
    "createdAt": "2026-08-19T10:00:00Z",
    "lastUsedAt": "2026-08-19T14:30:00Z",
    "expiresAt": "2026-09-18T10:00:00Z",
    "ipAddress": "189.120.45.12",
    "userAgent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36...",
    "deviceInfo": "Chrome 125 on Linux",
    "isCurrent": true
  }
]
```

---

#### `DELETE /api/v1/auth/sessions/{sessionId}`
**Purpose**: Terminate a specific remote session.

- **Authentication**: Bearer Token required
- **Response `204 No Content`**

---

### 4.2 Google OAuth 2.0 / OIDC (`/api/v1/auth/oauth/google`)

---

#### `GET /api/v1/auth/oauth/google/authorize`
**Purpose**: Generate Google OAuth consent URL with cryptographic state, nonce, and PKCE challenge.

- **Authentication**: None
- **Query Params**: `redirectUri` (optional, string)
- **Response `200 OK`**:
```json
{
  "authorizationUrl": "https://accounts.google.com/o/oauth2/v2/auth?client_id=...&redirect_uri=...&response_type=code&scope=openid%20email%20profile&state=eyJhbGciOiJIUzI1NiJ9...&code_challenge=...&code_challenge_method=S256",
  "state": "eyJhbGciOiJIUzI1NiJ9..."
}
```

#### `POST /api/v1/auth/oauth/google/callback`
**Purpose**: Exchange Google authorization code and validate state/nonce/PKCE, linking with existing account or provisioning a new workshop tenant.

- **Authentication**: None
- **Request Body**:
```json
{
  "code": "4/0AeanS0b...",
  "state": "eyJhbGciOiJIUzI1NiJ9..."
}
```
- **Response `200 OK`**: Returns standard `AuthResponse` with GoMech tokens.

---

### 4.3 Users & Roles Management (`/api/v1/users`, `/api/v1/roles`, `/api/v1/units`)

---

#### `GET /api/v1/users`
- **Auth**: `hasAuthority('IAM_USER_READ') or hasRole('Proprietário')`
- **Response `200 OK`**:
```json
[
  {
    "id": "a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d",
    "name": "Carlos Mecânico",
    "email": "carlos.mec@turbopower.com.br",
    "status": "ACTIVE",
    "tenantId": "e3b0c442-98fc-1c14-9afb-f4c599684501",
    "roles": [
      {
        "roleId": "d1e2f3a4-b5c6-7a8b-9c0d-1e2f3a4b5c6d",
        "roleName": "Mecânico",
        "unitId": "f4c59968-4501-4429-8fc1-c149afbf4c59",
        "unitName": "Matriz Centro"
      }
    ]
  }
]
```

#### `POST /api/v1/users`
- **Auth**: `hasAuthority('IAM_USER_WRITE') or hasRole('Proprietário')`
- **Request Body**:
```json
{
  "name": "Roberto Silva",
  "email": "roberto@turbopower.com.br",
  "password": "Password@123",
  "roles": [
    {
      "roleId": "d1e2f3a4-b5c6-7a8b-9c0d-1e2f3a4b5c6d",
      "unitId": "f4c59968-4501-4429-8fc1-c149afbf4c59"
    }
  ]
}
```
- **Response `201 Created`**: Returns `UserResponse`.

#### `POST /api/v1/users/{id}/roles`
- **Auth**: `hasAuthority('IAM_USER_WRITE') or hasRole('Proprietário')`
- **Request Body**:
```json
{
  "roleId": "d1e2f3a4-b5c6-7a8b-9c0d-1e2f3a4b5c6d",
  "unitId": "f4c59968-4501-4429-8fc1-c149afbf4c59"
}
```
- **Response `200 OK`**: Returns updated `UserResponse`.

#### `GET /api/v1/units`
- **Auth**: `hasAuthority('IAM_UNIT_READ') or hasRole('Proprietário')`
- **Response `200 OK`**:
```json
[
  {
    "id": "f4c59968-4501-4429-8fc1-c149afbf4c59",
    "name": "Matriz Centro",
    "address": "Av. Principal, 1000",
    "isHeadquarters": true,
    "tenantId": "e3b0c442-98fc-1c14-9afb-f4c599684501"
  }
]
```

#### `POST /api/v1/units`
- **Auth**: `hasAuthority('IAM_UNIT_WRITE') or hasRole('Proprietário')`
- **Request Body**:
```json
{
  "name": "Filial Zona Sul",
  "address": "Rua das Flores, 200",
  "isHeadquarters": false
}
```
- **Response `201 Created`**: Returns `UnitResponse`.

#### `GET /api/v1/roles` & `GET /api/v1/roles/permissions`
- **Auth**: `hasAuthority('IAM_ROLE_READ') or hasRole('Proprietário')`
- **Response `200 OK`**: Lists roles with permissions or all available catalog permissions (`code`, `module`).

#### `POST /api/v1/roles`
- **Auth**: `hasAuthority('IAM_ROLE_WRITE') or hasRole('Proprietário')`
- **Request Body**:
```json
{
  "name": "Inspetor de Qualidade",
  "description": "Responsável por inspeções e testes de rodagem",
  "permissionCodes": [
    "OPERATIONS_ORDER_READ",
    "OPERATIONS_ORDER_EXECUTE",
    "CRM_VEHICLE_READ"
  ]
}
```
- **Response `201 Created`**: Returns `RoleResponse`.

---

## 5. Data Models & Schemas

| Field | Type | Required | Nullable | Description | Frontend Considerations |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `accessToken` | `string` | Yes | No | JWT Bearer token (15m) | Store in memory/Zustand state; send in `Authorization` header. |
| `refreshToken` | `string` (UUID) | Yes | No | Opaque rotating token (30d) | Store in `localStorage` for session restoration & refresh. |
| `tokenType` | `string` | No | No | `"Bearer"` | Default prefix for authorization header. |
| `expiresIn` | `number` | Yes | No | Seconds until access token expires (`900`) | Schedule silent refresh at ~14 minutes. |
| `user.id` | `string` (UUID) | Yes | No | User identifier | Unique key. |
| `user.tenantId` | `string` (UUID) | Yes | No | Organization identifier | Read-only. |
| `user.activeUnitId` | `string` (UUID) | Yes | No | Currently active branch/unit | Display in Topbar unit selector. |
| `user.roles` | `string[]` | Yes | No | Role names in active unit | E.g. `["Proprietário"]`, `["Gerente"]`. |
| `user.permissions` | `string[]` | Yes | No | Granular PBAC codes | Use for conditional UI rendering (`can('IAM_USER_WRITE')`). |
| `bays` | `number` | Yes | No | Number of service bays | Positive integer (`min: 1`). |
| `services` | `string[]` | No | Yes | Array of service tags | Multi-select chips. |
| `isHeadquarters` | `boolean` | No | No | Is main unit | Badge in unit selector (`Matriz`). |

---

## 6. Error Contract (RFC 7807 Problem Details)

All error responses from the backend strictly adhere to **RFC 7807 Problem Detail**:

```json
{
  "type": "https://gomech.com/docs/errors/validation-failed",
  "title": "Validation Failed",
  "status": 422,
  "detail": "Input validation failed for some parameters.",
  "invalidParams": [
    {
      "name": "email",
      "reason": "must be a well-formed email address"
    },
    {
      "name": "password",
      "reason": "must not be blank"
    }
  ]
}
```

### Error Types Reference
| Status Code | Type URI | Title | Description / Handling |
| :--- | :--- | :--- | :--- |
| `400 Bad Request` | `.../bad-request` | Bad Request | Malformed payload or business constraint violation (e.g. unit not found). |
| `401 Unauthorized` | `.../unauthorized` | Unauthorized | Expired or invalid token. Invalidate local session and redirect to `/login`. |
| `403 Forbidden` | `.../forbidden` | Forbidden | Insufficient permissions for the requested operation. |
| `409 Conflict` | `.../duplicate-resource` | Conflict | Resource conflict (e.g. email or unit name already in use). |
| `422 Unprocessable` | `.../validation-failed` | Validation Failed | Form validation errors. Map `invalidParams` array directly to form inputs. |

---

## 7. Frontend State Requirements

The frontend integration must support the following UI states:

```
[UNAUTHENTICATED] ──(Login / Register)──▶ [AUTHENTICATING (Loading)]
        │                                             │
        │                                  ┌──────────┴──────────┐
        │                                  ▼                     ▼
        │                            [AUTHENTICATED]      [AUTH_ERROR]
        │                                  │                     │
        │                           (Token Expired)        (Show Alert)
        │                                  │
        │                           [REFRESHING]
        │                                  │
        │                        ┌─────────┴─────────┐
        │                        ▼                   ▼
        │                 [REFRESH_SUCCESS]   [SESSION_REVOKED]
        │                        │                   │
        └────────────────────────┼───────────────────┘
                                 ▼
                          [UNAUTHENTICATED]
```

---

## 8. Axios Interceptor Pattern (Recommended Implementation)

```typescript
import axios from 'axios';
import { useAuthStore } from './authStore';

export const api = axios.create({
  baseURL: import.meta.env.VITE_API_URL || 'http://localhost:8080/api/v1',
  headers: { 'Content-Type': 'application/json' },
});

// Request Interceptor: Attach Bearer Token
api.interceptors.request.use((config) => {
  const token = useAuthStore.getState().accessToken;
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

// Response Interceptor: Handle 401 & Rotate Refresh Token
let isRefreshing = false;
let failedQueue: Array<{ resolve: (token: string) => void; reject: (err: unknown) => void }> = [];

api.interceptors.response.use(
  (response) => response,
  async (error) => {
    const originalRequest = error.config;
    if (error.response?.status === 401 && !originalRequest._retry) {
      if (originalRequest.url.includes('/auth/login') || originalRequest.url.includes('/auth/refresh')) {
        useAuthStore.getState().logout();
        return Promise.reject(error);
      }

      if (isRefreshing) {
        return new Promise((resolve, reject) => {
          failedQueue.push({ resolve, reject });
        }).then((token) => {
          originalRequest.headers.Authorization = `Bearer ${token}`;
          return api(originalRequest);
        });
      }

      originalRequest._retry = true;
      isRefreshing = true;

      const refreshToken = useAuthStore.getState().refreshToken;
      if (!refreshToken) {
        useAuthStore.getState().logout();
        return Promise.reject(error);
      }

      try {
        const { data } = await axios.post(`${api.defaults.baseURL}/auth/refresh`, { refreshToken });
        useAuthStore.getState().setAuth(data.accessToken, data.refreshToken, data.user);
        failedQueue.forEach((prom) => prom.resolve(data.accessToken));
        failedQueue = [];
        originalRequest.headers.Authorization = `Bearer ${data.accessToken}`;
        return api(originalRequest);
      } catch (refreshErr) {
        failedQueue.forEach((prom) => prom.reject(refreshErr));
        failedQueue = [];
        useAuthStore.getState().logout();
        return Promise.reject(refreshErr);
      } finally {
        isRefreshing = false;
      }
    }
    return Promise.reject(error);
  }
);
```

---

## 9. Frontend Integration Risks

1. **Token Storage**:
   - *Risk*: Storing access tokens in `localStorage` increases XSS vulnerability.
   - *Recommendation*: Keep `accessToken` in Zustand state (in-memory) and store only `refreshToken` in persistent storage (`localStorage`), refreshing on application boot.
2. **Unit Switch Without Page Reload**:
   - *Risk*: Switching units changes roles and permissions immediately.
   - *Recommendation*: When `switchUnit` succeeds, update Zustand auth store and invalidate all React Query caches (`queryClient.clear()` or `queryClient.invalidateQueries()`).
3. **Anti-Theft Trigger**:
   - *Risk*: If multiple concurrent requests trigger refresh with the same old refresh token, the backend might detect reuse and revoke the session.
   - *Recommendation*: Always use the request queue pattern shown in Section 8 to execute only one refresh request at a time.

---

## 10. Implementation Checklist

- [ ] Verify `VITE_API_URL` environment variable points to backend (`http://localhost:8080/api/v1`).
- [ ] Update `authStore.ts` to store `accessToken`, `refreshToken`, and `user` profile (`id`, `name`, `email`, `tenantId`, `activeUnitId`, `roles`, `permissions`).
- [ ] Implement Axios request and response interceptors with automatic token refresh.
- [ ] Connect `LoginForm.tsx` to `POST /api/v1/auth/login`.
- [ ] Connect `RegisterForm.tsx` to `POST /api/v1/auth/register`.
- [ ] Implement Google Sign-In button redirecting to `GET /api/v1/auth/oauth/google/authorize` and callback route posting to `/api/v1/auth/oauth/google/callback`.
- [ ] Implement Topbar Unit Selector calling `POST /api/v1/auth/switch-unit`.
- [ ] Implement Sessions page with active device list (`GET /api/v1/auth/sessions`) and remote logout (`DELETE /api/v1/auth/sessions/{id}`).
- [ ] Map RFC 7807 `invalidParams` to form fields in `LoginForm` and `RegisterForm`.
