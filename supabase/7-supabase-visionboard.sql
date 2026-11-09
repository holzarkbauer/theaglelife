-- ============================================================
--  The Eagle Life · paso 7: Vision Board
--  Almacenamiento privado de las imágenes de cada usuario + cupo mensual de imágenes con IA.
--  Córrelo después del paso 6 · SQL Editor → + New → pegar todo → Run
-- ============================================================

-- Carpeta privada: cada usuario solo ve y sube dentro de su carpeta (vision/<su id>/...)
insert into storage.buckets (id, name, public) values ('vision', 'vision', false) on conflict (id) do nothing;
drop policy if exists "vision: ver lo propio" on storage.objects;
drop policy if exists "vision: subir lo propio" on storage.objects;
drop policy if exists "vision: cambiar lo propio" on storage.objects;
drop policy if exists "vision: borrar lo propio" on storage.objects;
create policy "vision: ver lo propio" on storage.objects for select to authenticated
  using (bucket_id = 'vision' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "vision: subir lo propio" on storage.objects for insert to authenticated
  with check (bucket_id = 'vision' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "vision: cambiar lo propio" on storage.objects for update to authenticated
  using (bucket_id = 'vision' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "vision: borrar lo propio" on storage.objects for delete to authenticated
  using (bucket_id = 'vision' and (storage.foldername(name))[1] = auth.uid()::text);

-- Cupo de imágenes con IA por mes
alter table public.ai_tokens add column if not exists images int not null default 0;
create or replace function public.add_vision_image(uid uuid)
returns int language sql security definer set search_path = public as $$
  insert into public.ai_tokens as t (user_id, month, tokens, images)
  values (uid, date_trunc('month', now())::date, 0, 1)
  on conflict (user_id, month) do update set images = t.images + 1
  returning t.images;
$$;
revoke all on function public.add_vision_image(uuid) from public, anon, authenticated;
grant execute on function public.add_vision_image(uuid) to service_role;

insert into public.app_settings (key, value) values ('vision_images', '[0, 3, 12, 40]'::jsonb)
on conflict (key) do nothing;

notify pgrst, 'reload schema';
