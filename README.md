# 🖨️ In.printing.lab — E-commerce & Gestão de Encomendas

<div align="center">
  <img src="ln.png" alt="In.printing.lab Logo" width="150"/>
  <p><strong>Catálogo de peças de impressão 3D, personalização e gestão de pedidos online.</strong></p>
</div>

---

## 📖 Sobre o Projeto
Uma solução completa, leve e responsiva criada à medida para a gestão de encomendas de impressão 3D. Este projeto integra uma montra de produtos interativa (storefront), um sistema de checkout com validação (2FA) por email e um painel de administração privado para acompanhamento da produção.

O sistema foi desenhado com um **fallback inteligente**: caso a base de dados não esteja configurada, o site transita automaticamente para um modo de encomenda direta via WhatsApp, garantindo que nunca se perdem vendas.

## ✨ Funcionalidades Principais

### 🛍️ Storefront (Para Clientes)
* **Catálogo Dinâmico:** Grelha de produtos responsiva com categorias, pesquisa em tempo real e visualização detalhada.
* **Carrossel de Imagens:** Suporte para múltiplas imagens por produto com navegação por swipe (mobile) e setas (desktop).
* **Personalização Avançada:** Campos de input dinâmicos para seleção de cores, nomes e opções (essencial para impressão 3D).
* **Carrinho de Compras:** Gestão intuitiva de itens, quantidades e cálculo de totais.
* **Sistema de Confirmação por Email:** Para evitar spam e pedidos falsos, o cliente recebe um código de 6 dígitos via email para confirmar a encomenda.
* **Consulta de Estado:** Os clientes podem verificar o estado do seu pedido (Ex: "Em Produção", "Pronto") inserindo o número da encomenda e o email.

### 🔐 Painel de Administração (Para o Dono)
* **Autenticação Segura:** Login protegido gerido pelo Supabase Auth.
* **Dashboard Resumo:** Estatísticas rápidas de encomendas pendentes, em produção e confirmadas hoje.
* **Gestão de Estados:** Atualização do ciclo de vida da encomenda (Aguarda confirmação ➔ Confirmada ➔ Em produção ➔ Pronta ➔ Entregue).
* **Gestão de Clientes:** Acesso rápido aos dados do cliente, notas internas e botão para contacto direto via WhatsApp.

## 🛠️ Stack Tecnológica

* **Frontend:** HTML5, CSS3, Vanilla JavaScript (Sem frameworks pesadas para máxima velocidade).
* **Styling:** [Tailwind CSS](https://tailwindcss.com/) (via CDN).
* **Tipografia:** Google Fonts (Space Grotesk & Inter).
* **Base de Dados & Backend:** [Supabase](https://supabase.com/) (PostgreSQL, Row Level Security, RPCs, Auth).
* **Serviço de Email:** [EmailJS](https://www.emailjs.com/) (Envio de templates de confirmação diretamente do frontend).

## 📂 Estrutura de Ficheiros

```text
📦 ln-3d-printing-lab-website
 ┣ 📜 index.html              # Página principal (Catálogo, Carrinho, Checkout)
 ┣ 📜 admin.html              # Painel de Administração protegido
 ┣ 📜 config.js               # Ficheiro de configurações (Chaves de API)
 ┣ 📜 supabase-schema.sql     # Script SQL para criar tabelas, políticas e funções (RPCs)
 ┣ 📜 CONFIGURACAO.md         # Guia passo-a-passo para ligar o Supabase e EmailJS
 ┣ 🖼️ ln.png                  # Logótipo da loja
 ┗ 📁 [Pastas de Produtos]    # Imagens dos produtos organizadas por pastas
```

## 🚀 Como Configurar e Instalar

O site está desenhado para funcionar de imediato de forma simplificada (via WhatsApp). Para desbloquear o sistema de gestão completo, segue estes passos:

1. **Configurar a Base de Dados:**
   * Cria um projeto no [Supabase](https://supabase.com/).
   * Executa o código do ficheiro `supabase-schema.sql` no SQL Editor do teu projeto.
   * Cria o teu utilizador administrador na secção *Authentication*.

2. **Configurar o Envio de Emails:**
   * Cria uma conta no [EmailJS](https://www.emailjs.com/) e liga o teu serviço de email.
   * Cria um template de confirmação conforme indicado no `CONFIGURACAO.md`.

3. **Ligar as APIs:**
   * Abre o ficheiro `config.js` e preenche as variáveis `SUPABASE_URL`, `SUPABASE_ANON_KEY` e as chaves do `EmailJS`.

*(Para instruções mais detalhadas, consulta o ficheiro `CONFIGURACAO.md` incluído no projeto).*

## 🌐 Deploy (Publicação)

Como o projeto é 100% *Client-Side* (estático) conjugado com APIs externas, pode ser alojado de forma totalmente gratuita e rápida:

### Via Netlify (Recomendado)
1. Vai a [Netlify](https://www.netlify.com/) e faz login.
2. Navega até **Add new site** > **Deploy manually**.
3. Arrasta a pasta completa do projeto para a área indicada.
4. O teu site estará online em segundos. Podes posteriormente ligar um domínio personalizado (ex: `inprintinglab.pt`).

### Via GitHub Pages
1. Faz push desta pasta para um repositório no GitHub.
2. Vai a **Settings** > **Pages**.
3. Seleciona a *branch* principal (ex: `main`) e grava.
4. O site ficará disponível no teu domínio `.github.io`.

---
<div align="center">
  <p>Desenvolvido para In.printing.lab</p>
</div>