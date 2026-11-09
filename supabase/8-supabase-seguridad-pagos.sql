-- ============================================================
--  The Eagle Life · paso 8: backoffice con verificación en 2 pasos (2FA),
--  precios en soles para Culqi y Mercado Pago.
--  Córrelo después del paso 7 · SQL Editor → + New → pegar todo → Run
-- ============================================================

-- 1) El backoffice exige sesión verificada con código 2FA (nivel aal2).
--    Sin el código, ninguna función ni tabla de administrador responde, aunque alguien tenga tu contraseña.
create or replace function public.is_admin()
returns boolean language sql security definer set search_path = public stable as $$
  select exists (select 1 from public.admins where user_id = auth.uid())
     and coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2';
$$;
grant execute on function public.is_admin() to anon, authenticated;

-- La app solo necesita saber si la cuenta ES administradora (para mostrar el menú) y si ya pasó el 2FA
create or replace function public.admin_status()
returns json language sql security definer set search_path = public stable as $$
  select json_build_object(
    'admin', exists (select 1 from public.admins where user_id = auth.uid()),
    'aal', coalesce(auth.jwt() ->> 'aal', 'aal1'));
$$;
grant execute on function public.admin_status() to authenticated;

-- 2) Precios en soles (Culqi en PEN). Se cambian aquí o desde Backoffice → Límites y metas.
insert into public.app_settings (key, value) values
  ('prices_pen', '{"prueba": 400, "semillas": 2700, "eagle_mes": 6500, "fx": 3.8}'::jsonb)
on conflict (key) do nothing;
create or replace function public.price_list()
returns json language sql security definer set search_path = public stable as $$
  select coalesce((select value from public.app_settings where key = 'prices_pen'), '{}'::jsonb)::json;
$$;
grant execute on function public.price_list() to anon, authenticated;

-- 3) Suscripciones: proveedor (Culqi o Mercado Pago)
alter table public.subscriptions add column if not exists provider text not null default 'culqi';
alter table public.subscriptions add column if not exists currency text not null default 'USD';
alter table public.subscriptions add column if not exists mp_preapproval text unique;
create or replace function public.plan_info()
returns json language sql security definer set search_path = public stable as $$
  select json_build_object(
    'tier', public.user_tier(),
    'expires', (select max(expires_at) from public.memberships where user_id = auth.uid() and expires_at > now()),
    'plan', (select plan from public.memberships where user_id = auth.uid() and (expires_at is null or expires_at > now())
             order by expires_at desc nulls first limit 1),
    'sub', (select json_build_object('plan', plan, 'status', status, 'trial', trial, 'next', next_billing, 'provider', provider, 'currency', currency)
            from public.subscriptions where user_id = auth.uid() order by created_at desc limit 1));
$$;
grant execute on function public.plan_info() to authenticated;

notify pgrst, 'reload schema';
