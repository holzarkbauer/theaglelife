-- ============================================================
--  Semillas de Identidad · paso 2: permisos + control de uso del coach IA
--  Supabase → SQL Editor → + New → pegar todo → Run
-- ============================================================

-- 1) Permisos de las tablas (arregla "no se guardan los cambios")
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on public.app_docs to authenticated;
grant select on public.profiles to authenticated;

-- 2) Conteo de consultas al coach por usuario y por día (para controlar el costo)
create table if not exists public.ai_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  day     date not null default current_date,
  calls   int  not null default 0,
  primary key (user_id, day)
);
alter table public.ai_usage enable row level security;   -- nadie la lee desde la app

create or replace function public.bump_ai_usage()
returns int
language sql
security definer set search_path = public
as $$
  insert into public.ai_usage (user_id, day, calls)
  values (auth.uid(), current_date, 1)
  on conflict (user_id, day) do update set calls = public.ai_usage.calls + 1
  returning calls;
$$;
revoke all on function public.bump_ai_usage() from public, anon;
grant execute on function public.bump_ai_usage() to authenticated;

notify pgrst, 'reload schema';
