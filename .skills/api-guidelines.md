# API Guidelines

Toda API deve:

- Utilizar REST
- Versionamento /api/v1
- DTOs para entrada e saída

Nunca expor entidades diretamente.

---

Respostas:

200 OK
201 Created
400 Bad Request
401 Unauthorized
403 Forbidden
404 Not Found
500 Internal Server Error

---

Paginação obrigatória em listagens.