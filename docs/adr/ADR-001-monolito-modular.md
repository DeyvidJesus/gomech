# ADR-001: Monolito modular

- **Status:** Aceita
- **Data:** 2026-08-17
- **Relacionadas:** [ADR-002 — Camadas e regras de dependência](ADR-002-camadas-e-regras-de-dependencia.md)

## Contexto

O backend da V2 é implementado como uma única aplicação Spring Boot.

O sistema vai reunir várias capacidades de negócio, e cada uma delas exige responsabilidade e fronteiras claras. No entanto, o escopo arquitetural atual não justifica implantar cada capacidade de negócio como um microsserviço independente.

Por isso, a arquitetura precisa estabelecer fronteiras internas claras entre módulos, mantendo uma única aplicação de backend implantável.

A principal restrição arquitetural é:

> Módulos de negócio não são microsserviços.

A estrutura modular busca melhorar a separação de responsabilidades, a manutenibilidade, a definição de responsáveis (ownership), os testes e a evolução futura, sem introduzir prematuramente a complexidade operacional de um sistema distribuído.

## Decisão

O backend da V2 seguirá uma arquitetura de **monolito modular**.

O backend continua sendo uma única aplicação Spring Boot, implantada como uma única unidade de deploy. Internamente, a aplicação é dividida em módulos orientados ao negócio, com fronteiras e responsabilidades explícitas.

Cada módulo de negócio é responsável por:

- Lógica de domínio
- Lógica de aplicação/casos de uso
- Acesso a dados específico do módulo
- Questões de infraestrutura específicas do módulo
- Contratos internos públicos

Um módulo não deve depender diretamente de detalhes internos de implementação de outros módulos.

A comunicação entre módulos deve ocorrer por meio de contratos explícitos, interfaces, serviços de aplicação ou outras APIs de módulo aprovadas.

Módulos de negócio não devem ser tratados como serviços implantáveis de forma independente.

## Ownership dos módulos

Cada módulo deve ter um responsável e uma responsabilidade claramente definidos.

A documentação de arquitetura deve manter um mapa de ownership dos módulos contendo, no mínimo:

| Módulo | Responsabilidade | Responsável | API pública | Dependências |
|---|---|---|---|---|
| `<módulo>` | `<responsabilidade de negócio>` | `<responsável>` | `<contrato>` | `<módulos>` |

Ownership significa responsabilidade por manter as regras de negócio do módulo, sua implementação interna, seus testes e suas fronteiras arquiteturais.

Um módulo só pode depender de outro por meio de um contrato definido explicitamente.

## Implicações de deploy

Todos os módulos de negócio são empacotados e implantados como parte da mesma aplicação Spring Boot.

Portanto:

- Os módulos compartilham o mesmo runtime.
- Os módulos são liberados juntos, na mesma release.
- Os módulos escalam juntos.
- Um deploy afeta toda a aplicação de backend.
- Um módulo não pode ser implantado de forma independente.
- Evita-se a complexidade de infraestrutura associada a serviços distribuídos.

A estrutura modular é, portanto, uma **fronteira de código e de arquitetura**, e não uma fronteira de deploy.

## Alternativas consideradas

### Microsserviços

Rejeitada para a V2.

Microsserviços ofereceriam fronteiras independentes de deploy e de escalabilidade, mas também trariam complexidade operacional e arquitetural adicional, incluindo comunicação entre serviços, modos de falha distribuídos, coordenação de deploys, observabilidade e questões de propriedade dos dados.

Os requisitos atuais não justificam essa complexidade.

### Monolito tradicional

Rejeitada.

Um monolito tradicional, sem fronteiras explícitas entre módulos, manteria o deploy simples, mas deixaria as fronteiras de negócio menos explícitas e aumentaria o risco de acoplamento forte entre funcionalidades não relacionadas.

O monolito modular oferece a simplicidade operacional de um monolito e, ao mesmo tempo, estabelece fronteiras internas mais fortes.

### Monolito modular

Escolhida.

O monolito modular oferece:

- Uma única aplicação implantável
- Fronteiras de negócio explícitas
- Menor complexidade operacional
- Desenvolvimento local mais fácil
- Testes e depuração mais simples
- Ownership claro por módulo
- A possibilidade de extrair um módulo para um serviço no futuro, se isso se justificar

## Trade-offs

### Vantagens

- Deploy mais simples
- Menor complexidade de infraestrutura
- Desenvolvimento local mais fácil
- Depuração mais fácil
- Separação mais forte das responsabilidades de negócio
- Ownership mais claro
- Menor overhead de comunicação em rede
- Consistência transacional mais fácil dentro da aplicação

### Desvantagens

- Os módulos compartilham o mesmo ciclo de vida de deploy
- Os módulos não podem escalar de forma independente
- Uma falha na aplicação pode afetar vários módulos
- É preciso disciplina rigorosa para evitar que as fronteiras entre módulos se degradem
- A aplicação pode ficar fortemente acoplada se as APIs internas dos módulos forem contornadas

## Consequências

As fronteiras entre módulos devem ser tratadas como restrições arquiteturais, e não apenas como organização de pacotes.

Testes de arquitetura devem verificar que os módulos não acessam detalhes de implementação proibidos de outros módulos e que as regras de dependência são respeitadas.

Toda nova funcionalidade deve ser atribuída a um módulo existente; um novo módulo de negócio só deve ser criado quando houver uma fronteira de negócio clara.

A arquitetura não deve introduzir infraestrutura de microsserviços só porque a base de código tem vários módulos.

Se, no futuro, um módulo exigir deploy, escalabilidade, ownership ou isolamento operacional independentes, essa decisão deve ser avaliada separadamente, em uma nova decisão arquitetural.

## Notas de implementação

O projeto Spring Boot deve organizar o código em torno de módulos de negócio, e não de camadas técnicas que atravessam a aplicação inteira.

Por exemplo:

```text
backend/
└── src/
    └── main/
        └── java/
            └── <base-package>/
                ├── <module-a>/
                │   ├── domain/
                │   ├── application/
                │   ├── infrastructure/
                │   └── api/
                │
                ├── <module-b>/
                │   ├── domain/
                │   ├── application/
                │   ├── infrastructure/
                │   └── api/
                │
                └── <module-c>/
                    ├── domain/
                    ├── application/
                    ├── infrastructure/
                    └── api/
```

Os nomes exatos dos módulos e sua estrutura interna são definidos pela documentação central de arquitetura e não devem ser inventados por esta ADR.

## Testes de arquitetura

Existem testes de arquitetura que validam as fronteiras modulares definidas pela arquitetura central.

A implementação verifica que:

- Módulos não acessam pacotes internos proibidos de outros módulos.
- A direção das dependências segue a arquitetura definida.
- Módulos de negócio não dependem diretamente da infraestrutura de outro módulo.
- Módulos expõem apenas a API pública prevista, ou seja, seus pacotes `api` e `events`.
- O scaffolding compartilhado em `core` nunca depende de volta de um módulo de negócio.
- Não existe ciclo de dependência entre módulos, que é justamente o que tornaria impossível extrair
  um módulo para um serviço no futuro.

As regras, a verificação sobre o código de produção e as fixtures que violam as regras de propósito,
provando que cada regra ainda detecta sua violação, estão documentadas na
[ADR-002 — Camadas e regras de dependência](ADR-002-camadas-e-regras-de-dependencia.md)
e implementadas em
[backend/src/test/java/com/gomech/api/architecture/](https://github.com/DeyvidJesus/gomech-backend-v2/tree/master/src/test/java/com/gomech/api/architecture).

Os testes rodam no `mvn test` e no CI, então uma violação quebra o build em vez de depender do code review para ser detectada.

## Dependências

Esta ADR depende da documentação central de arquitetura para:

- Módulos de negócio definidos
- Responsabilidades dos módulos
- Direção das dependências
- Ownership dos módulos
- Contratos públicos dos módulos

Esta ADR não redefine essas fronteiras.

## Fora do escopo

Esta ADR não:

- Redesenha a arquitetura do backend
- Define módulos de negócio individuais
- Define schemas de banco de dados
- Define endpoints de API
- Introduz microsserviços
- Define a infraestrutura de deploy
- Estabelece uma estratégia de extração de serviços

## Critérios de aceite

- [x] ADR revisada e aprovada.
- [x] ADR armazenada junto à documentação de arquitetura.
- [x] Decisão pelo monolito modular documentada explicitamente.
- [x] Alternativas documentadas.
- [x] Trade-offs documentados.
- [x] Consequências documentadas.
- [x] Ownership dos módulos documentado ou referenciado a partir da arquitetura central.
- [x] Implicações de deploy documentadas.
- [x] Testes de arquitetura existentes referenciados.
- [x] Testes de arquitetura verificam as fronteiras de módulo definidas.

## Documentação relacionada

- Arquitetura central
- [Arquitetura do backend](https://github.com/DeyvidJesus/gomech-backend-v2/blob/master/docs/arquitetura.md)
- Mapa de ownership dos módulos
- [Testes de arquitetura](https://github.com/DeyvidJesus/gomech-backend-v2/tree/master/src/test/java/com/gomech/api/architecture)
