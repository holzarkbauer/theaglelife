// Supabase Edge Function «culqi-webhook»: Culqi avisa cada cobro mensual, fallo o cancelación de una suscripción.
// Por seguridad NO confiamos en el contenido del aviso: tomamos el id de la suscripción (sxn_…)
// y le preguntamos su estado real a Culqi con tu llave secreta. Así nadie puede activar un plan con un aviso falso.
// Publícala con «Verify JWT» DESACTIVADO (Culqi no envía sesión de Supabase).
// URL para pegar en Culqi → Desarrollo → Webhooks: https://<tu-proyecto>.supabase.co/functions/v1/culqi-webhook
import { createClient } from "npm:@supabase/supabase-js@2";

const AMOUNT: Record<string, number> = { semillas: 700, eagle_mes: 1700 };

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return new Response("ok");
  try {
    const raw = await req.text();
    const ids = [...new Set(raw.match(/sxn_(?:live|test)_[A-Za-z0-9]+/g) ?? [])].slice(0, 5);
    if (!ids.length) return new Response(JSON.stringify({ ok: true, ignored: true }), { headers: { "Content-Type": "application/json" } });
    const sk = Deno.env.get("CULQI_SECRET_KEY")!;
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const results: unknown[] = [];
    for (const id of ids) {
      const { data: row } = await admin.from("subscriptions").select("id,user_id,plan,status").eq("culqi_sub", id).maybeSingle();
      if (!row) { results.push({ id, unknown: true }); continue; }
      const r = await fetch("https://api.culqi.com/v2/recurrent/subscriptions/" + id, { headers: { Authorization: "Bearer " + sk } });
      const sub: any = await r.json().catch(() => ({}));
      if (!r.ok) { results.push({ id, error: r.status }); continue; }
      const st = String(sub.status ?? "").toLowerCase();
      const canceled = /cancel|anul|inactiv|expir|finaliz/.test(st);
      const toDate = (v: any) => v == null ? null : new Date(typeof v === "number" ? (v < 1e12 ? v * 1000 : v) : v);
      const next = toDate(sub.next_billing_date);
      // ¿Hubo un cobro exitoso? (busca en los periodos de la suscripción)
      const charges = (Array.isArray(sub.periods) ? sub.periods : []).flatMap((p: any) => Array.isArray(p.charges) ? p.charges : []);
      const ok = charges.filter((c: any) => /exito|éxito|success|paid|pagad|captur/.test(String(c.charger_status ?? c.status ?? "").toLowerCase()));
      const last = ok[ok.length - 1];
      if (canceled) {
        await admin.from("subscriptions").update({ status: "canceled", updated_at: new Date().toISOString() }).eq("id", row.id);
        results.push({ id, canceled: true });
        continue;
      }
      await admin.from("subscriptions").update({ status: "active", trial: false, next_billing: next && !isNaN(+next) ? next.toISOString() : null, updated_at: new Date().toISOString() }).eq("id", row.id);
      if (last?.charge_id) {
        const { data: dup } = await admin.from("memberships").select("id").eq("charge_id", last.charge_id).maybeSingle();
        // vigencia hasta el próximo cobro + 2 días de gracia (o 31 días si Culqi no informa la fecha)
        const until = next && !isNaN(+next) && +next > Date.now() ? new Date(+next + 2 * 864e5) : new Date(Date.now() + 31 * 864e5);
        // El primer cobro de una suscripción sin prueba ya quedó registrado al suscribirse (con el id sxn_ como código)
        const { data: first } = dup ? { data: null } : await admin.from("memberships").select("id").eq("subscription_id", id).eq("charge_id", id).maybeSingle();
        if (first) {
          await admin.from("memberships").update({ charge_id: last.charge_id, expires_at: until.toISOString() }).eq("id", first.id);
          results.push({ id, first: true });
        } else if (!dup) {
          await admin.from("memberships").insert({
            user_id: row.user_id, plan: row.plan, charge_id: last.charge_id, subscription_id: id,
            amount: Number(last.amount) || AMOUNT[row.plan], currency: last.currency ?? "USD", expires_at: until.toISOString(),
          });
          results.push({ id, renewed: until.toISOString() });
        } else results.push({ id, already: true });
      } else results.push({ id, status: st });
    }
    return new Response(JSON.stringify({ ok: true, results }), { headers: { "Content-Type": "application/json" } });
  } catch (e) {
    return new Response(JSON.stringify({ error: String((e as Error)?.message ?? e) }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
});
