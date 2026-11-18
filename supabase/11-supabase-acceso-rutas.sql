-- ============================================================
--  The Eagle Life · paso 11: entrar con código de 6 dígitos, IA gratis limitada,
--  libros «incluidos en la suscripción» y enlaces a comunidades.
--  Córrelo después del paso 10 · SQL Editor → + New → pegar todo → Run
-- ============================================================

-- 1) Cuentas nuevas sin nombre de usuario (al entrar con código): se crea uno automático y único
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare base text; cand text; n int := 0;
begin
  base := lower(coalesce(nullif(new.raw_user_meta_data->>'username', ''), split_part(coalesce(new.email, 'usuario'), '@', 1)));
  base := regexp_replace(base, '[^a-z0-9_.]', '', 'g');
  if char_length(base) < 3 then base := base || 'usuario'; end if;
  base := left(base, 24);
  cand := base;
  while exists (select 1 from public.profiles where lower(username) = cand) loop
    n := n + 1; cand := left(base, 24) || n::text;
  end loop;
  insert into public.profiles (id, username, email) values (new.id, cand, new.email)
  on conflict (id) do nothing;
  return new;
end $$;

-- 2) IA gratis: unos 15 mensajes al mes (30 000 tokens) para quien no tiene plan; sin razonamiento avanzado
insert into public.app_settings (key, value) values
  ('monthly_tokens', '[30000, 600000, 4000000, 8000000]'::jsonb),
  ('opus_tokens',    '[0, 15000, 115000, 330000]'::jsonb)
on conflict (key) do update set value = jsonb_set(
  case when jsonb_typeof(public.app_settings.value) = 'array' and jsonb_array_length(public.app_settings.value) = 4
       then public.app_settings.value else excluded.value end, '{0}',
  case when public.app_settings.key = 'monthly_tokens' then '30000'::jsonb else '0'::jsonb end);

-- 3) Libros «incluidos en tu suscripción» (estrella en la portada) y socio que recibe la parte del autor
alter table public.store_books add column if not exists included boolean not null default false;
alter table public.store_books add column if not exists partner text not null default '';
alter table public.store_books add column if not exists partner_share_pct int not null default 0 check (partner_share_pct between 0 and 100);

-- Los libros «incluidos» y públicos se leen completos con cualquier plan activo (prueba, Semillas o Eagle)
create or replace function public.can_view_book(bid uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select public.is_admin()
    or exists (select 1 from public.store_viewers v join auth.users u on lower(u.email) = lower(v.email)
               where v.book_id = bid and u.id = auth.uid())
    or (auth.uid() is not null and public.user_tier() >= 1 and exists (
          select 1 from public.store_books b where b.id = bid and b.included and b.active and b.visibility = 'public'));
$$;
grant execute on function public.can_view_book(uuid) to anon, authenticated;

-- 4) Enlaces a comunidades para llevar los cursos de forma virtual (se editan aquí o desde el Backoffice)
insert into public.app_settings (key, value) values
  ('course_links', '{"hombria": {"name": "Grupos de hombres · Camino de Vida", "url": "https://caminodevida.com/grupospequenos/hombres/"}}'::jsonb)
on conflict (key) do nothing;
create or replace function public.course_links()
returns json language sql security definer set search_path = public stable as $$
  select coalesce((select value from public.app_settings where key = 'course_links'), '{}'::jsonb)::json;
$$;
grant execute on function public.course_links() to anon, authenticated;

notify pgrst, 'reload schema';
