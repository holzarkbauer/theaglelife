-- ============================================================
--  Semillas de Identidad · theaglelife.com/app
--  Configuración de cuentas y datos por usuario (Supabase)
--  Pega TODO este archivo en Supabase → SQL Editor → Run
-- ============================================================

-- 1) PERFILES: un nombre de usuario único por cuenta
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  username    text not null check (char_length(username) between 3 and 30),
  email       text,
  created_at  timestamptz not null default now()
);
-- Único sin importar mayúsculas (Jose = jose)
create unique index if not exists profiles_username_lower_idx
  on public.profiles (lower(username));

alter table public.profiles enable row level security;

drop policy if exists "perfil: ver el propio" on public.profiles;
create policy "perfil: ver el propio" on public.profiles
  for select using (auth.uid() = id);

-- 2) Al registrarse, crear el perfil automáticamente
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, username, email)
  values (new.id, new.raw_user_meta_data->>'username', new.email);
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 3) ¿Está libre el nombre de usuario? (la app lo consulta antes de registrar)
create or replace function public.username_available(u text)
returns boolean
language sql
security definer set search_path = public
stable
as $$
  select not exists (select 1 from public.profiles where lower(username) = lower(u));
$$;
grant execute on function public.username_available(text) to anon, authenticated;

-- 4) DATOS DE LA APP: cada usuario solo ve y edita lo suyo
create table if not exists public.app_docs (
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  path        text not null,             -- ej. tracker/main, plan/vision, dias/d001
  data        jsonb not null default '{}'::jsonb,
  updated_at  timestamptz not null default now(),
  primary key (user_id, path)
);

alter table public.app_docs enable row level security;

drop policy if exists "docs: leer los propios"    on public.app_docs;
drop policy if exists "docs: crear los propios"   on public.app_docs;
drop policy if exists "docs: editar los propios"  on public.app_docs;
drop policy if exists "docs: borrar los propios"  on public.app_docs;

create policy "docs: leer los propios"   on public.app_docs for select using (auth.uid() = user_id);
create policy "docs: crear los propios"  on public.app_docs for insert with check (auth.uid() = user_id);
create policy "docs: editar los propios" on public.app_docs for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "docs: borrar los propios" on public.app_docs for delete using (auth.uid() = user_id);
