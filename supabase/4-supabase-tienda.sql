-- ============================================================
--  Semillas de Identidad · paso 4: tienda de libros, opiniones y tope de IA gratuita
--  Córrelo después de 3-supabase-planes.sql · SQL Editor → + New → pegar → Run
-- ============================================================
grant execute on function public.is_admin() to anon;   -- para que la portada pueda leer opiniones

-- ---------- 1. Opiniones (estrellas + comentario, se publican al aprobarlas) ----------
create table if not exists public.reviews (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null unique default auth.uid() references auth.users(id) on delete cascade,
  username   text,
  stars      int  not null check (stars between 1 and 5),
  comment    text not null check (char_length(comment) between 3 and 600),
  status     text not null default 'pending' check (status in ('pending','approved','hidden')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.reviews enable row level security;
create or replace function public.reviews_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    new.status := 'pending';
    new.user_id := auth.uid();
  end if;
  new.username := coalesce((select username from public.profiles where id = new.user_id), new.username);
  new.updated_at := now();
  return new;
end; $$;
drop trigger if exists reviews_guard on public.reviews;
create trigger reviews_guard before insert or update on public.reviews for each row execute function public.reviews_guard();
drop policy if exists "opiniones: ver aprobadas" on public.reviews;
drop policy if exists "opiniones: escribir la propia" on public.reviews;
drop policy if exists "opiniones: editar la propia" on public.reviews;
drop policy if exists "opiniones: admin borra" on public.reviews;
create policy "opiniones: ver aprobadas" on public.reviews for select to anon, authenticated
  using (status = 'approved' or auth.uid() = user_id or public.is_admin());
create policy "opiniones: escribir la propia" on public.reviews for insert to authenticated with check (auth.uid() = user_id);
create policy "opiniones: editar la propia" on public.reviews for update to authenticated
  using (auth.uid() = user_id or public.is_admin()) with check (auth.uid() = user_id or public.is_admin());
create policy "opiniones: admin borra" on public.reviews for delete to authenticated using (public.is_admin());
grant select on public.reviews to anon, authenticated;
grant insert, update, delete on public.reviews to authenticated;

-- ---------- 2. Tienda: títulos originales con permiso de sus autores ----------
create table if not exists public.store_books (
  id             uuid primary key default gen_random_uuid(),
  title          text not null,
  author         text,
  descr          text,
  price_cents    int  not null check (price_cents >= 300),
  commission_pct int  not null default 30 check (commission_pct between 0 and 100),  -- tu porcentaje
  color          text default '#4d5c1f',
  pages          int,
  active         boolean not null default true,
  created_at     timestamptz not null default now()
);
alter table public.store_books enable row level security;
drop policy if exists "tienda: ver catálogo" on public.store_books;
drop policy if exists "tienda: admin escribe" on public.store_books;
create policy "tienda: ver catálogo" on public.store_books for select to anon, authenticated using (active or public.is_admin());
create policy "tienda: admin escribe" on public.store_books for all to authenticated using (public.is_admin()) with check (public.is_admin());
grant select on public.store_books to anon, authenticated;
grant insert, update, delete on public.store_books to authenticated;

-- Datos privados del autor (solo tú los ves)
create table if not exists public.store_authors (
  book_id      uuid primary key references public.store_books(id) on delete cascade,
  author_email text,
  notes        text
);
alter table public.store_authors enable row level security;
drop policy if exists "autores: solo admin" on public.store_authors;
create policy "autores: solo admin" on public.store_authors for all to authenticated using (public.is_admin()) with check (public.is_admin());
grant select, insert, update, delete on public.store_authors to authenticated;

-- Compras (solo las escribe la función «pago»)
create table if not exists public.book_orders (
  id                 bigserial primary key,
  user_id            uuid not null references auth.users(id) on delete cascade,
  book_id            uuid not null references public.store_books(id) on delete restrict,
  amount             int  not null,
  currency           text,
  author_share_cents int,
  charge_id          text,
  emailed            boolean not null default false,
  created_at         timestamptz not null default now(),
  unique (user_id, book_id)
);
alter table public.book_orders enable row level security;
drop policy if exists "compras: ver las propias" on public.book_orders;
create policy "compras: ver las propias" on public.book_orders for select to authenticated using (auth.uid() = user_id or public.is_admin());
grant select on public.book_orders to authenticated;

-- Archivos de la tienda: <id>.json (lectura en la app) y <id>.pdf (descarga por correo)
insert into storage.buckets (id, name, public) values ('tienda', 'tienda', false) on conflict (id) do nothing;
drop policy if exists "tienda: leer comprados" on storage.objects;
drop policy if exists "tienda: admin sube"     on storage.objects;
drop policy if exists "tienda: admin borra"    on storage.objects;
create policy "tienda: leer comprados" on storage.objects for select to authenticated using (
  bucket_id = 'tienda' and (public.is_admin() or exists (
    select 1 from public.book_orders o where o.user_id = auth.uid() and o.book_id::text = split_part(name, '.', 1))));
create policy "tienda: admin sube"  on storage.objects for insert to authenticated with check (bucket_id = 'tienda' and public.is_admin());
create policy "tienda: admin borra" on storage.objects for delete to authenticated using (bucket_id = 'tienda' and public.is_admin());

-- ---------- 3. Tope mensual de IA para TODO el plan gratuito (protege tu costo) ----------
create table if not exists public.ai_global (
  month       date primary key,
  free_tokens bigint not null default 0
);
alter table public.ai_global enable row level security;
create or replace function public.add_free_pool(n bigint)
returns bigint language sql security definer set search_path = public as $$
  insert into public.ai_global (month, free_tokens) values (date_trunc('month', now())::date, greatest(n, 0))
  on conflict (month) do update set free_tokens = public.ai_global.free_tokens + greatest(n, 0)
  returning free_tokens;
$$;
revoke all on function public.add_free_pool(bigint) from public, anon, authenticated;
grant execute on function public.add_free_pool(bigint) to service_role;

notify pgrst, 'reload schema';
