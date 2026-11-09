-- ============================================================
--  Semillas de Identidad · paso 6 (versión 10)
--  Planes mensuales con prueba de 7 días, IA Haiku + Opus, guías, tienda tipo Amazon,
--  muestras privadas de libros y portal de autores.
--  Córrelo después de los pasos 1 a 5 · SQL Editor → + New → pegar todo → Run
-- ============================================================

-- ---------- 1. Planes nuevos ----------
--  0 Gratis (sin IA) · 1 Prueba 7 días ($1) · 2 Semillas ($7/mes) · 3 Eagle ($17/mes)
--  Los planes antiguos siguen valiendo: bootcamper = 1, eagle = 2, eagle_plus = 3
alter table public.memberships drop constraint if exists memberships_plan_check;
alter table public.memberships add constraint memberships_plan_check
  check (plan in ('bootcamper','eagle','eagle_plus','prueba','semillas','eagle_mes'));
alter table public.memberships add column if not exists subscription_id text;

create or replace function public.tier_of(uid uuid)
returns int language sql security definer set search_path = public stable as $$
  select coalesce(max(case plan
      when 'bootcamper' then 1 when 'prueba' then 1
      when 'eagle' then 2 when 'semillas' then 2
      when 'eagle_plus' then 3 when 'eagle_mes' then 3 else 0 end), 0)
  from public.memberships where user_id = uid and (expires_at is null or expires_at > now());
$$;
revoke all on function public.tier_of(uuid) from public, anon, authenticated;
grant execute on function public.tier_of(uuid) to service_role;

-- Suscripciones de Culqi (cobro automático mensual)
create table if not exists public.subscriptions (
  id              bigserial primary key,
  user_id         uuid not null references auth.users(id) on delete cascade,
  plan            text not null check (plan in ('semillas','eagle_mes')),
  culqi_customer  text,
  culqi_card      text,
  culqi_sub       text unique,
  status          text not null default 'active',     -- active · canceled · failed
  trial           boolean not null default false,
  next_billing    timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists subscriptions_user_idx on public.subscriptions(user_id);
alter table public.subscriptions enable row level security;
drop policy if exists "suscripciones: ver las propias" on public.subscriptions;
create policy "suscripciones: ver las propias" on public.subscriptions for select to authenticated
  using (auth.uid() = user_id or public.is_admin());
grant select on public.subscriptions to authenticated;

create or replace function public.plan_info()
returns json language sql security definer set search_path = public stable as $$
  select json_build_object(
    'tier', public.user_tier(),
    'expires', (select max(expires_at) from public.memberships where user_id = auth.uid() and expires_at > now()),
    'plan', (select plan from public.memberships where user_id = auth.uid() and (expires_at is null or expires_at > now())
             order by expires_at desc nulls first limit 1),
    'sub', (select json_build_object('plan', plan, 'status', status, 'trial', trial, 'next', next_billing)
            from public.subscriptions where user_id = auth.uid() order by created_at desc limit 1));
$$;
grant execute on function public.plan_info() to authenticated;

-- ---------- 2. Datos: tracker y Plan RPM ahora son gratis para todos ----------
drop policy if exists "docs: crear los propios"  on public.app_docs;
drop policy if exists "docs: editar los propios" on public.app_docs;
create policy "docs: crear los propios" on public.app_docs for insert with check (auth.uid() = user_id);
create policy "docs: editar los propios" on public.app_docs for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create or replace function public.book_limit()
returns int language sql security definer set search_path = public stable as $$
  select case public.user_tier() when 0 then 1 when 1 then 2 when 2 then 5 else 100000 end;
$$;

-- ---------- 3. IA: tokens Haiku (conversación) + Opus (razonamiento avanzado) ----------
alter table public.ai_tokens add column if not exists opus bigint not null default 0;
create or replace function public.add_ai_usage(uid uuid, n_haiku bigint, n_opus bigint)
returns json language sql security definer set search_path = public as $$
  insert into public.ai_tokens as t (user_id, month, tokens, opus)
  values (uid, date_trunc('month', now())::date, greatest(n_haiku, 0), greatest(n_opus, 0))
  on conflict (user_id, month) do update
    set tokens = t.tokens + greatest(n_haiku, 0), opus = t.opus + greatest(n_opus, 0)
  returning json_build_object('haiku', t.tokens, 'opus', t.opus);
$$;
revoke all on function public.add_ai_usage(uuid, bigint, bigint) from public, anon, authenticated;
grant execute on function public.add_ai_usage(uuid, bigint, bigint) to service_role;

insert into public.app_settings (key, value) values
  ('monthly_tokens', '[0, 600000, 4000000, 8000000]'::jsonb),
  ('opus_tokens',    '[0, 15000, 115000, 330000]'::jsonb)
on conflict (key) do update set value = excluded.value;

-- ---------- 4. Tienda tipo Amazon: muestras, reseñas por libro y vista privada ----------
alter table public.store_books add column if not exists visibility text not null default 'public';
alter table public.store_books drop constraint if exists store_books_visibility_check;
alter table public.store_books add constraint store_books_visibility_check check (visibility in ('public','private'));
alter table public.store_books add column if not exists subtitle text;
alter table public.store_books add column if not exists sample_pages int not null default 8;
alter table public.store_books add column if not exists category text;

-- Personas invitadas a ver un libro privado (por ejemplo, la editorial que debe aprobarlo)
create table if not exists public.store_viewers (
  book_id uuid not null references public.store_books(id) on delete cascade,
  email   text not null,
  primary key (book_id, email)
);
alter table public.store_viewers enable row level security;
drop policy if exists "invitados: solo admin" on public.store_viewers;
create policy "invitados: solo admin" on public.store_viewers for all to authenticated using (public.is_admin()) with check (public.is_admin());
grant select, insert, update, delete on public.store_viewers to authenticated;

create or replace function public.can_view_book(bid uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select public.is_admin() or exists (
    select 1 from public.store_viewers v join auth.users u on lower(u.email) = lower(v.email)
    where v.book_id = bid and u.id = auth.uid());
$$;
grant execute on function public.can_view_book(uuid) to anon, authenticated;
create or replace function public.can_view_file(fname text)
returns boolean language plpgsql security definer set search_path = public stable as $$
declare k text := split_part(fname, '.', 1);
begin
  if k !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return false; end if;
  return public.can_view_book(k::uuid);
end; $$;
grant execute on function public.can_view_file(text) to authenticated;

drop policy if exists "tienda: ver catálogo" on public.store_books;
create policy "tienda: ver catálogo" on public.store_books for select to anon, authenticated
  using ((active and visibility = 'public') or public.can_view_book(id));

drop policy if exists "tienda: leer comprados" on storage.objects;
create policy "tienda: leer comprados" on storage.objects for select to authenticated using (
  bucket_id = 'tienda' and (public.is_admin()
    or public.can_view_file(name)
    or exists (select 1 from public.book_orders o where o.user_id = auth.uid() and o.book_id::text = split_part(name, '.', 1))));

-- Muestra gratuita (primeras páginas): cualquiera puede leerla
insert into storage.buckets (id, name, public) values ('muestras', 'muestras', true) on conflict (id) do nothing;
drop policy if exists "muestras: leer" on storage.objects;
drop policy if exists "muestras: admin sube" on storage.objects;
drop policy if exists "muestras: admin borra" on storage.objects;
create policy "muestras: leer" on storage.objects for select to anon, authenticated using (bucket_id = 'muestras');
create policy "muestras: admin sube" on storage.objects for insert to authenticated with check (bucket_id = 'muestras' and public.is_admin());
create policy "muestras: admin borra" on storage.objects for delete to authenticated using (bucket_id = 'muestras' and public.is_admin());

-- Reseñas de cada libro (solo quien lo compró)
create table if not exists public.book_reviews (
  book_id    uuid not null references public.store_books(id) on delete cascade,
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  username   text,
  stars      int not null check (stars between 1 and 5),
  comment    text check (char_length(comment) <= 600),
  status     text not null default 'pending' check (status in ('pending','approved','hidden')),
  created_at timestamptz not null default now(),
  primary key (book_id, user_id)
);
alter table public.book_reviews enable row level security;
create or replace function public.book_reviews_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    new.status := 'pending';
    new.user_id := auth.uid();
    if not exists (select 1 from public.book_orders o where o.user_id = auth.uid() and o.book_id = new.book_id) then
      raise exception 'Solo quien compró el libro puede reseñarlo';
    end if;
  end if;
  new.username := coalesce((select username from public.profiles where id = new.user_id), new.username);
  return new;
end; $$;
drop trigger if exists book_reviews_guard on public.book_reviews;
create trigger book_reviews_guard before insert or update on public.book_reviews for each row execute function public.book_reviews_guard();
drop policy if exists "reseñas libro: ver" on public.book_reviews;
drop policy if exists "reseñas libro: escribir" on public.book_reviews;
drop policy if exists "reseñas libro: editar" on public.book_reviews;
create policy "reseñas libro: ver" on public.book_reviews for select to anon, authenticated
  using (status = 'approved' or auth.uid() = user_id or public.is_admin());
create policy "reseñas libro: escribir" on public.book_reviews for insert to authenticated with check (auth.uid() = user_id);
create policy "reseñas libro: editar" on public.book_reviews for update to authenticated
  using (auth.uid() = user_id or public.is_admin()) with check (auth.uid() = user_id or public.is_admin());
grant select on public.book_reviews to anon, authenticated;
grant insert, update on public.book_reviews to authenticated;

create or replace view public.book_ratings with (security_invoker = false) as
  select book_id, round(avg(stars)::numeric, 1) as avg, count(*)::int as n
  from public.book_reviews where status = 'approved' group by book_id;
grant select on public.book_ratings to anon, authenticated;

-- ---------- 5. Portal de autores: solicitud + contrato digital ----------
create table if not exists public.author_applications (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid default auth.uid() references auth.users(id) on delete set null,
  full_name      text not null check (char_length(full_name) between 3 and 120),
  organization   text,
  role           text,
  email          text not null check (char_length(email) between 5 and 160),
  phone          text,
  country        text,
  book_titles    text not null check (char_length(book_titles) between 2 and 1000),
  author_pct     int  not null check (author_pct between 10 and 95),
  rights_holder  boolean not null,
  accepted_terms boolean not null check (accepted_terms),
  terms_version  text not null,
  signature      text not null check (char_length(signature) between 3 and 120),
  user_agent     text,
  status         text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at     timestamptz not null default now()
);
alter table public.author_applications enable row level security;
drop policy if exists "autores: enviar" on public.author_applications;
drop policy if exists "autores: ver" on public.author_applications;
drop policy if exists "autores: admin edita" on public.author_applications;
create policy "autores: enviar" on public.author_applications for insert to anon, authenticated
  with check (status = 'pending');
create policy "autores: ver" on public.author_applications for select to authenticated
  using (public.is_admin() or auth.uid() = user_id);
create policy "autores: admin edita" on public.author_applications for update to authenticated
  using (public.is_admin()) with check (public.is_admin());
grant insert on public.author_applications to anon, authenticated;
grant select, update on public.author_applications to authenticated;

-- Seguidores reales para mostrar a las editoriales (solo números, sin datos personales)
create or replace function public.public_stats()
returns json language sql security definer set search_path = public stable as $$
  select json_build_object(
    'users', (select count(*) from auth.users),
    'active_30d', (select count(distinct user_id) from public.app_docs where updated_at > now() - interval '30 days'),
    'reviews_avg', (select round(avg(stars)::numeric, 1) from public.reviews where status = 'approved'),
    'reviews', (select count(*) from public.reviews where status = 'approved'));
$$;
grant execute on function public.public_stats() to anon, authenticated;

-- ---------- 6. Backoffice: datos extra ----------
create or replace function public.admin_extra()
returns json language plpgsql security definer set search_path = public stable as $$
begin
  if not public.is_admin() then raise exception 'Solo administradores'; end if;
  return json_build_object(
    'opus_month', (select coalesce(sum(opus), 0) from public.ai_tokens where month = date_trunc('month', now())::date),
    'subs_active', (select count(*) from public.subscriptions where status = 'active'),
    'subs_by_plan', (select coalesce(json_object_agg(plan, n), '{}'::json) from (select plan, count(*) n from public.subscriptions where status = 'active' group by plan) s),
    'trials_active', (select count(distinct user_id) from public.memberships where plan = 'prueba' and expires_at > now()),
    'author_apps', (select coalesce(json_agg(a order by a.created_at desc), '[]'::json) from (
        select id, full_name, organization, role, email, phone, country, book_titles, author_pct, rights_holder, signature, terms_version, status, created_at
        from public.author_applications order by created_at desc limit 100) a),
    'onboarding', (select coalesce(json_object_agg(k, n), '{}'::json) from (
        select p.k, count(*) n from public.app_docs d, jsonb_array_elements_text(coalesce(d.data->'pains', '[]'::jsonb)) as p(k)
        where d.path = 'onb/main' group by p.k) o));
end; $$;
grant execute on function public.admin_extra() to authenticated;

-- Ventas, vencimientos y cortesías con los planes nuevos
create or replace function public.plan_name(p text)
returns text language sql immutable as $$
  select case p when 'prueba' then 'Prueba 7 días' when 'semillas' then 'Plan Semillas' when 'eagle_mes' then 'Plan Eagle (mensual)'
    when 'bootcamper' then 'Plan Bootcamper' when 'eagle' then 'Plan Eagle (90 días)' when 'eagle_plus' then 'Plan Eagle Plus' else p end;
$$;
create or replace function public.admin_sales(lim int default 30)
returns table (kind text, sold_at timestamptz, username text, email text, item text, amount int, currency text, author_share int, charge_id text)
language plpgsql security definer set search_path = public, auth stable as $$
begin
  if not public.is_admin() then raise exception 'Solo administradores'; end if;
  return query
  select * from (
    select 'plan'::text, m.starts_at, p.username, u.email::text, public.plan_name(m.plan),
           m.amount, m.currency, null::int, m.charge_id
      from public.memberships m join auth.users u on u.id = m.user_id left join public.profiles p on p.id = m.user_id
     where coalesce(m.charge_id,'') <> 'cortesia' and coalesce(m.amount,0) > 0
    union all
    select 'libro', o.created_at, p.username, u.email::text, coalesce(b.title, 'Libro'), o.amount, o.currency, o.author_share_cents, o.charge_id
      from public.book_orders o join auth.users u on u.id = o.user_id left join public.profiles p on p.id = o.user_id
      left join public.store_books b on b.id = o.book_id
  ) s order by 2 desc limit least(greatest(lim,1),500);
end; $$;
grant execute on function public.admin_sales(int) to authenticated;

-- Planes por vencer SIN suscripción activa (hay que escribirles para que renueven)
create or replace function public.admin_expiring(days int default 14)
returns table (username text, email text, plan text, expires timestamptz)
language plpgsql security definer set search_path = public, auth stable as $$
begin
  if not public.is_admin() then raise exception 'Solo administradores'; end if;
  return query
  select p.username, u.email::text, m.plan, m.expires_at
    from public.memberships m join auth.users u on u.id = m.user_id left join public.profiles p on p.id = m.user_id
   where m.plan <> 'bootcamper' and m.expires_at between now() and now() + make_interval(days => days)
     and not exists (select 1 from public.subscriptions s where s.user_id = m.user_id and s.status = 'active')
   order by m.expires_at;
end; $$;
grant execute on function public.admin_expiring(int) to authenticated;

create or replace function public.admin_grant(target uuid, plan_id text, days int default 30, note text default 'cortesia')
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Solo administradores'; end if;
  if plan_id not in ('prueba','semillas','eagle_mes','bootcamper','eagle','eagle_plus') then raise exception 'Plan no válido'; end if;
  insert into public.memberships (user_id, plan, charge_id, amount, currency, expires_at)
  values (target, plan_id, coalesce(nullif(note,''),'cortesia'), 0, 'USD',
          case when plan_id = 'bootcamper' then null else now() + make_interval(days => greatest(days,1)) end);
end; $$;
grant execute on function public.admin_grant(uuid, text, int, text) to authenticated;

notify pgrst, 'reload schema';
