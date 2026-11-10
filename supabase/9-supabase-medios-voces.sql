-- ============================================================
--  The Eagle Life · paso 9: biblioteca de medios (sonidos y videos de fondo) y voces de declaraciones,
--  editables desde el Backoffice. Córrelo después del paso 8 · SQL Editor → + New → pegar todo → Run
-- ============================================================

-- 1) Categorías y elementos (kind: 'sound' = sonidos de naturaleza · 'video' = fondos para meditar)
create table if not exists public.media_categories (
  id text primary key default ('c-' || substr(md5(random()::text), 1, 10)),
  kind text not null check (kind in ('sound','video')),
  name text not null,
  description text not null default '',
  sort int not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now());
create table if not exists public.media_items (
  id text primary key default ('m-' || substr(md5(random()::text), 1, 12)),
  category_id text not null references public.media_categories(id) on delete cascade,
  name text not null,
  file_path text not null,          -- ruta en la app (sonidos/… o fondos/…) o en el bucket «medios», o un https://
  poster_path text,                 -- solo videos: imagen fija
  sort int not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now());
create index if not exists media_items_cat on public.media_items(category_id, sort);

-- 2) Voces para las declaraciones (4haus Studio o la voz del dispositivo)
create table if not exists public.voices (
  id text primary key default ('v-' || substr(md5(random()::text), 1, 10)),
  name text not null,
  provider text not null default '4haus' check (provider in ('4haus','device')),
  provider_voice_id text not null default '',
  lang text not null default 'es',
  gender text not null default '',
  description text not null default '',
  sample_url text,
  min_tier int not null default 1,  -- 0 = gratis · 1 = prueba/Semillas · 3 = Eagle
  sort int not null default 0,
  active boolean not null default true,
  is_default boolean not null default false,
  created_at timestamptz not null default now());

alter table public.media_categories enable row level security;
alter table public.media_items enable row level security;
alter table public.voices enable row level security;
drop policy if exists "medios: leer activos" on public.media_categories;
create policy "medios: leer activos" on public.media_categories for select using (active or public.is_admin());
drop policy if exists "medios: admin escribe" on public.media_categories;
create policy "medios: admin escribe" on public.media_categories for all using (public.is_admin()) with check (public.is_admin());
drop policy if exists "items: leer activos" on public.media_items;
create policy "items: leer activos" on public.media_items for select using (active or public.is_admin());
drop policy if exists "items: admin escribe" on public.media_items;
create policy "items: admin escribe" on public.media_items for all using (public.is_admin()) with check (public.is_admin());
drop policy if exists "voces: leer activas" on public.voices;
create policy "voces: leer activas" on public.voices for select using (active or public.is_admin());
drop policy if exists "voces: admin escribe" on public.voices;
create policy "voces: admin escribe" on public.voices for all using (public.is_admin()) with check (public.is_admin());
grant select on public.media_categories, public.media_items, public.voices to anon, authenticated;
grant insert, update, delete on public.media_categories, public.media_items, public.voices to authenticated;

-- 3) Bucket público «medios» para lo que subas desde el Backoffice (audio .mp3, video .mp4, imágenes .jpg)
insert into storage.buckets (id, name, public) values ('medios', 'medios', true) on conflict (id) do update set public = true;
drop policy if exists "medios: leer" on storage.objects;
create policy "medios: leer" on storage.objects for select using (bucket_id = 'medios');
drop policy if exists "medios: admin sube" on storage.objects;
create policy "medios: admin sube" on storage.objects for insert to authenticated with check (bucket_id = 'medios' and public.is_admin());
drop policy if exists "medios: admin cambia" on storage.objects;
create policy "medios: admin cambia" on storage.objects for update to authenticated using (bucket_id = 'medios' and public.is_admin());
drop policy if exists "medios: admin borra" on storage.objects;
create policy "medios: admin borra" on storage.objects for delete to authenticated using (bucket_id = 'medios' and public.is_admin());

-- 4) La app lee todo en una sola llamada
create or replace function public.media_library()
returns json language sql security definer set search_path = public stable as $$
  select json_build_object(
    'sound', coalesce((select json_agg(c order by c.sort) from (
        select mc.id, mc.name, mc.description, mc.sort,
          (select coalesce(json_agg(json_build_object('id', mi.id, 'n', mi.name, 'f', mi.file_path) order by mi.sort), '[]'::json)
             from media_items mi where mi.category_id = mc.id and mi.active) as items
        from media_categories mc where mc.kind = 'sound' and mc.active) c), '[]'::json),
    'video', coalesce((select json_agg(c order by c.sort) from (
        select mc.id, mc.name, mc.description, mc.sort,
          (select coalesce(json_agg(json_build_object('id', mi.id, 'n', mi.name, 'v', mi.file_path, 'p', mi.poster_path) order by mi.sort), '[]'::json)
             from media_items mi where mi.category_id = mc.id and mi.active) as items
        from media_categories mc where mc.kind = 'video' and mc.active) c), '[]'::json),
    'voices', coalesce((select json_agg(json_build_object('id', id, 'name', name, 'provider', provider, 'voice', provider_voice_id,
        'gender', gender, 'description', description, 'sample', sample_url, 'min_tier', min_tier, 'default', is_default) order by sort)
      from voices where active), '[]'::json));
$$;
grant execute on function public.media_library() to anon, authenticated;

-- 5) Contenido inicial: los 20 sonidos y los 54 videos que ya están en la app
insert into public.media_categories (id,kind,name,description,sort) values ('s-rain','sound','Lluvia','Para reflexionar y escribir',0) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,sort) values ('s-lluvia-palmeras','s-rain','Lluvia sobre palmeras','sonidos/lluvia-palmeras.mp3',0) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,sort) values ('s-lluvia-selva','s-rain','Lluvia en la selva','sonidos/lluvia-selva.mp3',1) on conflict (id) do nothing;
insert into public.media_categories (id,kind,name,description,sort) values ('s-water','sound','Agua','Ríos, olas y mar para leer',1) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,sort) values ('s-rio-sereno','s-water','Río sereno','sonidos/rio-sereno.mp3',0) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,sort) values ('s-olas-suaves','s-water','Olas suaves en las rocas','sonidos/olas-suaves.mp3',1) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,sort) values ('s-mar-bahia','s-water','Mar en la bahía','sonidos/mar-bahia.mp3',2) on conflict (id) do nothing;
insert into public.media_categories (id,kind,name,description,sort) values ('s-wind','sound','Viento','Hojas, árboles y montaña para planear',2) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,sort) values ('s-hojas-noche','s-wind','Hojas en una noche de verano','sonidos/hojas-noche.mp3',0) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,sort) values ('s-hojas-montana','s-wind','Hojas en la montaña','sonidos/hojas-montana.mp3',1) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,sort) values ('s-arboles-aves','s-wind','Árboles, hojas y aves','sonidos/arboles-aves.mp3',2) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,sort) values ('s-viento-arboles','s-wind','Viento entre los árboles','sonidos/viento-arboles.mp3',3) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,sort) values ('s-viento-invierno','s-wind','Viento de invierno','sonidos/viento-invierno.mp3',4) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,sort) values ('s-viento-montana','s-wind','Viento fuerte de montaña','sonidos/viento-montana.mp3',5) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,sort) values ('s-viento-dunas','s-wind','Ráfagas en las dunas','sonidos/viento-dunas.mp3',6) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,sort) values ('s-tormenta-nieve','s-wind','Tormenta de nieve','sonidos/tormenta-nieve.mp3',7) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,sort) values ('s-tormenta-himalaya','s-wind','Tormenta en el Himalaya','sonidos/tormenta-himalaya.mp3',8) on conflict (id) do nothing;
insert into public.media_categories (id,kind,name,description,sort) values ('s-forest','sound','Ambiente','Bosques y manglares para orar',3) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,sort) values ('s-bosque-amanecer','s-forest','Aves al amanecer','sonidos/bosque-amanecer.mp3',0) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,sort) values ('s-bosque-tarde','s-forest','Bosque de pinos por la tarde','sonidos/bosque-tarde.mp3',1) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,sort) values ('s-manglar-manana','s-forest','Manglar en la mañana','sonidos/manglar-manana.mp3',2) on conflict (id) do nothing;
insert into public.media_categories (id,kind,name,description,sort) values ('s-birds','sound','Aves','Cantos al atardecer',4) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,sort) values ('s-bosque-atardecer','s-birds','Zorzales al atardecer','sonidos/bosque-atardecer.mp3',0) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,sort) values ('s-bosque-mirlo','s-birds','Mirlo y aves lejanas','sonidos/bosque-mirlo.mp3',1) on conflict (id) do nothing;
insert into public.media_categories (id,kind,name,description,sort) values ('s-animals','sound','Animales','Grillos en la pradera',5) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,sort) values ('s-pradera-grillos','s-animals','Pradera con grillos','sonidos/pradera-grillos.mp3',0) on conflict (id) do nothing;
insert into public.media_categories (id,kind,name,description,sort) values ('v-montanas','video','Montañas','',0) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c01','v-montanas','Cumbres rocosas','fondos/c01.mp4','fondos/c01.jpg',0) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c10','v-montanas','Picos verdes','fondos/c10.mp4','fondos/c10.jpg',1) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c22','v-montanas','Valle entre montañas','fondos/c22.mp4','fondos/c22.jpg',2) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c29','v-montanas','Pico nevado','fondos/c29.mp4','fondos/c29.jpg',3) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c39','v-montanas','Montañas en la niebla','fondos/c39.mp4','fondos/c39.jpg',4) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c03','v-montanas','Cima sobre las nubes','fondos/c03.mp4','fondos/c03.jpg',5) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c18','v-montanas','Montaña al alba','fondos/c18.mp4','fondos/c18.jpg',6) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c40','v-montanas','Camino entre nubes','fondos/c40.mp4','fondos/c40.jpg',7) on conflict (id) do nothing;
insert into public.media_categories (id,kind,name,description,sort) values ('v-cielos','video','Cielos y atardeceres','',1) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-b12','v-cielos','Atardecer en el bosque','fondos/b12.mp4','fondos/b12.jpg',0) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-b39','v-cielos','Sol sobre la ciudad','fondos/b39.mp4','fondos/b39.jpg',1) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c05','v-cielos','Amanecer sobre las nubes','fondos/c05.mp4','fondos/c05.jpg',2) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c21','v-cielos','Atardecer en la bahía','fondos/c21.mp4','fondos/c21.jpg',3) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c23','v-cielos','Sol en la nieve','fondos/c23.mp4','fondos/c23.jpg',4) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-b11','v-cielos','Cielo rosado en la costa','fondos/b11.mp4','fondos/b11.jpg',5) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c48','v-cielos','Espiga al atardecer','fondos/c48.mp4','fondos/c48.jpg',6) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c15','v-cielos','Trigo a contraluz','fondos/c15.mp4','fondos/c15.jpg',7) on conflict (id) do nothing;
insert into public.media_categories (id,kind,name,description,sort) values ('v-mar','video','Mar y playas','',2) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-b17','v-mar','La ola','fondos/b17.mp4','fondos/b17.jpg',0) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-b36','v-mar','Orilla desde el cielo','fondos/b36.mp4','fondos/b36.jpg',1) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-b44','v-mar','Playa al amanecer','fondos/b44.mp4','fondos/b44.jpg',2) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c07','v-mar','Mar turquesa','fondos/c07.mp4','fondos/c07.jpg',3) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c25','v-mar','Costa infinita','fondos/c25.mp4','fondos/c25.jpg',4) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c36','v-mar','Playa cristalina','fondos/c36.mp4','fondos/c36.jpg',5) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c42','v-mar','Olas en las rocas','fondos/c42.mp4','fondos/c42.jpg',6) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-b45','v-mar','Mar entre rocas','fondos/b45.mp4','fondos/b45.jpg',7) on conflict (id) do nothing;
insert into public.media_categories (id,kind,name,description,sort) values ('v-agua','video','Ríos y lagos','',3) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c14','v-agua','Río en el bosque','fondos/c14.mp4','fondos/c14.jpg',0) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c35','v-agua','Río en el valle','fondos/c35.mp4','fondos/c35.jpg',1) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c44','v-agua','Cañón con río','fondos/c44.mp4','fondos/c44.jpg',2) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c17','v-agua','Lago en calma','fondos/c17.mp4','fondos/c17.jpg',3) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c45','v-agua','Humedal verde','fondos/c45.mp4','fondos/c45.jpg',4) on conflict (id) do nothing;
insert into public.media_categories (id,kind,name,description,sort) values ('v-bosques','video','Bosques','',4) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-b29','v-bosques','Bosque de secuoyas','fondos/b29.mp4','fondos/b29.jpg',0) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c09','v-bosques','Bosque de otoño','fondos/c09.mp4','fondos/c09.jpg',1) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c16','v-bosques','Pinos al sol','fondos/c16.mp4','fondos/c16.jpg',2) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c27','v-bosques','Selva desde el cielo','fondos/c27.mp4','fondos/c27.jpg',3) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c38','v-bosques','Copas de los árboles','fondos/c38.mp4','fondos/c38.jpg',4) on conflict (id) do nothing;
insert into public.media_categories (id,kind,name,description,sort) values ('v-campos','video','Campos y valles','',5) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-a00','v-campos','Arrozal entre montañas','fondos/a00.mp4','fondos/a00.jpg',0) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-b01','v-campos','Campo de lavanda','fondos/b01.mp4','fondos/b01.jpg',1) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-b46','v-campos','Campo sembrado','fondos/b46.mp4','fondos/b46.jpg',2) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c02','v-campos','Campos y molino','fondos/c02.mp4','fondos/c02.jpg',3) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c20','v-campos','Casa en la pradera','fondos/c20.mp4','fondos/c20.jpg',4) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c37','v-campos','Colinas verdes','fondos/c37.mp4','fondos/c37.jpg',5) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c41','v-campos','Valle y bosque','fondos/c41.mp4','fondos/c41.jpg',6) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c43','v-campos','Pueblo en el valle','fondos/c43.mp4','fondos/c43.jpg',7) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c30','v-campos','Molinos de viento','fondos/c30.mp4','fondos/c30.jpg',8) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c46','v-campos','Molinos en la niebla','fondos/c46.mp4','fondos/c46.jpg',9) on conflict (id) do nothing;
insert into public.media_categories (id,kind,name,description,sort) values ('v-detalles','video','Detalles de la creación','',6) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-b38','v-detalles','Rocío en la hierba','fondos/b38.mp4','fondos/b38.jpg',0) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-b42','v-detalles','Sol entre ramas','fondos/b42.mp4','fondos/b42.jpg',1) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-b43','v-detalles','Espigas al viento','fondos/b43.mp4','fondos/b43.jpg',2) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c26','v-detalles','Flores silvestres','fondos/c26.mp4','fondos/c26.jpg',3) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c28','v-detalles','Gotas en las hojas','fondos/c28.mp4','fondos/c28.jpg',4) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c47','v-detalles','Hierba al amanecer','fondos/c47.mp4','fondos/c47.jpg',5) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-b41','v-detalles','Páginas de un libro','fondos/b41.mp4','fondos/b41.jpg',6) on conflict (id) do nothing;
insert into public.media_categories (id,kind,name,description,sort) values ('v-caminos','video','Caminos y libertad','',7) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c32','v-caminos','Ruta en el desierto','fondos/c32.mp4','fondos/c32.jpg',0) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c12','v-caminos','Río seco','fondos/c12.mp4','fondos/c12.jpg',1) on conflict (id) do nothing;
insert into public.media_items (id,category_id,name,file_path,poster_path,sort) values ('v-c34','v-caminos','Caballos en libertad','fondos/c34.mp4','fondos/c34.jpg',2) on conflict (id) do nothing;
insert into public.voices (id, name, provider, provider_voice_id, description, min_tier, sort, is_default)
values ('v-dispositivo', 'Voz de tu celular', 'device', '', 'Gratis · la voz en español que trae tu dispositivo', 0, 0, true)
on conflict (id) do nothing;

notify pgrst, 'reload schema';
