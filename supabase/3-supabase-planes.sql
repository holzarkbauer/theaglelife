-- ============================================================
--  Semillas de Identidad · paso 3: planes, biblioteca, libros PDF y límites de IA
--  (reemplaza a supabase-pagos.sql; córrelo después de supabase-setup.sql y supabase-coach.sql)
--  Supabase → SQL Editor → + New → pegar todo → Run
-- ============================================================

-- ---------- 1. Planes ----------
--  0 Gratis · 1 Bootcamper ($7 pago único) · 2 Eagle ($17 cada 90 días) · 3 Eagle Plus ($27 cada 90 días)
create table if not exists public.memberships (
  id         bigserial primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  plan       text not null check (plan in ('bootcamper','eagle','eagle_plus')),
  charge_id  text,
  amount     int,
  currency   text,
  starts_at  timestamptz not null default now(),
  expires_at timestamptz            -- null = no vence (bootcamper)
);
create index if not exists memberships_user_idx on public.memberships(user_id);
alter table public.memberships enable row level security;
drop policy if exists "planes: ver los propios" on public.memberships;
create policy "planes: ver los propios" on public.memberships for select using (auth.uid() = user_id);
grant select on public.memberships to authenticated;

-- Si ya habías corrido supabase-pagos.sql, pasa esos pagos a Bootcamper
do $$ begin
  if to_regclass('public.purchases') is not null then
    insert into public.memberships (user_id, plan, charge_id, amount, currency, starts_at)
    select p.user_id, 'bootcamper', p.charge_id, p.amount, p.currency, p.paid_at from public.purchases p
    where not exists (select 1 from public.memberships m where m.user_id = p.user_id and m.plan = 'bootcamper');
  end if;
end $$;

create or replace function public.tier_of(uid uuid)
returns int language sql security definer set search_path = public stable as $$
  select coalesce(max(case plan when 'bootcamper' then 1 when 'eagle' then 2 when 'eagle_plus' then 3 else 0 end), 0)
  from public.memberships where user_id = uid and (expires_at is null or expires_at > now());
$$;
revoke all on function public.tier_of(uuid) from public, anon, authenticated;
grant execute on function public.tier_of(uuid) to service_role;

create or replace function public.user_tier()
returns int language sql security definer set search_path = public stable as $$ select public.tier_of(auth.uid()); $$;
grant execute on function public.user_tier() to authenticated;

create or replace function public.is_paid()
returns boolean language sql security definer set search_path = public stable as $$ select public.user_tier() >= 1; $$;
grant execute on function public.is_paid() to authenticated;

-- Fecha de vencimiento del plan Eagle vigente (para mostrar "renovar")
create or replace function public.plan_info()
returns json language sql security definer set search_path = public stable as $$
  select json_build_object('tier', public.user_tier(),
    'expires', (select max(expires_at) from public.memberships where user_id = auth.uid() and plan in ('eagle','eagle_plus') and expires_at > now()));
$$;
grant execute on function public.plan_info() to authenticated;

-- ---------- 2. Administradores (tú) ----------
create table if not exists public.admins (user_id uuid primary key references auth.users(id) on delete cascade);
alter table public.admins enable row level security;
create or replace function public.is_admin()
returns boolean language sql security definer set search_path = public stable as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;
grant execute on function public.is_admin() to authenticated;

-- ---------- 3. Qué se guarda según el plan ----------
--  Todos: coach/, tracker/, lectura/ (resaltados y notas)  ·  Plan RPM (plan/, semanas/, dias/): Bootcamper o más
drop policy if exists "docs: crear los propios"  on public.app_docs;
drop policy if exists "docs: editar los propios" on public.app_docs;
create policy "docs: crear los propios" on public.app_docs for insert
  with check (auth.uid() = user_id and (path like 'coach/%' or path like 'tracker/%' or path like 'lectura/%' or public.is_paid()));
create policy "docs: editar los propios" on public.app_docs for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id and (path like 'coach/%' or path like 'tracker/%' or path like 'lectura/%' or public.is_paid()));

-- ---------- 4. Libros PDF propios (límite por plan: 1 · 2 · 10 · sin límite) ----------
create or replace function public.book_limit()
returns int language sql security definer set search_path = public stable as $$
  select case public.user_tier() when 0 then 1 when 1 then 2 when 2 then 10 else 100000 end;
$$;
grant execute on function public.book_limit() to authenticated;

create table if not exists public.user_books (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title      text not null,
  author     text,
  pages      int,
  created_at timestamptz not null default now()
);
alter table public.user_books enable row level security;
create or replace function public.my_book_count()
returns int language sql security definer set search_path = public stable as $$
  select count(*)::int from public.user_books where user_id = auth.uid();
$$;
grant execute on function public.my_book_count() to authenticated;
drop policy if exists "libros: ver los propios"   on public.user_books;
drop policy if exists "libros: subir con límite"  on public.user_books;
drop policy if exists "libros: borrar los propios" on public.user_books;
create policy "libros: ver los propios"    on public.user_books for select using (auth.uid() = user_id);
create policy "libros: subir con límite"   on public.user_books for insert with check (auth.uid() = user_id and public.my_book_count() < public.book_limit());
create policy "libros: borrar los propios" on public.user_books for delete using (auth.uid() = user_id);
grant select, insert, delete on public.user_books to authenticated;

-- ---------- 5. Biblioteca (la llenas tú; la leen los planes Eagle) ----------
create table if not exists public.library_books (
  id         uuid primary key default gen_random_uuid(),
  title      text not null,
  author     text,
  descr      text,
  kind       text not null default 'propio' check (kind in ('propio','clasico')),
  lang       text default 'es',
  pages      int,
  created_at timestamptz not null default now()
);
alter table public.library_books enable row level security;
drop policy if exists "biblioteca: ver catálogo"  on public.library_books;
drop policy if exists "biblioteca: admin escribe" on public.library_books;
create policy "biblioteca: ver catálogo"  on public.library_books for select to authenticated using (true);
create policy "biblioteca: admin escribe" on public.library_books for all to authenticated using (public.is_admin()) with check (public.is_admin());
grant select, insert, update, delete on public.library_books to authenticated;

-- ---------- 6. Archivos (Storage) ----------
insert into storage.buckets (id, name, public) values ('libros', 'libros', false), ('biblioteca', 'biblioteca', false)
on conflict (id) do nothing;
drop policy if exists "libros: leer propios"   on storage.objects;
drop policy if exists "libros: subir propios"  on storage.objects;
drop policy if exists "libros: borrar propios" on storage.objects;
drop policy if exists "biblioteca: leer Eagle" on storage.objects;
drop policy if exists "biblioteca: admin sube" on storage.objects;
drop policy if exists "biblioteca: admin borra" on storage.objects;
create policy "libros: leer propios"   on storage.objects for select to authenticated using (bucket_id = 'libros' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "libros: subir propios"  on storage.objects for insert to authenticated with check (bucket_id = 'libros' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "libros: borrar propios" on storage.objects for delete to authenticated using (bucket_id = 'libros' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "biblioteca: leer Eagle" on storage.objects for select to authenticated using (bucket_id = 'biblioteca' and (public.user_tier() >= 2 or public.is_admin()));
create policy "biblioteca: admin sube" on storage.objects for insert to authenticated with check (bucket_id = 'biblioteca' and public.is_admin());
create policy "biblioteca: admin borra" on storage.objects for delete to authenticated using (bucket_id = 'biblioteca' and public.is_admin());

-- ---------- 7. Tokens de IA por mes (nivel 1: 100 mil · nivel 2: 250 mil · nivel 3: 500 mil) ----------
create table if not exists public.ai_tokens (
  user_id uuid not null references auth.users(id) on delete cascade,
  month   date not null,
  tokens  bigint not null default 0,
  primary key (user_id, month)
);
alter table public.ai_tokens enable row level security;
drop policy if exists "tokens: ver los propios" on public.ai_tokens;
create policy "tokens: ver los propios" on public.ai_tokens for select using (auth.uid() = user_id);
grant select on public.ai_tokens to authenticated;
create or replace function public.add_ai_tokens(uid uuid, n bigint)
returns bigint language sql security definer set search_path = public as $$
  insert into public.ai_tokens (user_id, month, tokens) values (uid, date_trunc('month', now())::date, greatest(n, 0))
  on conflict (user_id, month) do update set tokens = public.ai_tokens.tokens + greatest(n, 0)
  returning tokens;
$$;
revoke all on function public.add_ai_tokens(uuid, bigint) from public, anon, authenticated;   -- solo la función «coach»
grant execute on function public.add_ai_tokens(uuid, bigint) to service_role;

-- ---------- 8. Tu cuenta: administrador + plan Eagle Plus de cortesía ----------
insert into public.admins (user_id) select id from auth.users where email = 'arkholzbau@gmail.com' on conflict do nothing;
insert into public.memberships (user_id, plan, charge_id, amount, currency)
select u.id, 'eagle_plus', 'cortesia', 0, 'USD' from auth.users u
where u.email = 'arkholzbau@gmail.com'
  and not exists (select 1 from public.memberships m where m.user_id = u.id and m.charge_id = 'cortesia');

notify pgrst, 'reload schema';
