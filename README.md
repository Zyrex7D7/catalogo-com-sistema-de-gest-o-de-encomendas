# ln-3d-printing-lab-website

Site da In.printing.lab: catálogo de peças de impressão 3D com carrinho, encomenda online com **confirmação por código de email**, e um **painel de administração** para o dono processar as encomendas.

## Ficheiros

- `index.html` — site público (catálogo, carrinho, checkout com confirmação).
- `admin.html` — painel privado do dono (login + gestão de encomendas).
- `config.js` — onde colas as tuas chaves do Supabase e do EmailJS.
- `supabase-schema.sql` — script para criar a base de dados no Supabase.
- `CONFIGURACAO.md` — guia passo-a-passo para ligar tudo (20-30 min, sem programação).
- `ln.png` — logótipo.
- Pastas com o nome de cada produto — fotos do catálogo.

## Início rápido

O site funciona imediatamente tal como está (encomenda direta por WhatsApp). Para ativar o email de confirmação automática e o painel de admin, segue o `CONFIGURACAO.md`.
