-- ============================================================
--  The Eagle Life · paso 10: Libro de Reclamaciones virtual (Perú · Código de Protección y Defensa del Consumidor)
--  SQL Editor → + New → pegar todo → Run
-- ============================================================
create sequence if not exists public.reclamos_seq;
create table if not exists public.reclamos (
  id bigint primary key default nextval('public.reclamos_seq'),
  codigo text unique not null,
  created_at timestamptz not null default now(),
  tipo text not null check (tipo in ('reclamo','queja')),
  nombre text not null, doc_tipo text not null, doc_num text not null,
  domicilio text not null default '', telefono text not null default '', email text not null,
  menor boolean not null default false, apoderado text not null default '',
  bien text not null check (bien in ('producto','servicio')),
  monto text not null default '', descripcion text not null,
  detalle text not null, pedido text not null,
  estado text not null default 'nuevo' check (estado in ('nuevo','en_proceso','respondido')),
  respuesta text not null default '', respondido_at timestamptz,
  user_id uuid);
alter table public.reclamos enable row level security;
drop policy if exists "reclamos: admin lee" on public.reclamos;
create policy "reclamos: admin lee" on public.reclamos for select using (public.is_admin());
drop policy if exists "reclamos: admin responde" on public.reclamos;
create policy "reclamos: admin responde" on public.reclamos for update using (public.is_admin()) with check (public.is_admin());
grant select, update on public.reclamos to authenticated;

-- Registro público (sin cuenta). Devuelve el código correlativo de la hoja.
create or replace function public.submit_reclamo(r json)
returns json language plpgsql security definer set search_path = public as $$
declare n bigint; c text; t text := lower(coalesce(r->>'tipo',''));
begin
  if t not in ('reclamo','queja') then raise exception 'Elige reclamo o queja.'; end if;
  if length(coalesce(r->>'nombre','')) < 3 or length(coalesce(r->>'doc_num','')) < 6 then raise exception 'Completa tu nombre y documento.'; end if;
  if coalesce(r->>'email','') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Escribe un correo válido.'; end if;
  if length(coalesce(r->>'detalle','')) < 10 or length(coalesce(r->>'pedido','')) < 3 then raise exception 'Describe el detalle y tu pedido.'; end if;
  -- freno simple: máximo 5 hojas por correo al día
  if (select count(*) from reclamos where email = lower(r->>'email') and created_at > now() - interval '1 day') >= 5 then
    raise exception 'Ya registraste varias hojas hoy. Te responderemos por correo.'; end if;
  n := nextval('reclamos_seq');
  c := 'LR-' || to_char(now() at time zone 'America/Lima', 'YYYY') || '-' || lpad(n::text, 6, '0');
  insert into reclamos (id, codigo, tipo, nombre, doc_tipo, doc_num, domicilio, telefono, email, menor, apoderado, bien, monto, descripcion, detalle, pedido, user_id)
  values (n, c, t, left(r->>'nombre',150), left(coalesce(r->>'doc_tipo','DNI'),20), left(r->>'doc_num',20), left(coalesce(r->>'domicilio',''),250),
    left(coalesce(r->>'telefono',''),30), lower(left(r->>'email',150)), coalesce((r->>'menor')::boolean,false), left(coalesce(r->>'apoderado',''),150),
    case when r->>'bien' = 'producto' then 'producto' else 'servicio' end, left(coalesce(r->>'monto',''),40), left(coalesce(r->>'descripcion',''),500),
    left(r->>'detalle',3000), left(r->>'pedido',1500), auth.uid());
  return json_build_object('codigo', c, 'fecha', to_char(now() at time zone 'America/Lima', 'DD/MM/YYYY HH24:MI'));
end $$;
grant execute on function public.submit_reclamo(json) to anon, authenticated;
notify pgrst, 'reload schema';
