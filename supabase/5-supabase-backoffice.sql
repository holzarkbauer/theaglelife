-- ============================================================
--  Semillas de Identidad · paso 5: Backoffice (solo administradores)
--  Usuarios, ingresos, productos, tokens de IA y ajustes.
--  Córrelo después de 4-supabase-tienda.sql · SQL Editor → + New → pegar → Run
-- ============================================================

-- ---------- Ajustes editables desde el backoffice ----------
create table if not exists public.app_settings (
  key        text primary key,
  value      jsonb not null,
  updated_at timestamptz not null default now()
);
alter table public.app_settings enable row level security;
drop policy if exists "ajustes: admin" on public.app_settings;
create policy "ajustes: admin" on public.app_settings for all to authenticated using (public.is_admin()) with check (public.is_admin());
grant select, insert, update on public.app_settings to authenticated;
insert into public.app_settings (key, value) values
  ('free_pool_tokens', '20000000'),
  ('monthly_tokens', '[30000, 100000, 250000, 500000]'),
  ('user_goal', '50000')
on conflict (key) do nothing;

-- ---------- Resumen general ----------
create or replace function public.admin_overview()
returns json language plpgsql security definer set search_path = public, auth stable as $$
declare
  m date := date_trunc('month', now())::date;
  r json;
begin
  if not public.is_admin() then raise exception 'Solo administradores'; end if;
  select json_build_object(
    'users_total',   (select count(*) from auth.users),
    'users_7d',      (select count(*) from auth.users where created_at > now() - interval '7 days'),
    'users_30d',     (select count(*) from auth.users where created_at > now() - interval '30 days'),
    'users_prev_30d',(select count(*) from auth.users where created_at between now() - interval '60 days' and now() - interval '30 days'),
    'active_7d',     (select count(distinct user_id) from public.app_docs where updated_at > now() - interval '7 days'),
    'active_30d',    (select count(distinct user_id) from public.app_docs where updated_at > now() - interval '30 days'),
    'tiers',         (select coalesce(json_object_agg(t, c), '{}'::json) from (select public.tier_of(u.id) t, count(*) c from auth.users u group by 1) x),
    'plan_revenue',  (select coalesce(sum(amount), 0) from public.memberships where coalesce(charge_id, '') <> 'cortesia'),
    'plan_sales',    (select count(*) from public.memberships where coalesce(charge_id, '') <> 'cortesia'),
    'plan_month',    (select coalesce(sum(amount), 0) from public.memberships where coalesce(charge_id, '') <> 'cortesia' and starts_at >= m),
    'store_revenue', (select coalesce(sum(amount), 0) from public.book_orders),
    'store_author',  (select coalesce(sum(author_share_cents), 0) from public.book_orders),
    'store_sales',   (select count(*) from public.book_orders),
    'store_month',   (select coalesce(sum(amount), 0) from public.book_orders where created_at >= m),
    'tokens_month',  (select coalesce(sum(tokens), 0) from public.ai_tokens where month = m),
    'tokens_free',   (select coalesce(max(free_tokens), 0) from public.ai_global where month = m),
    'tokens_tier',   (select coalesce(json_object_agg(t, s), '{}'::json) from (select public.tier_of(user_id) t, sum(tokens) s from public.ai_tokens where month = m group by 1) x),
    'ai_users_month',(select count(*) from public.ai_tokens where month = m and tokens > 0),
    'user_books',    (select count(*) from public.user_books),
    'library_books', (select count(*) from public.library_books),
    'store_books',   (select count(*) from public.store_books where active),
    'reviews_avg',   (select round(avg(stars)::numeric, 2) from public.reviews where status = 'approved'),
    'reviews_count', (select count(*) from public.reviews where status = 'approved'),
    'reviews_pending',(select count(*) from public.reviews where status = 'pending'),
    'expiring_14d',  (select count(*) from public.memberships where plan in ('eagle','eagle_plus') and expires_at between now() and now() + interval '14 days'),
    'settings',      (select coalesce(json_object_agg(key, value), '{}'::json) from public.app_settings)
  ) into r;
  return r;
end; $$;
grant execute on function public.admin_overview() to authenticated;

-- ---------- Series para gráficos ----------
create or replace function public.admin_series(days int default 30, months int default 6)
returns json language plpgsql security definer set search_path = public, auth stable as $$
declare r json;
begin
  if not public.is_admin() then raise exception 'Solo administradores'; end if;
  select json_build_object(
    'signups', (select json_agg(json_build_object('d', g::date, 'n', coalesce(u.n, 0)) order by g)
                from generate_series(current_date - (least(greatest(days,7),365) - 1), current_date, interval '1 day') g
                left join (select created_at::date dd, count(*) n from auth.users group by 1) u on u.dd = g::date),
    'revenue', (select json_agg(json_build_object('m', g::date,
                  'plans', coalesce((select sum(amount) from public.memberships where coalesce(charge_id,'') <> 'cortesia' and date_trunc('month', starts_at) = g), 0),
                  'store', coalesce((select sum(amount) from public.book_orders where date_trunc('month', created_at) = g), 0)) order by g)
                from generate_series(date_trunc('month', now()) - make_interval(months => least(greatest(months,1),24) - 1), date_trunc('month', now()), interval '1 month') g)
  ) into r;
  return r;
end; $$;
grant execute on function public.admin_series(int, int) to authenticated;

-- ---------- Usuarios (búsqueda y orden) ----------
create or replace function public.admin_users(q text default '', sort text default 'recent', lim int default 50, off int default 0)
returns table (id uuid, email text, username text, created_at timestamptz, last_seen timestamptz, tier int,
               expires timestamptz, tokens_month bigint, books int, spent_cents bigint)
language plpgsql security definer set search_path = public, auth stable as $$
begin
  if not public.is_admin() then raise exception 'Solo administradores'; end if;
  return query
  select u.id, u.email::text, p.username, u.created_at,
         (select max(d.updated_at) from public.app_docs d where d.user_id = u.id),
         public.tier_of(u.id),
         (select max(mm.expires_at) from public.memberships mm where mm.user_id = u.id and mm.expires_at > now()),
         coalesce((select t.tokens from public.ai_tokens t where t.user_id = u.id and t.month = date_trunc('month', now())::date), 0)::bigint,
         (select count(*)::int from public.user_books b where b.user_id = u.id),
         (coalesce((select sum(mm.amount) from public.memberships mm where mm.user_id = u.id and coalesce(mm.charge_id,'') <> 'cortesia'), 0)
          + coalesce((select sum(o.amount) from public.book_orders o where o.user_id = u.id), 0))::bigint
  from auth.users u left join public.profiles p on p.id = u.id
  where q = '' or u.email ilike '%' || q || '%' or p.username ilike '%' || q || '%'
  order by
    case when sort = 'tokens' then coalesce((select t.tokens from public.ai_tokens t where t.user_id = u.id and t.month = date_trunc('month', now())::date), 0) end desc nulls last,
    case when sort = 'spent' then (coalesce((select sum(mm.amount) from public.memberships mm where mm.user_id = u.id and coalesce(mm.charge_id,'') <> 'cortesia'), 0)
          + coalesce((select sum(o.amount) from public.book_orders o where o.user_id = u.id), 0)) end desc nulls last,
    u.created_at desc
  limit least(greatest(lim, 1), 1000) offset greatest(off, 0);
end; $$;
grant execute on function public.admin_users(text, text, int, int) to authenticated;

-- ---------- Ventas recientes (planes + tienda) ----------
create or replace function public.admin_sales(lim int default 30)
returns table (kind text, sold_at timestamptz, username text, email text, item text, amount int, currency text, author_share int, charge_id text)
language plpgsql security definer set search_path = public, auth stable as $$
begin
  if not public.is_admin() then raise exception 'Solo administradores'; end if;
  return query
  select * from (
    select 'plan'::text, m.starts_at, p.username, u.email::text,
           case m.plan when 'bootcamper' then 'Plan Bootcamper' when 'eagle' then 'Plan Eagle' else 'Plan Eagle Plus' end,
           m.amount, m.currency, null::int, m.charge_id
      from public.memberships m join auth.users u on u.id = m.user_id left join public.profiles p on p.id = m.user_id
     where coalesce(m.charge_id,'') <> 'cortesia'
    union all
    select 'libro', o.created_at, p.username, u.email::text, coalesce(b.title, 'Libro'), o.amount, o.currency, o.author_share_cents, o.charge_id
      from public.book_orders o join auth.users u on u.id = o.user_id left join public.profiles p on p.id = o.user_id
      left join public.store_books b on b.id = o.book_id
  ) s order by 2 desc limit least(greatest(lim,1),500);
end; $$;
grant execute on function public.admin_sales(int) to authenticated;

-- ---------- Planes Eagle por vencer (para recordar renovar) ----------
create or replace function public.admin_expiring(days int default 14)
returns table (username text, email text, plan text, expires timestamptz)
language plpgsql security definer set search_path = public, auth stable as $$
begin
  if not public.is_admin() then raise exception 'Solo administradores'; end if;
  return query
  select p.username, u.email::text, m.plan, m.expires_at
    from public.memberships m join auth.users u on u.id = m.user_id left join public.profiles p on p.id = m.user_id
   where m.plan in ('eagle','eagle_plus') and m.expires_at between now() and now() + make_interval(days => days)
   order by m.expires_at;
end; $$;
grant execute on function public.admin_expiring(int) to authenticated;

-- ---------- Dar un plan a mano (cortesía, becas, pagos por transferencia) ----------
create or replace function public.admin_grant(target uuid, plan_id text, days int default 90, note text default 'cortesia')
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Solo administradores'; end if;
  if plan_id not in ('bootcamper','eagle','eagle_plus') then raise exception 'Plan no válido'; end if;
  insert into public.memberships (user_id, plan, charge_id, amount, currency, expires_at)
  values (target, plan_id, coalesce(nullif(note,''),'cortesia'), 0, 'USD',
          case when plan_id = 'bootcamper' then null else now() + make_interval(days => greatest(days,1)) end);
end; $$;
grant execute on function public.admin_grant(uuid, text, int, text) to authenticated;

notify pgrst, 'reload schema';
