// Supabase Edge Function «mercadopago»: pagos con Mercado Pago (suscripciones mensuales y libros).
// Secretos (Supabase → Edge Functions → Secrets):
//   MP_ACCESS_TOKEN → Access Token de PRODUCCIÓN (o de prueba: TEST-…) de tu cuenta de Mercado Pago
//                     (Mercado Pago Developers → Tus integraciones → tu aplicación → Credenciales)
//   MP_CURRENCY     → opcional, "USD" (por defecto) o "PEN". Si Mercado Pago rechaza USD en tu cuenta, cámbialo a PEN.
//   APP_URL         → opcional, por defecto https://www.theaglelife.com/app/
// Cómo funciona: la función crea el pago en Mercado Pago y devuelve un enlace (init_point). La app lleva al usuario ahí,
// paga, y vuelve a la app. La confirmación real llega a la función «mp-webhook», que pregunta el estado a Mercado Pago.
// Prueba: con Mercado Pago la prueba es de 7 días GRATIS y luego Semillas (Mercado Pago no permite un primer cobro distinto de $1).
import { createClient } from "npm:@supabase/supabase-js@2";

const USD: Record<string, number> = { prueba: 7, semillas: 7, eagle_mes: 17 };
const NAME: Record<string, string> = { prueba: "The Eagle Life · Semillas (7 días gratis)", semillas: "The Eagle Life · Semillas", eagle_mes: "The Eagle Life · Eagle" };
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const asUser = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } });
    const { data: { user } } = await asUser.auth.getUser();
    if (!user) return json({ error: "Inicia sesión para pagar." }, 401);
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const token = Deno.env.get("MP_ACCESS_TOKEN");
    const b: any = await req.json().catch(() => ({}));
    if (b.ping) return json(token ? { ok: true } : { error: "Falta configurar MP_ACCESS_TOKEN en Supabase." }, token ? 200 : 500);
    if (!token) return json({ error: "Falta configurar MP_ACCESS_TOKEN en Supabase." }, 500);
    const currency = (Deno.env.get("MP_CURRENCY") ?? "USD").toUpperCase() === "PEN" ? "PEN" : "USD";
    const appUrl = (Deno.env.get("APP_URL") ?? "https://www.theaglelife.com/app/").replace(/\/?$/, "/");
    const mp = async (path: string, method = "POST", body?: unknown) => {
      const r = await fetch("https://api.mercadopago.com" + path, { method, headers: { Authorization: "Bearer " + token, "Content-Type": "application/json", "X-Idempotency-Key": crypto.randomUUID() }, body: body ? JSON.stringify(body) : undefined });
      const out: any = await r.json().catch(() => ({}));
      if (!r.ok) throw new Error("Mercado Pago: " + (out?.message ?? out?.error ?? r.status) + (/currency/i.test(JSON.stringify(out)) ? " (prueba MP_CURRENCY=PEN)" : ""));
      return out;
    };
    let pen: any = { fx: 3.8, semillas: 2700, eagle_mes: 6500 };
    if (currency === "PEN") { const { data: ps } = await admin.from("app_settings").select("value").eq("key", "prices_pen").maybeSingle(); if (ps?.value) pen = { ...pen, ...ps.value }; }
    const notify = url + "/functions/v1/mp-webhook";

    // ---- Cancelar la suscripción de Mercado Pago ----
    if (b.action === "cancel") {
      const { data: subs } = await admin.from("subscriptions").select("id,mp_preapproval").eq("user_id", user.id).eq("provider", "mp").eq("status", "active");
      for (const s of subs ?? []) {
        if (s.mp_preapproval) await mp("/preapproval/" + s.mp_preapproval, "PUT", { status: "cancelled" });
        await admin.from("subscriptions").update({ status: "canceled", updated_at: new Date().toISOString() }).eq("id", s.id);
      }
      return json({ canceled: true });
    }

    // ---- Libro de la tienda: pago único con Checkout Pro ----
    if (b.action === "book") {
      const { data: bk } = await admin.from("store_books").select("id,title,price_cents,active,visibility").eq("id", String(b.book_id)).maybeSingle();
      if (!bk || !bk.active || bk.visibility !== "public") return json({ error: "Ese libro no está a la venta." }, 404);
      const price = currency === "PEN" ? Math.round(bk.price_cents * Number(pen.fx || 3.8) / 10) / 10 : bk.price_cents / 100;
      const pref = await mp("/checkout/preferences", "POST", {
        items: [{ id: bk.id, title: bk.title, quantity: 1, unit_price: price, currency_id: currency }],
        payer: { email: user.email },
        external_reference: "book:" + user.id + ":" + bk.id,
        back_urls: { success: appUrl + "?pago=mp#store", failure: appUrl + "?pago=mp_error#store", pending: appUrl + "?pago=mp#store" },
        auto_return: "approved",
        notification_url: notify,
        statement_descriptor: "EAGLE LIFE",
      });
      return json({ url: pref.init_point });
    }

    // ---- Planes: suscripción mensual (preapproval) ----
    const planId = String(b.plan ?? "");
    if (!USD[planId]) return json({ error: "Plan no válido." }, 400);
    if (planId === "prueba") {
      const { data: used } = await admin.from("memberships").select("id").eq("user_id", user.id).eq("plan", "prueba").limit(1);
      if (used?.length) return json({ error: "La prueba de 7 días se usa una sola vez. Elige Semillas o Eagle." }, 409);
    }
    const subPlan = planId === "eagle_mes" ? "eagle_mes" : "semillas";
    const amount = currency === "PEN" ? Number(pen[subPlan]) / 100 : USD[planId];
    const auto: any = { frequency: 1, frequency_type: "months", transaction_amount: amount, currency_id: currency };
    if (planId === "prueba") auto.free_trial = { frequency: 7, frequency_type: "days" };
    const pre = await mp("/preapproval", "POST", {
      reason: NAME[planId],
      external_reference: "sub:" + user.id + ":" + planId,
      payer_email: S(b.email, 120) || user.email,
      auto_recurring: auto,
      back_url: appUrl + "?pago=mp#pay",
      status: "pending",
    });
    await admin.from("subscriptions").insert({ user_id: user.id, plan: subPlan, provider: "mp", currency, mp_preapproval: pre.id, status: "pending", trial: planId === "prueba" });
    return json({ url: pre.init_point });
  } catch (e) {
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
const S = (v: unknown, n: number) => String(v ?? "").slice(0, n);
