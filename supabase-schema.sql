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
-- Os clientes só interagem através das duas funções abaixo (mais seguro do que
-- abrir INSERT/UPDATE/SELECT livres com a chave pública).

drop policy if exists "admin_acesso_total" on orders;
create policy "admin_acesso_total"
    on orders for all
    to authenticated
    using (true)
    with check (true);

-- ---------------------------------------------------------
-- Função: criar encomenda
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
-- Função: o cliente consultar o estado da própria encomenda
-- (não expõe a tabela toda, só o essencial, por número + email)
-- ---------------------------------------------------------
create or replace function get_order_status(p_order_number text, p_email text)
returns table(status text, order_number text, total numeric, created_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
begin
    return query
    select o.status, o.order_number, o.total, o.created_at
    from orders o
    where o.order_number = p_order_number
      and o.customer_email = lower(trim(p_email));
end;
$$;

-- Permite a qualquer visitante (chave anónima) executar estas 4 funções.
-- É seguro: elas próprias validam tudo o que é preciso lá dentro.
grant execute on function create_order to anon;
grant execute on function confirm_order to anon;
grant execute on function resend_code to anon;
grant execute on function get_order_status to anon;

-- =========================================================
-- Depois de correr este script:
-- 1. Vai a Authentication > Users > Add user e cria o teu login de admin.
-- 2. Usa esse email/password para entrares em admin.html.
-- =========================================================
