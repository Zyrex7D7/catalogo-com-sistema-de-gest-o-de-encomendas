-- =========================================================
-- In.printing.lab — esquema da base de dados (Supabase)
-- Copia TODO este ficheiro e cola no Supabase: SQL Editor > New query > Run
-- =========================================================

-- Extensão necessária para gerar códigos aleatórios
create extension if not exists pgcrypto;

-- ---------------------------------------------------------
-- Tabela principal de encomendas
-- ---------------------------------------------------------
create table if not exists orders (
    id uuid primary key default gen_random_uuid(),
    order_number text unique not null,
    customer_name text not null,
    customer_email text not null,
    customer_phone text,
    items jsonb not null,
    total numeric(10,2) not null,
    status text not null default 'pending_confirmation'
        check (status in (
            'pending_confirmation', -- aguarda o cliente confirmar o email
            'confirmed',            -- cliente confirmou, aguarda o dono aceitar
            'in_production',        -- em produção
            'ready',                -- pronta para entrega/levantamento
            'delivered',            -- entregue
            'cancelled',            -- cancelada (por erro, duplicada, etc.)
            'expired'               -- código expirou e nunca foi confirmada
        )),
    confirmation_code text,
    confirmation_expires_at timestamptz,
    confirmation_attempts int not null default 0,
    confirmed_at timestamptz,
    admin_notes text,
    created_at timestamptz not null default now()
);

create index if not exists idx_orders_status on orders(status);
create index if not exists idx_orders_email on orders(customer_email);
create index if not exists idx_orders_created on orders(created_at desc);

alter table orders enable row level security;

-- Ninguém pode ler/escrever a tabela diretamente à exceção do admin autenticado.
-- Os clientes só interagem através das funções abaixo (mais seguro do que
-- abrir INSERT/UPDATE/SELECT livres com a chave pública).

drop policy if exists "admin_acesso_total" on orders;
create policy "admin_acesso_total"
    on orders for all
    to authenticated
    using (true)
    with check (true);

-- ---------------------------------------------------------
-- Função: criar encomenda (telefone obrigatório)
-- Gera número de encomenda + código de confirmação de 6 dígitos.
-- Corre com privilégios do dono da função (contorna RLS de forma controlada).
-- ---------------------------------------------------------
create or replace function create_order(
    p_customer_name text,
    p_customer_email text,
    p_customer_phone text,
    p_items jsonb,
    p_total numeric
)
returns table(order_number text, confirmation_code text)
language plpgsql
security definer
set search_path = public
as $$
declare
    v_order_number text;
    v_code text;
    v_recent_count int;
begin
    -- validações básicas
    if p_customer_name is null or length(trim(p_customer_name)) < 2 then
        raise exception 'NOME_INVALIDO';
    end if;
    if p_customer_email is null or p_customer_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
        raise exception 'EMAIL_INVALIDO';
    end if;

    -- validação do telemóvel (mínimo 9 caracteres)
    if p_customer_phone is null or length(trim(p_customer_phone)) < 9 then
        raise exception 'TELEFONE_INVALIDO';
    end if;

    if p_items is null or jsonb_array_length(p_items) = 0 then
        raise exception 'CARRINHO_VAZIO';
    end if;

    -- anti-duplicação: bloqueia o mesmo email a criar >3 encomendas em 10 min
    select count(*) into v_recent_count
    from orders
    where customer_email = p_customer_email
      and created_at > now() - interval '10 minutes';

    if v_recent_count >= 3 then
        raise exception 'DEMASIADAS_ENCOMENDAS';
    end if;

    v_order_number := 'LN-' || to_char(now(), 'YYMMDD') || '-' || lpad(floor(random()*1000)::text, 3, '0');
    v_code := lpad(floor(random()*1000000)::text, 6, '0');

    insert into orders(order_number, customer_name, customer_email, customer_phone, items, total,
                        confirmation_code, confirmation_expires_at)
    values (v_order_number, trim(p_customer_name), lower(trim(p_customer_email)), p_customer_phone, p_items, p_total,
            v_code, now() + interval '15 minutes');

    return query select v_order_number, v_code;
end;
$$;

-- ---------------------------------------------------------
-- Função: confirmar encomenda com o código recebido por email
-- ---------------------------------------------------------
create or replace function confirm_order(
    p_order_number text,
    p_code text
)
returns text -- 'ok' | 'codigo_errado' | 'expirado' | 'demasiadas_tentativas' | 'nao_encontrada'
language plpgsql
security definer
set search_path = public
as $$
declare
    v_row orders%rowtype;
begin
    select * into v_row from orders where order_number = p_order_number;

    if not found then
        return 'nao_encontrada';
    end if;

    if v_row.status <> 'pending_confirmation' then
        return 'ok'; -- já estava confirmada; idempotente
    end if;

    if v_row.confirmation_attempts >= 5 then
        return 'demasiadas_tentativas';
    end if;

    if now() > v_row.confirmation_expires_at then
        update orders set status = 'expired' where id = v_row.id;
        return 'expirado';
    end if;

    if v_row.confirmation_code <> p_code then
        update orders set confirmation_attempts = confirmation_attempts + 1 where id = v_row.id;
        return 'codigo_errado';
    end if;

    update orders
    set status = 'confirmed', confirmed_at = now()
    where id = v_row.id;

    return 'ok';
end;
$$;

-- ---------------------------------------------------------
-- Função: reenviar código (gera um novo código e nova validade)
-- ---------------------------------------------------------
create or replace function resend_code(p_order_number text)
returns text -- devolve o novo código, para o site o enviar por EmailJS
language plpgsql
security definer
set search_path = public
as $$
declare
    v_code text;
    v_row orders%rowtype;
begin
    select * into v_row from orders where order_number = p_order_number;
    if not found or v_row.status <> 'pending_confirmation' then
        raise exception 'PEDIDO_INVALIDO';
    end if;

    v_code := lpad(floor(random()*1000000)::text, 6, '0');

    update orders
    set confirmation_code = v_code,
        confirmation_expires_at = now() + interval '15 minutes',
        confirmation_attempts = 0
    where id = v_row.id;

    return v_code;
end;
$$;

-- ---------------------------------------------------------
-- Função: o cliente consultar UMA encomenda específica (por número + email)
-- Devolve também os itens e o código, para poderes retomar a confirmação.
-- ---------------------------------------------------------
drop function if exists get_order_status(text, text);

create or replace function get_order_status(p_order_number text, p_email text)
returns table(status text, order_number text, total numeric, created_at timestamptz, items jsonb, confirmation_code text)
language plpgsql
security definer
set search_path = public
as $$
begin
    return query
    select o.status, o.order_number, o.total, o.created_at, o.items, o.confirmation_code
    from orders o
    where o.order_number = p_order_number
      and o.customer_email = lower(trim(p_email));
end;
$$;

-- ---------------------------------------------------------
-- Função: o cliente consultar TODAS as encomendas feitas com aquele email
-- ---------------------------------------------------------
create or replace function get_customer_orders(p_email text)
returns table(status text, order_number text, total numeric, created_at timestamptz, items jsonb, confirmation_code text)
language plpgsql
security definer
set search_path = public
as $$
begin
    return query
    select o.status, o.order_number, o.total, o.created_at, o.items, o.confirmation_code
    from orders o
    where o.customer_email = lower(trim(p_email))
    order by o.created_at desc; -- mostra as mais recentes primeiro
end;
$$;

-- ---------------------------------------------------------
-- Função: o cliente cancelar uma encomenda ainda pendente de confirmação
-- ---------------------------------------------------------
create or replace function cancel_pending_order(p_order_number text, p_email text)
returns text -- 'ok' | 'nao_encontrada' | 'nao_pendente'
language plpgsql
security definer
set search_path = public
as $$
declare
    v_row orders%rowtype;
begin
    select * into v_row from orders
    where order_number = p_order_number and customer_email = lower(trim(p_email));

    if not found then return 'nao_encontrada'; end if;
    if v_row.status <> 'pending_confirmation' then return 'nao_pendente'; end if;

    update orders set status = 'cancelled' where id = v_row.id;
    return 'ok';
end;
$$;

-- Permite a qualquer visitante (chave anónima) executar estas funções.
-- É seguro: elas próprias validam tudo o que é preciso lá dentro.
grant execute on function create_order to anon;
grant execute on function confirm_order to anon;
grant execute on function resend_code to anon;
grant execute on function get_order_status to anon;
grant execute on function get_customer_orders to anon;
grant execute on function cancel_pending_order to anon;

-- =========================================================
-- Catálogo de produtos (gerido a partir do admin.html)
-- =========================================================

create table if not exists products (
    id uuid primary key default gen_random_uuid(),
    nome text not null,
    descricao text not null default '',
    preco numeric(10,2) not null default 0,
    categoria text not null default 'Geral',
    fotos jsonb not null default '[]'::jsonb,        -- array de URLs/caminhos das fotos
    personalizacao jsonb not null default '[]'::jsonb, -- array de campos { label, placeholder } ou { label, tipo:'select', opcoes:[...] }
    ordem int not null default 0,                      -- ordem de exibição no catálogo
    ativo boolean not null default true,                -- desativar em vez de apagar, se quiseres esconder sem perder dados
    created_at timestamptz not null default now()
);

create index if not exists idx_products_categoria on products(categoria);
create index if not exists idx_products_ordem on products(ordem);

alter table products enable row level security;

-- Qualquer visitante (chave anónima) só pode LER produtos ativos.
drop policy if exists "produtos_leitura_publica" on products;
create policy "produtos_leitura_publica"
    on products for select
    to anon, authenticated
    using (ativo = true or auth.role() = 'authenticated');

-- Só o admin autenticado pode criar, editar ou apagar produtos.
drop policy if exists "produtos_gestao_admin" on products;
create policy "produtos_gestao_admin"
    on products for all
    to authenticated
    using (true)
    with check (true);

-- ---------------------------------------------------------
-- Storage: bucket para as fotos dos produtos carregadas pelo admin
-- ---------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('product-photos', 'product-photos', true)
on conflict (id) do nothing;

drop policy if exists "product_photos_leitura_publica" on storage.objects;
create policy "product_photos_leitura_publica"
    on storage.objects for select
    to public
    using (bucket_id = 'product-photos');

drop policy if exists "product_photos_upload_admin" on storage.objects;
create policy "product_photos_upload_admin"
    on storage.objects for insert
    to authenticated
    with check (bucket_id = 'product-photos');

drop policy if exists "product_photos_update_admin" on storage.objects;
create policy "product_photos_update_admin"
    on storage.objects for update
    to authenticated
    using (bucket_id = 'product-photos');

drop policy if exists "product_photos_delete_admin" on storage.objects;
create policy "product_photos_delete_admin"
    on storage.objects for delete
    to authenticated
    using (bucket_id = 'product-photos');

-- =========================================================
-- Depois de correr este script:
-- 1. Vai a Authentication > Users > Add user e cria o teu login de admin.
-- 2. Usa esse email/password para entrares em admin.html.
-- 3. O catálogo passa a vir desta tabela — gere tudo (criar, editar,
--    apagar produtos e fotos) a partir do painel de administração.
-- =========================================================

-- Seed: migra os produtos atualmente fixos no código para a tabela products.
-- Os caminhos das fotos mantêm-se iguais aos de hoje (pasta/ficheiro), por isso
-- não precisas de mexer nas pastas de fotos já publicadas no site.
-- Corre isto SÓ UMA VEZ (se correres duas vezes, os produtos ficam duplicados).
insert into products (nome, descricao, preco, categoria, fotos, personalizacao, ordem) values
('Secador de Capacetes #CSC', 'Secador de capacetes e luvas composto por 3 ventoinhas (uma de 120mm p/ capacete e duas de 60mm p/ luvas). Inclui botão de ligar/desligar e cabo de alimentação. Pode ser personalizada a cor do stand, número e nome. Tempo de entrega: 2 semanas.', 95, 'Auto & SimRacing', '["Secador%20de%20Capacetes%20CSC/ssc1.png","Secador%20de%20Capacetes%20CSC/ssc2.png","Secador%20de%20Capacetes%20CSC/ssc3.png","Secador%20de%20Capacetes%20CSC/ssc4.png"]'::jsonb, '[{"label":"Cor dos pés","placeholder":"ex: preto"},{"label":"Cor da base","placeholder":"ex: preto"},{"label":"Personalização (nome e/ou número)","placeholder":"ex: João, nº 7"}]'::jsonb, 0),
('Secador de Capacetes e Luvas', 'Secador de capacetes e luvas.<br><br>Composto com 3 ventoinhas, uma de 120mm para secar o capacete e duas de 60mm para secar as luvas.<br>Inclui também um botão para ligar e desligar as ventoinhas e o respetivo cabo de alimentação.<br><br>Pode ser escolhida a cor só stand (pés e base) e pode ser incluída uma personalização, por exemplo com número e nome.<br><br>Valor sem personalização: 85€<br>Valor com personalização: 95€<br><br>Tempo previsto desde a encomenda à entrega: duas semanas.', 95, 'Auto & SimRacing', '["Secador%20de%20Capacete%20e%20Luvas/scl1.png","Secador%20de%20Capacete%20e%20Luvas/scl2.png","Secador%20de%20Capacete%20e%20Luvas/scl3.png","Secador%20de%20Capacete%20e%20Luvas/scl4.png","Secador%20de%20Capacete%20e%20Luvas/scl5.png","Secador%20de%20Capacete%20e%20Luvas/scl6.png"]'::jsonb, '[{"label":"Cor dos pés","placeholder":"ex: preto"},{"label":"Cor da base","placeholder":"ex: preto"},{"label":"Personalização (nome e/ou número)","placeholder":"ex: João, nº 7"}]'::jsonb, 1),
('Indicador SimRacing (RPM/Bandeiras)', 'Indicador de mudança, bandeiras e rotação (RPM).<br><br><strong>Compatibilidade:</strong> Assetto Corsa e Competizione, iRacing, rFactor 2, Project CARS 1 e 2, Automobilista 1 e 2, F1 Series (2020-24), Dirt Rally 1 e 2.0, Euro Truck/American Truck Sim, RaceRoom, BeamNG.drive, Forza Horizon 4 e 5, Gran Turismo 7, Live for Speed, WRC, KartKraft.<br><br><strong>Detalhes:</strong> Ligação Micro USB. Cores dos LEDs totalmente personalizáveis.', 30, 'Auto & SimRacing', '["Indicador%20de%20mudan%C3%A7a%20bandeiras%20rpm%20Simracig/sim1.png","Indicador%20de%20mudan%C3%A7a%20bandeiras%20rpm%20Simracig/sim2.png","Indicador%20de%20mudan%C3%A7a%20bandeiras%20rpm%20Simracig/sim3.png","Indicador%20de%20mudan%C3%A7a%20bandeiras%20rpm%20Simracig/sim4.png"]'::jsonb, '[]'::jsonb, 2),
('Bola de Natal - Cão', 'Bola de natal em forma de patinha. Disponível versão com asinhas para homenagem. Personalizada com nome. Diâmetro: 8cm. Escolha a cor da fita.', 2.5, 'Natal', '["Bola%20de%20Natal%20-%20C%C3%A3o/au.png","Bola%20de%20Natal%20-%20C%C3%A3o/auau.png"]'::jsonb, '[{"label":"Nome","placeholder":"ex: Rex"},{"label":"Cor do topo e base","tipo":"select","opcoes":["Dourado","Cinzento","Vermelho"]}]'::jsonb, 3),
('Bola de Natal - Gato', 'Bola de natal em forma de cabeça de gatinho. Disponível com asinhas. Personalizada com nome. Diâmetro: 8cm. Escolha a cor da fita.', 2.5, 'Natal', '["Bola%20de%20Natal%20-%20Gato/miau.png"]'::jsonb, '[{"label":"Nome","placeholder":"ex: Mimi"},{"label":"Cor do topo e base","tipo":"select","opcoes":["Dourado","Cinzento","Vermelho"]}]'::jsonb, 4),
('Bola de Natal - Melhor Auxiliar', 'Bola de natal para mimar os auxiliares. Personalizada com nome. Diâmetro: 8cm. Escolha a cor da fita.', 2.5, 'Natal', '["Bola%20de%20Natal%20-%20Melhor%20Auxiliar/aux1.png","Bola%20de%20Natal%20-%20Melhor%20Auxiliar/aux2.png"]'::jsonb, '[{"label":"Cor do topo e base","tipo":"select","opcoes":["Dourado","Cinzento","Vermelho"]}]'::jsonb, 5),
('Bola de Natal - Professor(a)', 'Bola de natal para mimar os professores(as). Diâmetro: 8cm. Escolha a cor da fita.', 2.5, 'Natal', '["Bola%20de%20Natal%20-%20Melhor%20Professor(a)/prof1.png","Bola%20de%20Natal%20-%20Melhor%20Professor(a)/prof2.png"]'::jsonb, '[{"label":"Cor do topo e base","tipo":"select","opcoes":["Dourado","Cinzento","Vermelho"]}]'::jsonb, 6),
('Bola de Natal - Educador(a)', 'Bola de Natal para o mimar os(as) Educadores(as) ! 🤍Escolha também a cor da fita para melhor condizer com a sua árvore de natal!Diametro de 8cm.', 2.5, 'Natal', '["Bola%20de%20Natal%20-%20Melhor%20Educador(a)/educa1.png","Bola%20de%20Natal%20-%20Melhor%20Educador(a)/educa2.png"]'::jsonb, '[{"label":"Cor do topo e base","tipo":"select","opcoes":["Dourado","Cinzento","Vermelho"]}]'::jsonb, 7),
('Bola de Natal - Boas Festas', 'Bola de Natal para quem não pode passar sem oferecer uma lembrança! 🤍Escolha também a cor da fita para melhor condizer com a sua árvore de natal!Diametro de 8cm.', 2.5, 'Natal', '["Bola%20Feliz%20Natal%20Boas%20Festas/festa1.png","Bola%20Feliz%20Natal%20Boas%20Festas/festa2.png"]'::jsonb, '[{"label":"Cor do topo e base","tipo":"select","opcoes":["Dourado","Cinzento","Vermelho"]}]'::jsonb, 8),
('Bola de Natal Personalizada', 'Bola de Natal personalizada.<br><br>Também disponível versão com asinhas para homenagear os entes queridos 🤍<br><br>Personalizada com um nome à escolha.<br>Escolha também a cor da fita para melhor condizer com a sua árvore de natal!<br><br>Diâmetro de 8cm.', 2.5, 'Natal', '["Bola%20de%20Natal%20Personalizada/personal.png"]'::jsonb, '[{"label":"Nome","placeholder":"ex: Solange"},{"label":"Com asinhas (para homenagem)","tipo":"select","opcoes":["Sim","Não"]},{"label":"Cor do topo e base","tipo":"select","opcoes":["Dourado","Cinzento","Vermelho"]}]'::jsonb, 9),
('Bola com Fotografia', 'Bola personalizada com fotografia à sua escolha. Iluminada através das luzes da sua árvore de Natal.', 10, 'Natal', '["Bola%20com%20Fotografia/ft1.png","Bola%20com%20Fotografia/ft2.png","Bola%20com%20Fotografia/ft3.png"]'::jsonb, '[{"label":"Detalhes da fotografia (envia a foto depois por WhatsApp)","placeholder":"ex: foto de família de Natal"}]'::jsonb, 10),
('Caixa de Memórias', 'Caixa de memórias que leva até 3 fotografias. É possível escolher a cor da armação.', 35, 'Decoração & Presentes', '["Caixa%20de%20mem%C3%B3rias/1.png","Caixa%20de%20mem%C3%B3rias/2.png"]'::jsonb, '[{"label":"Cor da armação","placeholder":"ex: natural"},{"label":"Detalhes das fotografias (até 3, envia depois por WhatsApp)","placeholder":"ex: fotos de família"}]'::jsonb, 11),
('Nome Infinito', 'Peça decorativa personalizável com nomes. Várias cores disponíveis.', 15, 'Decoração & Presentes', '["Nome%20infinito/nome_infinito.png"]'::jsonb, '[{"label":"Nome","placeholder":"ex: Marta & João"},{"label":"Cor","placeholder":"ex: dourado"}]'::jsonb, 12),
('Base Monstera', 'Conjunto composto por 4 folhas de monstera com base. Dimensão folha: 8cm x 10cm x 0,4cm. Dimensão base: 8,5cm x 10,5cm x 2,2cm.', 10, 'Decoração & Presentes', '["Base%20coposvelas%20monsteras/base.png"]'::jsonb, '[{"label":"Cor","placeholder":"ex: verde"}]'::jsonb, 13),
('Vaso Caveira', 'Vaso decorativo para plantas ou para guardar chaves. Disponível em várias cores.', 12, 'Decoração & Presentes', '["Caveiras%20vaso/cav1.png","Caveiras%20vaso/cav2.png"]'::jsonb, '[{"label":"Cor","placeholder":"ex: preto"}]'::jsonb, 14),
('Luminária NameLed', 'Luminária personalizada com iluminação LED controlável com comando remoto. Permite até quatro cores diferentes. Dimensão máxima: 25cm x 25cm.', 30, 'Decoração & Presentes', '["NameLed/nl1.png","NameLed/nl2.png"]'::jsonb, '[{"label":"Nome","placeholder":"ex: Beatriz"},{"label":"Cor(es) LED","placeholder":"ex: azul e branco"}]'::jsonb, 15);
