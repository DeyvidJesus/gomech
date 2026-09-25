# ADR-002: Camadas dos módulos e regras de dependência

- **Status:** Aceita
- **Data:** 2026-08-18

## Contexto

O GoMech V2 está sendo construído como um único monolito modular em Spring Boot, com um serviço de IA independente.

O repositório já define módulos de backend orientados ao domínio em `com.gomech.api.modules`, mas as fronteiras entre módulos ainda não são aplicadas de forma consistente pela estrutura do código nem por testes automatizados. Sem regras explícitas de camadas e de dependência, o monolito tende a derivar para acesso compartilhado à persistência, dependências cíclicas e acoplamento entre funcionalidades, algo caro de reverter depois que os módulos de negócio estiverem implementados.

É necessária uma decisão única e compartilhada que deixe explícito:

- como cada módulo do backend é dividido em camadas
- quem é dono da persistência e das transações
- quais direções de dependência são permitidas
- como os módulos se comunicam
- como essas regras se traduzem em testes de arquitetura e imports proibidos

Esta ADR se aplica ao backend Spring Boot em `gomech/backend`.

## Decisão

Todos os módulos de negócio usam o mesmo modelo interno de camadas:

```text
com.gomech.api.modules.<module>
├── api
├── application
├── domain
└── infrastructure
```

O código transversal de suporte permanece em `com.gomech.api.core`.

### Responsabilidades das camadas

#### `api`

- Contém os controllers HTTP, os DTOs de request/response e os contratos públicos que o módulo expõe a outros módulos.
- Pode depender de `application` e de tipos de contrato de outros módulos.
- Não deve depender diretamente de `infrastructure`.

#### `application`

- Contém os casos de uso, a orquestração, as transações e os serviços de aplicação.
- Pode depender do seu próprio `domain`.
- Pode consumir outros módulos apenas por meio de contratos explícitos em `api` ou de eventos publicados.
- Não deve depender do `domain` nem da `infrastructure` de outro módulo.

#### `domain`

- Contém as regras de negócio, agregados, value objects, serviços de domínio e invariantes.
- Não deve depender de `api`, `application`, Spring MVC, repositórios JPA nem adapters de infraestrutura.
- É a camada mais estável e aponta apenas para dentro: para si mesma ou para tipos do shared kernel explicitamente permitidos em `core`.

#### `infrastructure`

- Contém os adapters de persistência, entidades JPA, repositórios Spring Data, clientes externos, adapters de mensageria e integrações com frameworks.
- Pode depender de `domain`.
- Não deve ser referenciada diretamente por outro módulo.

## Propriedade da persistência

A propriedade da persistência é local a cada módulo.

- Cada módulo é dono das suas tabelas, entidades JPA, migrations, repositórios e adapters de persistência.
- Nenhum módulo pode ler ou escrever diretamente nos repositórios de outro módulo.
- Nenhum módulo pode fazer join com tabelas de outro módulo por meio da sua própria camada de repositório.
- O acesso a dados entre módulos deve ocorrer por meio de:
  - um contrato público de aplicação exposto no pacote `api` do módulo dono
  - um evento de domínio/aplicação consumido de forma assíncrona

Exemplos:

- `operations` não pode injetar repositórios de `inventory` para baixar estoque diretamente.
- `finance` não pode consultar tabelas de `operations` por meio de um repositório customizado.
- `billing` pode depender de contratos de `iam`, mas não de tipos de persistência de `iam`.

## Direções de dependência permitidas

Dependências permitidas dentro de um módulo:

- `api -> application`
- `application -> domain`
- `infrastructure -> domain`
- `infrastructure -> application`, apenas para conectar adapters a ports definidas em `application`, quando necessário

Dependências proibidas dentro de um módulo:

- `domain -> application`
- `domain -> api`
- `domain -> infrastructure`
- `application -> infrastructure` por tipo de implementação concreta
- `api -> infrastructure`

Dependências permitidas entre módulos:

- `<module>.api -> <other-module>.api`
- `<module>.application -> <other-module>.api`
- `<module>.application -> <other-module>.events`

Dependências proibidas entre módulos:

- `<module>.* -> <other-module>.domain`
- `<module>.* -> <other-module>.infrastructure`
- `<module>.* -> <other-module>.repositories`
- `<module>.* -> <other-module>.models`

## Regras de comunicação

A comunicação entre módulos usa apenas contratos explícitos:

1. Chamadas síncronas por meio dos contratos públicos do módulo em `api`
2. Integração assíncrona por meio de eventos explícitos em `events`

Nenhum módulo pode tratar o modelo de entidades de outro módulo como uma biblioteca compartilhada.

O serviço de IA independente está fora dessas regras entre módulos in-process. O backend pode expor contratos de aplicação voltados à IA, mas esta ADR não concede ao serviço Python propriedade direta sobre o banco de dados.

## Alternativas consideradas

### Manter o layout atual controller/service/repository/model em cada módulo

Rejeitada porque não distingue contratos públicos de infraestrutura e torna provável o vazamento de repositórios.

### Arquitetura hexagonal completa em todo lugar desde o primeiro dia

Rejeitada por enquanto, porque adiciona mais indireção do que o projeto precisa antes de os módulos de negócio centrais existirem. O modelo de quatro camadas escolhido é um conjunto de regras mais enxuto e mais simples de adotar.

### Permitir acesso a repositórios entre módulos dentro do monolito

Rejeitada porque acopla os schemas de persistência, esconde as fronteiras de propriedade e torna refatorações ou extrações futuras muito mais difíceis.

## Trade-offs

### Benefícios

- Torna explícita a propriedade da persistência.
- Isola as regras de domínio do código de transporte e de framework.
- Oferece um template de módulo único e repetível.
- Abre um caminho direto para verificações automatizadas de arquitetura.

### Custos

- Mais pacotes e interfaces logo de início.
- Alguns casos de uso vão exigir DTOs de contrato ou eventos em vez de reaproveitar repositórios diretamente.
- Refatorar o código inicial de IAM para o modelo de pacotes alvo exigirá trabalho posterior.

## Consequências

- Novos módulos de negócio devem ser criados com `api/application/domain/infrastructure`.
- Os antigos pacotes `controllers`, `dto`, `services`, `models` e `repositories` foram removidos. O IAM foi migrado para `api/application/domain/infrastructure`, e a regra `modules_must_follow_the_four_layer_layout` agora impede que eles voltem.
- Os testes de arquitetura passam a fazer parte da definition of done do backend.
- Pedidos de acesso entre módulos passam a ser avaliados como questões de design de contrato, e não como imports de conveniência.

## Aplicação das regras

As regras a seguir são aplicadas por testes ArchUnit. Elas rodam como parte do `mvn test`, então uma
dependência proibida quebra o build e o CI.

| Regra | Teste ArchUnit |
|------|--------------------|
| todo pacote de módulo é uma das quatro camadas (ou `events`) | `modules_must_follow_the_four_layer_layout` |
| controllers ficam em `api` | `controllers_must_reside_in_the_api_layer` |
| entidades JPA ficam em `infrastructure` | `jpa_entities_must_reside_in_the_infrastructure_layer` |
| repositórios Spring Data ficam em `infrastructure` | `spring_data_repositories_must_reside_in_the_infrastructure_layer` |
| `domain` não depende de camadas externas | `domain_must_not_depend_on_outer_layers` |
| `domain` não depende de Spring, JPA, Hibernate nem da Servlet API | `domain_must_not_depend_on_frameworks` |
| `application` não depende dos seus próprios controllers nem de tipos web do Spring | `application_must_not_depend_on_api_controllers` |
| `api` não acessa `infrastructure` diretamente | `api_must_not_access_infrastructure_directly` |
| `core` não depende de nenhum módulo de negócio | `core_must_not_depend_on_business_modules` |
| módulos se ligam a abstrações do `core`, não a implementações do `core` | `modules_must_not_depend_on_core_infrastructure` |
| módulos não importam tipos de persistência de outro módulo | `cross_module_access_must_not_target_persistence` |
| módulos só alcançam outros módulos via `api` e `events` | `cross_module_access_must_target_public_contracts_only` |
| módulos não chamam controllers de outro módulo | `modules_must_not_depend_on_another_modules_controllers` |
| repositórios não são importados fora do módulo dono | `repositories_must_not_be_imported_outside_their_module` |
| contratos/eventos públicos ficam em pacotes explícitos | `module_contracts_must_live_in_api_or_events_packages` |
| não existe ciclo de dependência entre módulos | `modules_must_be_free_of_cycles` |

As regras de camada se aplicam aos módulos de negócio **e** aos slices do `core`, que usam os mesmos
nomes de camada. Os pacotes de camada são casados como `..modules..<layer>..` e `..core..<layer>..`,
e não como um `..api..` isolado, porque o pacote raiz da própria aplicação é `com.gomech.api` e a
forma isolada casaria com tudo.

O layout de quatro camadas é obrigatório apenas para módulos de negócio. Um slice do `core` tem só as
camadas de que realmente precisa, e as regras se aplicam às que existirem:

| Slice do core | Camadas presentes | Motivo |
|---|---|---|
| `audit` | `api`, `application`, `domain`, `infrastructure` | `AuditEntry` é um fato registrado com semântica de valor própria, por isso tem um tipo de domínio |
| `authorization` | `api`, `application`, `infrastructure` | seu vocabulário (`ActorContext`, `AuthorizationRequest`, `AccessDecision`) *é* o contrato publicado, por isso fica em `api` |
| `entitlement` | `api`, `application`, `infrastructure` | idem: `EntitlementSnapshot` é o contrato |

Nunca se cria um pacote de camada vazio só para satisfazer o formato. Duplicar um tipo de contrato
entre `api` e `domain` foi o que produziu os gêmeos mortos `AuthorizationResult` e `EntitlementView`,
já removidos: uma representação por conceito, na camada que é dona dele.

Três regras classificam por responsabilidade, e não por nome de pacote: um `@RestController`, uma
`@Entity` e um repositório Spring Data precisam ficar na camada certa, não importa em qual pacote
(com nome válido) tenham sido colocados. Como essas regras têm uma cláusula `that()` e não usam
`allowEmptyShould`, elas também falham se a base de código deixar de ter qualquer classe desse tipo,
então nunca passam no vazio.

As propriedades a seguir desse conjunto de regras são deliberadas.

**A superfície permitida entre módulos é definida por exclusão.** Um módulo publica seus pacotes
`api` e `events`. Qualquer outro pacote sob `com.gomech.api.modules.<module>` é interno, seja qual for
o nome. Assim, um novo pacote interno já nasce protegido, sem precisar de atualização nas regras.

**`application` pode usar os DTOs do seu próprio `api`, mas nunca seus controllers.** Esta ADR coloca
os DTOs de request/response em `api`, e `application -> api` não está na lista de dependências
proibidas acima; o alvo da regra são as *implementações* de `api`. Por isso,
`application_must_not_depend_on_api_controllers` proíbe um caso de uso de depender de uma classe
`@RestController`/`@Controller` ou de qualquer tipo de `org.springframework.web`, mas continua
permitindo os records de DTO. Isso mantém o HTTP fora dos casos de uso sem obrigar a criar um
conjunto duplicado de DTOs na camada de aplicação.

**As falhas indicam a correção.** Cada regra tem uma cláusula `because(...)` que aponta a saída, de
modo que uma violação é lida como uma instrução, e não como uma simples rejeição:

```text
com.gomech.api.core.tenancy.SomeClass depends on
com.gomech.api.modules.iam.infrastructure.persistence.repository.UserRepository, but module 'iam'
owns that repository. Fix: ask the owning module for the data through its api contract instead of
importing its repository interface.
```

**As regras de camada não são mais declaradas com `allowEmptyShould(true)`.** O IAM agora usa o
layout alvo, então `api`, `application`, `domain` e `infrastructure` casam com classes reais de
produção. Sem essa flag, uma regra que deixa de casar com qualquer classe (depois de renomear um
pacote, ou se uma camada for esvaziada) quebra o build em vez de passar no vazio. As fixtures com
violações descritas na seção [Testes](#testes) continuam sendo a segunda linha de proteção.

### Desvio transitório conhecido

Hoje, `application` depende de interfaces de repositório Spring Data que pertencem a
`infrastructure`, o que a lista de dependências proibidas acima exclui ("por tipo de implementação
concreta"). Fechar essa lacuna exige ports em `application` com adapters em `infrastructure`, e
modelos de domínio separados das entidades JPA: o passo hexagonal completo que esta ADR adiou
deliberadamente. Nenhuma regra aplica esse limite ainda; ele está registrado como trabalho futuro, em
vez de ser tratado silenciosamente como conforme.

## Testes

As regras são definidas uma única vez em
[backend/src/test/java/com/gomech/api/architecture/ModuleArchitectureRules.java](https://github.com/DeyvidJesus/gomech-backend-v2/blob/master/src/test/java/com/gomech/api/architecture/ModuleArchitectureRules.java)
e aplicadas duas vezes:

- [ModuleArchitectureRulesTest.java](https://github.com/DeyvidJesus/gomech-backend-v2/blob/master/src/test/java/com/gomech/api/architecture/ModuleArchitectureRulesTest.java)
  as verifica contra o código de produção.
- [ModuleArchitectureRuleFixturesTest.java](https://github.com/DeyvidJesus/gomech-backend-v2/blob/master/src/test/java/com/gomech/api/architecture/ModuleArchitectureRuleFixturesTest.java)
  as verifica contra as fixtures que violam as regras de propósito, em
  [architecture/fixtures/](https://github.com/DeyvidJesus/gomech-backend-v2/tree/master/src/test/java/com/gomech/api/architecture/fixtures),
  garantindo que cada regra continue falhando, aponte a classe infratora e informe a correção.

O teste de fixtures é o que mantém o conjunto de regras honesto. Uma regra que deixa de casar com
qualquer classe, depois de renomear um pacote ou de um erro de digitação em um padrão de pacote,
continuaria passando contra o código de produção para sempre. As fixtures ficam nos fontes de teste e
são excluídas da verificação de produção por `ImportOption.Predefined.DO_NOT_INCLUDE_TESTS`.

O CI executa os testes de arquitetura como uma etapa dedicada, com nome próprio, em
[.github/workflows/ci.yml](../../.github/workflows/ci.yml),
antes da suíte completa do backend, para que uma violação de fronteira seja reportada como violação de
fronteira, e não como uma falha entre muitas.

O trabalho futuro deve estender esses testes módulo a módulo, à medida que os pacotes migrarem da
estrutura transitória atual para as camadas alvo.
