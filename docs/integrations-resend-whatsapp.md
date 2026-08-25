# Guia de Configuração das Integrações: Resend (E-mail) & WhatsApp API

Este documento detalha o funcionamento e a configuração das integrações de mensageria e comunicação no **GoMech ERP**.

---

## 1. Integração com Resend (E-mail Transacional)

O GoMech ERP utiliza o **Resend** para disparos rápidos e de alta entregabilidade de e-mails transacionais com templates HTML modernos e responsivos.

### A. Eventos Cobertos pelo Resend:
1. **Boas-vindas a Novos Colaboradores**: Credenciais de acesso inicial e instruções de login disparadas ao cadastrar um usuário no IAM.
2. **Atualização de Permissões e Papéis**: Notificação enviada ao colaborador quando seu perfil de acesso é modificado pela gerência.
3. **Atribuição de Tarefas em Equipe**: Alerta por e-mail quando o colaborador é designado para um **Agendamento**, **Vistoria Técnica**, **Validação de Orçamento** ou **Ordem de Serviço**.
4. **Envio de Orçamentos para Clientes**: Envio automático do resumo de itens e link seguro do portal público de aprovação online.
5. **Aviso de Conclusão de Serviço**: E-mail avisando o cliente que o veículo está pronto para retirada.

### B. Variáveis de Ambiente no Backend:
| Variável | Padrão | Descrição |
| :--- | :--- | :--- |
| `RESEND_API_KEY` | `re_mock_api_key_gomech_test` | Chave de API gerada no painel do [Resend](https://resend.com) (`re_...`). Caso utilize a chave mock, o sistema simula o envio em log. |
| `RESEND_FROM_EMAIL` | `GoMech ERP <nao-responda@gomech.com.br>` | Remetente com domínio validado no Resend. |

---

## 2. Integração com WhatsApp API (Evolution API / Z-API / WhatsApp Cloud)

O serviço `WhatsAppService` permite que a oficina envie links diretos de aprovação de orçamentos, comprovantes e lembretes de agendamentos no WhatsApp do cliente.

### A. Provedores Suportados:
- **Evolution API** (Self-hosted ou Cloud)
- **Z-API**
- **WhatsApp Cloud API / Twilio**

### B. Variáveis de Ambiente no Backend:
| Variável | Padrão | Descrição |
| :--- | :--- | :--- |
| `WHATSAPP_API_URL` | `https://api.evolution-api.com` | URL base do gateway WhatsApp |
| `WHATSAPP_API_KEY` | `mock-whatsapp-key` | Token de autenticação da instância |
| `WHATSAPP_INSTANCE_NAME` | `gomech-main` | Identificador da instância conectada via QR Code |

---

## 3. Integração com Pagar.me V5 (Assinaturas & Pagamentos)

### A. Funcionamento do Cadastro:
- Ao criar a conta no GoMech, o cliente escolhe o plano (`STARTER`, `PRO`, `ENTERPRISE`) e cadastra o **Cartão de Crédito**.
- A API da Pagar.me cria o `Customer`, tokeniza o cartão e cria a `Subscription` com **14 dias de Trial gratuito**.
- O primeiro débito só ocorre após o término do período de experimentação, garantindo segurança contra fraudes e validação cadastral.

### B. Variáveis de Ambiente:
| Variável | Padrão | Descrição |
| :--- | :--- | :--- |
| `PAGARME_SECRET_KEY` | `sk_test_...` | Chave secreta da API V5 Pagar.me |
| `PAGARME_PUBLIC_KEY` | `pk_test_...` | Chave pública para tokenização frontend |
| `PAGARME_WEBHOOK_SECRET` | `secret_...` | Segredo para validação de assinatura HMAC dos webhooks |
