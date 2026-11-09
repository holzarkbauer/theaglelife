// Supabase Edge Function «mp-webhook»: Mercado Pago avisa pagos, suscripciones autorizadas y cobros mensuales.
// Publícala con «Verify JWT» DESACTIVADO. No confiamos en el aviso: con el id le preguntamos el estado real a Mercado Pago.
// URL para Mercado Pago → Tus integraciones → Webhooks (eventos: Pagos, Planes y suscripciones):
//   https://<tu-proyecto>.supabase.co/functions/v1/mp-webhook
import { createClient } from "npm:@supabase/supabase-js@2";

Deno.serve(async (req: Request) => {
  try {
    const u = new URL(req.url);
    const body: any = req.method === "POST" ? await req.json().catch(() => ({})) : {};
    const type = String(body.type ?? body.topic ?? u.searchParams.get("type") ?? u.searchParams.get("topic") ?? "");
    const id = String(body?.data?.id ?? u.searchParams.get("data.id") ?? u.searchParams.get("id") ?? "").replace(/[^\w-]/g, "");
    if (!id) return new Response("ok");
    const token = Deno.env.get("MP_ACCESS_TOKEN")!;
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const get = async (path: string) => { const r = await fetch("https://api.mercadopago.com" + path, { headers: { Authorization: "Bearer " + token } }); return r.ok ? await r.json() : null; };
    const plus = (d: number) => new Date(Date.now() + d * 864e5).toISOString();

    // Pago único (libros)
    if (/payment/.test(type) && !/authorized/.test(type)) {
      const p: any = await get("/v1/payments/" + id);
      if (p?.status === "approved" && String(p.external_reference ?? "").startsWith("book:")) {
        const [, uid, bookId] = String(p.external_reference).split(":");
        const { data: dup } = await admin.from("book_orders").select("id").eq("user_id", uid).eq("book_id", bookId).maybeSingle();
        if (!dup) {
          const { data: bk } = await admin.from("store_books").select("commission_pct").eq("id", bookId).maybeSingle();
          const cents = Math.round(Number(p.transaction_amount) * 100);
          await admin.from("book_orders").insert({ user_id: uid, book_id: bookId, amount: cents, currency: p.currency_id ?? "USD",
            author_share_cents: Math.round(cents * (100 - Number(bk?.commission_pct ?? 30)) / 100), charge_id: "mp_" + id });
        }
      }
      return new Response("ok");
    }
    // Suscripción autorizada / cancelada
    if (/preapproval/.test(type) && !/authorized_payment/.test(type)) {
      const s: any = await get("/preapproval/" + id);
      if (!s) return new Response("ok");
      const [, uid, planId] = String(s.external_reference ?? "").split(":");
      const { data: row } = await admin.from("subscriptions").select("id,status,plan,trial").eq("mp_preapproval", id).maybeSingle();
      if (s.status === "authorized") {
        if (row) await admin.from("subscriptions").update({ status: "active", next_billing: s.next_payment_date ?? null, updated_at: new Date().toISOString() }).eq("id", row.id);
        // la prueba gratis activa el plan 7 días; los cobros mensuales llegan como «authorized_payment»
        if (planId === "prueba" && uid) {
          const { data: has } = await admin.from("memberships").select("id").eq("user_id", uid).eq("plan", "prueba").limit(1);
          if (!has?.length) await admin.from("memberships").insert({ user_id: uid, plan: "prueba", charge_id: "mp_pre_" + id, subscription_id: id, amount: 0, currency: s.auto_recurring?.currency_id ?? "USD", expires_at: plus(7) });
        }
      } else if (s.status === "cancelled" || s.status === "paused") {
        if (row) await admin.from("subscriptions").update({ status: "canceled", updated_at: new Date().toISOString() }).eq("id", row.id);
      }
      return new Response("ok");
    }
    // Cobro mensual de una suscripción
    if (/authorized_payment/.test(type)) {
      const ap: any = await get("/authorized_payments/" + id);
      const ok = ap && (ap.status === "processed" || ap?.payment?.status === "approved");
      if (!ok) return new Response("ok");
      const { data: row } = await admin.from("subscriptions").select("id,user_id,plan").eq("mp_preapproval", ap.preapproval_id).maybeSingle();
      if (!row) return new Response("ok");
      const { data: dup } = await admin.from("memberships").select("id").eq("charge_id", "mp_ap_" + id).maybeSingle();
      if (!dup) await admin.from("memberships").insert({ user_id: row.user_id, plan: row.plan, charge_id: "mp_ap_" + id, subscription_id: ap.preapproval_id,
        amount: Math.round(Number(ap.transaction_amount ?? 0) * 100), currency: ap.currency_id ?? "USD", expires_at: plus(33) });
      await admin.from("subscriptions").update({ status: "active", trial: false, updated_at: new Date().toISOString() }).eq("id", row.id);
      return new Response("ok");
    }
    return new Response("ok");
  } catch (e) {
    return new Response(JSON.stringify({ error: String((e as Error)?.message ?? e) }), { status: 500 });
  }
});
