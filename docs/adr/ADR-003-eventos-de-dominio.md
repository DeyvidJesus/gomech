# ADR-003: Eventos de domínio

- **Status:** Aceita
- **Data:** 2026-08-18
- **Relacionadas:** [ADR-001 — Monolito modular](ADR-001-monolito-modular.md), [ADR-002 — Camadas e regras de dependência](ADR-002-camadas-e-regras-de-dependencia.md)

## Contexto

O GoMech V2 é um monolito modular. Os módulos de negócio precisam de uma forma de reagir a consequências relevantes geradas por outros módulos sem criar dependências diretas de repositório nem acoplamento no nível de serviços.

A [ADR-001](ADR-001-monolito-modular.md) estabeleceu o monolito modular. A [ADR-002](ADR-002-camadas-e-regras-de-dependencia.md) estabeleceu as camadas dos módulos, a propriedade da persistência e a regra de que a comunicação entre módulos deve ocorrer por meio de contratos explícitos ou de eventos.

Esta ADR define quando usar eventos de domínio/aplicação in-process, o que eles significam e em quais garantias de entrega os consumidores podem confiar.

O objetivo é desacoplar comportamentos entre módulos, e não transformar indiscriminadamente toda operação de escrita em evento.

## Decisão

O GoMech usará application events do Spring, in-process, para consequências relevantes entre módulos dentro do monolito do backend.

Os eventos são:

- inicialmente apenas in-process
- publicados dentro da mesma JVM
- destinados a consequências de negócio relevantes entre módulos
- não criados por padrão para operações CRUD

Esta ADR se aplica ao backend Spring Boot em `gomech/backend`.

## Quando publicar um evento

Um evento deve ser publicado quando todas as condições a seguir forem verdadeiras:

1. Um módulo conclui uma ação de negócio com consequências relevantes para outro módulo.
2. A consequência deve permanecer desacoplada da implementação de persistência de quem publica.
3. O consumidor não precisa participar chamando diretamente a camada de repositório de quem publica.
4. O nome do evento expressa um fato de negócio que já aconteceu.

Eventos não devem ser publicados para:

- todo create, update ou delete, por padrão
- coreografia interna de métodos dentro do mesmo módulo
- notificações técnicas de ciclo de vida sem significado de negócio
- casos em que um contrato síncrono direto entre módulos é mais claro do que um evento

## Seleção de eventos

Use eventos para consequências relevantes entre módulos, como:

- `WorkOrderCompleted`
  - Exemplo de consequência: o módulo `finance` cria um lançamento de contas a receber
  - Exemplo de consequência: o módulo `inventory` finaliza o relatório de consumo de estoque
- `InventoryPurchaseRecorded`
  - Exemplo de consequência: o módulo `finance` registra a obrigação de pagamento ao fornecedor
  - Exemplo de consequência: o módulo `analytics` atualiza as tendências de compra

Esses são exemplos de fatos de negócio, e não convenções de payload de transporte.

## Significado de um evento

Um evento descreve algo que já aconteceu do ponto de vista de quem o publica.

Nomes de eventos devem:

- usar linguagem de negócio no passado
- refletir um fato de negócio concluído
- fazer sentido sem mencionar detalhes de transporte

Bons exemplos:

- `WorkOrderCompleted`
- `InventoryPurchaseRecorded`
- `InvoiceIssued`

Maus exemplos:

- `WorkOrderUpdated`
- `SaveInventoryThing`
- `AfterControllerReturned`

## Garantias de entrega

O modelo inicial de entrega é explicitamente limitado:

- a entrega é in-process
- a entrega ocorre dentro do mesmo runtime da aplicação
- os eventos não são duráveis
- os eventos não podem ser reprocessados (replay) por padrão
- os eventos não passam por um broker

Os consumidores podem assumir que:

- quem publica e quem consome compartilham a mesma base de código e o mesmo processo JVM
- o payload do evento fica disponível imediatamente para os listeners do Spring

Os consumidores não devem assumir:

- durabilidade da mensagem após um crash do processo
- retries automáticos
- entrega entre processos
- semânticas de broker, como partições, offsets ou dead-letter queues

Se o processo cair depois do commit da transação de negócio, mas antes de um listener terminar, a consequência do evento pode ser perdida. Essa é uma limitação aceita do modelo in-process da V1.

## Comportamento dos consumidores

Os consumidores devem:

- pertencer ao módulo dono da consequência
- tratar o evento como um contrato de entrada, e não como permissão para acessar as tabelas de outro módulo
- ser idempotentes sempre que viável
- manter o processamento focado e rápido
- evitar orquestração interativa ou de longa duração no próprio listener

Os consumidores devem preferir:

- criar seus próprios registros usando seus próprios repositórios
- chamar seus próprios serviços de aplicação
- registrar em log contexto suficiente para diagnóstico

Os consumidores não devem:

- alterar diretamente o modelo de persistência de quem publicou
- importar repositórios ou entidades de outro módulo
- depender da ordem dos eventos entre listeners não relacionados, a menos que isso seja explicitamente projetado e testado

## Transação e publicação

Por padrão, os eventos do GoMech são eventos Spring in-process.

Para consequências entre módulos que precisam observar estado já commitado, a publicação e o consumo devem preferir listeners transacionais, como `@TransactionalEventListener` com `AFTER_COMMIT`.

Isso significa que:

- quem publica é dono da transação de negócio principal
- os consumidores observam um fato de negócio concluído
- os consumidores não devem presumir que podem fazer rollback da escrita de quem publicou depois do commit

As implementações específicas de cada módulo devem testar explicitamente o estilo de listener escolhido.

## Alternativas consideradas

### Apenas chamadas diretas de serviço entre módulos

Rejeitada porque algumas consequências são mais bem modeladas como reações a fatos de negócio concluídos do que como cadeias de orquestração síncrona.

### Kafka ou RabbitMQ desde o início

Rejeitada para a V1. A infraestrutura de broker adiciona uma complexidade operacional e de entrega de que o sistema ainda não precisa.

### Emitir eventos CRUD para toda escrita

Rejeitada porque gera ruído, enfraquece o significado dos eventos e incentiva o acoplamento acidental às mudanças de persistência, em vez dos resultados de negócio.

## Trade-offs

### Benefícios

- Desacopla as consequências entre módulos do acesso direto à persistência.
- Preserva a propriedade de cada módulo.
- Torna as reações de negócio explícitas no código.
- Encaixa-se no monolito modular sem infraestrutura extra.

### Custos

- A entrega não é durável.
- Falhas em listeners exigem tratamento deliberado.
- Uma seleção ruim de eventos geraria ruído rapidamente.
- Alguns comportamentos ainda precisam de contratos síncronos em vez de eventos.

## Consequências

- Reações entre módulos devem ser projetadas intencionalmente, e não inferidas a partir de CRUD.
- Os consumidores de eventos passam a fazer parte do comportamento do módulo e devem ser testados como código de primeira classe.
- Se requisitos futuros exigirem durabilidade, replay ou escalabilidade independente, uma nova ADR deve revisitar o modelo de entrega.
- A arquitetura atual mantém os eventos como ferramenta do monolito modular, e não como uma abstração de sistemas distribuídos.

## Regras de uso e aplicação

- Os eventos ficam em pacotes explícitos do módulo, como `events`, ou em outro pacote de contrato claramente público.
- Os payloads dos eventos devem conter os identificadores e o contexto de negócio de que os consumidores precisam, sem expor estruturas internas de persistência.
- Os consumidores usam apenas os serviços e repositórios do próprio módulo.
- Nenhum módulo pode depender de tipos de persistência de outro módulo para consumir um evento.

Esta ADR complementa as regras da [ADR-002 — Camadas e regras de dependência](ADR-002-camadas-e-regras-de-dependencia.md).

## Testes

Os testes de referência de consumo de eventos ficam em:

- [backend/src/test/java/com/gomech/api/events/InProcessDomainEventConsumerTest.java](https://github.com/DeyvidJesus/gomech-backend-v2/blob/master/src/test/java/com/gomech/api/events/InProcessDomainEventConsumerTest.java)

Esse teste de referência valida a premissa básica de que eventos de negócio nomeados, como `WorkOrderCompleted` e `InventoryPurchaseRecorded`, são consumidos in-process por listeners dedicados.

Os consumidores de eventos específicos de cada módulo devem ter seus próprios testes para:

- efeitos colaterais do listener
- tratamento idempotente, quando necessário
- comportamento transacional de publicação e consumo
- tratamento de falhas no caminho de consequência escolhido

## Fora do escopo

Esta ADR não:

- introduz Kafka, RabbitMQ ou outro broker na V1
- exige eventos CRUD por padrão
- define um padrão outbox
- define eventos de integração entre serviços para o serviço de IA independente
