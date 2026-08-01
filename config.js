/*
  CONFIGURAÇÃO — In.printing.lab
  ================================
  Preenche os valores abaixo depois de seguires o guia CONFIGURACAO.md.
  Enquanto não preencheres SUPABASE_URL e SUPABASE_ANON_KEY, o site funciona
  na mesma (catálogo + WhatsApp), mas SEM confirmação por email nem painel
  de encomendas — fica tudo pronto a ligar assim que colares as chaves aqui.
*/

const CONFIG = {
    // --- Supabase (base de dados das encomendas + login do admin) ---
    SUPABASE_URL: "https://shsqdehjtuknxfalexqy.supabase.co",           // ex: "https://abcdefgh.supabase.co"
    SUPABASE_ANON_KEY: "sb_publishable_0uCOFv-r3Zdv3yOuBdWvEA_2toOfN4F",      // a "anon public key" do teu projeto Supabase

    // --- EmailJS (envio do código de confirmação por email) ---
    EMAILJS_PUBLIC_KEY: "vYjj34J0rHyW7yZKd",     // Account > General > Public Key
    EMAILJS_SERVICE_ID: "service_jf6x9zs",     // Email Services > o teu serviço
    EMAILJS_TEMPLATE_ID: "template_60pkqlg",    // Email Templates > o teu template

    // --- WhatsApp do dono/loja (aviso rápido, além do email) ---
    WHATSAPP_NUMERO: "351215959525",

    // --- Identidade da loja ---
    NOME_LOJA: "In.printing.lab",
    EMAIL_SUPORTE: "geral@inprintinglab.pt"
};
