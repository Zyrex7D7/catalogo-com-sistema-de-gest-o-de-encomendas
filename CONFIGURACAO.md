# Guia de Configuração — In.printing.lab

O site já está pronto e funciona sem nenhuma configuração (catálogo + encomenda direta por WhatsApp, como antes). Este guia liga o **sistema de confirmação por email** e o **painel de administração**. É tudo gratuito para o volume de encomendas de uma loja pequena/média.

Vais precisar de criar contas em dois serviços gratuitos:
- **Supabase** — a base de dados que guarda as encomendas e o login do admin
- **EmailJS** — o serviço que envia o email com o código de confirmação

Tempo estimado: 20-30 minutos, sem precisares de saber programar.

---

## 1. Criar o projeto Supabase

1. Vai a [supabase.com](https://supabase.com) e cria uma conta gratuita.
2. Cria um **novo projeto** (escolhe um nome, uma password forte para a base de dados — guarda-a nas notas, e a região mais próxima, ex. Frankfurt).
3. Espera 1-2 minutos até o projeto ficar pronto.
4. No menu lateral, vai a **SQL Editor** → **New query**.
5. Abre o ficheiro `supabase-schema.sql` (incluído nesta pasta), copia **todo** o conteúdo, cola no editor e clica **Run**.
   - Isto cria a tabela de encomendas, a tabela de produtos, o espaço de armazenamento das fotos e as regras de segurança automaticamente.
   - Também semeia (insere) os produtos que já tinhas no catálogo, para não perderes nada.
   - Se já tinhas corrido uma versão anterior deste script (só com a tabela `orders`), podes correr este de novo sem problema — as partes já criadas são substituídas (`create or replace`) e só a tabela `products` é nova.
6. Vai a **Project Settings** (ícone de engrenagem) → **API**.
   - Copia o **Project URL** → cola em `config.js` no campo `SUPABASE_URL`.
   - Copia a chave **anon public** → cola em `config.js` no campo `SUPABASE_ANON_KEY`.

### Criar o teu login de administrador
1. No menu lateral, vai a **Authentication** → **Users** → **Add user** → **Create new user**.
2. Preenche com o teu email e uma password (esta é a password que vais usar para entrar em `admin.html`).
3. Desmarca a opção de pedir confirmação por email (ou confirma manualmente), para poderes entrar de imediato.

---

## 2. Criar a conta EmailJS (envio dos códigos)

1. Vai a [emailjs.com](https://www.emailjs.com) e cria uma conta gratuita (200 emails/mês grátis, suficiente para começar).
2. **Email Services** → **Add New Service** → escolhe Gmail, Outlook ou outro, e liga a tua conta de email da loja.
   - Copia o **Service ID** → cola em `config.js` no campo `EMAILJS_SERVICE_ID`.
3. **Email Templates** → **Create New Template**. Cria um template com este conteúdo (podes adaptar o design):

   **Assunto:** Confirma a tua encomenda {{order_number}} — {{nome_loja}}

   **Corpo:**
   ```
   Olá {{to_name}},

   Recebemos o teu pedido {{order_number}}.

   Itens: {{items_resumo}}
   Total: {{total}}

   O teu código de confirmação é: {{code}}

   Introduz este código no site para confirmares a encomenda.
   O código expira em 15 minutos.

   Obrigado,
   {{nome_loja}}
   ```
   - Certifica-te que o campo "To Email" do template está definido como `{{to_email}}`.
   - Copia o **Template ID** → cola em `config.js` no campo `EMAILJS_TEMPLATE_ID`.
4. **Account** → **General** → copia a **Public Key** → cola em `config.js` no campo `EMAILJS_PUBLIC_KEY`.

---

## 3. Preencher o config.js

Abre `config.js` e confirma que tens todos os campos preenchidos:

```js
SUPABASE_URL: "https://xxxxxxxx.supabase.co",
SUPABASE_ANON_KEY: "eyJ...",
EMAILJS_PUBLIC_KEY: "xxxxxxxx",
EMAILJS_SERVICE_ID: "service_xxxx",
EMAILJS_TEMPLATE_ID: "template_xxxx",
WHATSAPP_NUMERO: "351215959525",
NOME_LOJA: "In.printing.lab",
```

Grava o ficheiro. A partir daqui, o site passa a usar automaticamente o fluxo completo (código por email + painel de admin). Não precisas de tocar em mais nenhum ficheiro.

---

## 4. Publicar o site (hospedagem gratuita mais simples)

Recomendação: **Netlify** — arrastar e largar, sem linha de comandos.

1. Vai a [netlify.com](https://netlify.com) e cria uma conta gratuita.
2. **Add new site** → **Deploy manually**.
3. Arrasta a pasta inteira do site (com `index.html`, `admin.html`, `config.js`, `ln.png` e as pastas de fotos dos produtos) para a zona de upload.
4. Em 30 segundos tens um link público (ex: `inprintinglab.netlify.app`). Podes ligar um domínio próprio depois em **Domain settings**.

Se preferires GitHub Pages, funciona da mesma forma — basta enviar estes ficheiros para o repositório e ativar Pages nas definições.

---

## 5. Como usar no dia a dia

- **Clientes:** escolhem produtos → carrinho → dados (nome, email, telemóvel) → recebem código por email → confirmam → recebem o nº de encomenda. Em "A minha encomenda" veem todas as encomendas feitas com o seu email, e podem cancelar as que ainda estão a aguardar confirmação.
- **Tu (dono):** abre `admin.html`, entra com o teu login.
  - Na aba **Encomendas**, vês todas por estado (Aguarda confirmação, Confirmada, Em produção, Pronta, Entregue, Cancelada). Clicas numa para ver os detalhes e mudar o estado.
  - Na aba **Produtos**, crias, editas ou apagas os produtos do catálogo — nome, descrição, preço, categoria, fotos (carregadas diretamente, sem mexer em pastas) e os campos de personalização (ex: cor, nome). O catálogo do site atualiza-se sozinho a partir daqui.

### Sobre a prevenção de erros já incluída
- O cliente tem de indicar nome, email e **telemóvel** (agora obrigatório) e marcar uma confirmação antes de submeter.
- O código de confirmação por email garante que o email pertence mesmo ao cliente e que ele reviu os dados uma segunda vez.
- O cliente pode cancelar a própria encomenda enquanto ela ainda estiver "a aguardar confirmação", em "A minha encomenda".
- Deteção automática de **encomendas repetidas** (bloqueia mais de 3 encomendas do mesmo email em 10 minutos).
- Código expira em 15 minutos e tem limite de tentativas erradas, para evitar abuso.
- Se a base de dados estiver em baixo ou mal configurada, o site **não bloqueia o cliente** — volta automaticamente ao envio direto por WhatsApp.

---

## Notas e limitações importantes

- Este sistema não processa pagamentos online — continua a combinar o pagamento como já fazias (transferência, MB Way, na entrega, etc.). Se quiseres cobrar online no futuro, dá para adicionar Stripe ou MB Way depois.
- O total da encomenda é calculado a partir dos preços do catálogo no momento da compra; se precisares de alterar preços mais tarde, isso não afeta encomendas já feitas.
- O plano gratuito do Supabase e do EmailJS chega perfeitamente para o volume de uma loja pequena. Se um dia tiveres centenas de encomendas por dia, terás de mudar para o plano pago (poucos euros/mês).
- Guarda a password da base de dados Supabase e o teu login de admin num local seguro.

Qualquer dúvida durante a configuração, diz-me o passo onde ficaste preso que ajudo a resolver.
