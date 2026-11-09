// Supabase Edge Function «pago»: cobros con Culqi (planes mensuales, prueba de 7 días y libros de la tienda).
// Secretos (Supabase → Edge Functions → Secrets):
//   CULQI_SECRET_KEY            → llave secreta de Culqi (sk_test_… para probar, sk_live_… en producción)
//   CULQI_PLAN_SEMILLAS_TRIAL   → id del plan de Culqi "Semillas" $7/mes CON 7 días de prueba (pln_…)
//   CULQI_PLAN_SEMILLAS         → id del plan "Semillas" $7/mes sin prueba (pln_…)
//   CULQI_PLAN_EAGLE            → id del plan "Eagle" $17/mes (pln_…)
//   CULQI_PLAN_SEMILLAS_TRIAL_PEN, CULQI_PLAN_SEMILLAS_PEN, CULQI_PLAN_EAGLE_PEN → los mismos planes creados en SOLES
//   El usuario elige pagar en dólares (USD) o soles (PEN). Los precios en soles salen de app_settings → prices_pen.
//   RESEND_API_KEY / MAIL_FROM  → opcional, para enviar por correo el PDF de los libros comprados
// Prueba: se cobra $1 ahora y se crea la suscripción a "Semillas" con 7 días de prueba; el día 8 Culqi cobra $7 y cada mes después.
// Libros de la tienda: el precio sale de la tabla store_books (nunca del navegador).
import { createClient } from "npm:@supabase/supabase-js@2";

const PLANS: Record<string, { amount: number; days: number | null; name: string; sub?: string }> = {
  prueba: { amount: 100, days: 7, name: "Prueba 7 días", sub: "CULQI_PLAN_SEMILLAS_TRIAL" },
  semillas: { amount: 700, days: 31, name: "Semillas", sub: "CULQI_PLAN_SEMILLAS" },
  eagle_mes: { amount: 1700, days: 31, name: "Eagle", sub: "CULQI_PLAN_EAGLE" },
};
const TIER: Record<string, number> = { prueba: 1, semillas: 2, eagle_mes: 3 };
const API = "https://api.culqi.com/v2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
const S = (v: unknown, n = 80) => String(v ?? "").trim().slice(0, n);

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Método no permitido." }, 405);
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const auth = req.headers.get("Authorization") ?? "";
    const sb = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: auth } } });
    const { data: u } = await sb.auth.getUser(auth.replace(/^Bearer\s+/i, ""));
    const user = u?.user;
    if (!user) return json({ error: "Inicia sesión para pagar." }, 401);

    const b: any = await req.json();
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const sk = Deno.env.get("CULQI_SECRET_KEY");
    if (!sk) return json({ error: "Falta configurar CULQI_SECRET_KEY en Supabase." }, 500);
    const currency = b.currency === "PEN" ? "PEN" : "USD";
    let pen: any = { prueba: 400, semillas: 2700, eagle_mes: 6500, fx: 3.8 };
    if (currency === "PEN") { const { data: ps } = await admin.from("app_settings").select("value").eq("key", "prices_pen").maybeSingle(); if (ps?.value) pen = { ...pen, ...ps.value }; }
    const toPen = (usdCents: number) => Math.max(100, Math.round(usdCents * Number(pen.fx || 3.8) / 10) * 10);
    const culqi = async (path: string, method = "POST", body?: unknown) => {
      const r = await fetch(API + path, { method, headers: { Authorization: "Bearer " + sk, "Content-Type": "application/json" }, body: body ? JSON.stringify(body) : undefined });
      return { status: r.status, out: await r.json().catch(() => ({})) as any };
    };
    const fail = (out: any, d = "La tarjeta fue rechazada. No se hizo ningún cobro.") => json({ error: out?.user_message || out?.merchant_message || d }, 402);

    // ---- Cancelar la suscripción (el plan sigue hasta su fecha de vencimiento) ----
    if (b.cancel) {
      const { data: subs } = await admin.from("subscriptions").select("id,culqi_sub").eq("user_id", user.id).eq("status", "active");
      for (const s of subs ?? []) {
        if (s.culqi_sub) await culqi("/recurrent/subscriptions/" + s.culqi_sub, "DELETE");
        await admin.from("subscriptions").update({ status: "canceled", updated_at: new Date().toISOString() }).eq("id", s.id);
      }
      return json({ canceled: true });
    }
    if (!b.token) return json({ error: "Falta el token de la tarjeta." }, 400);

    // ---- Libro de la tienda ----
    let book: any = null;
    if (b.book_id) {
      const { data: bk } = await admin.from("store_books").select("id,title,author,price_cents,commission_pct,active,visibility").eq("id", String(b.book_id)).maybeSingle();
      if (!bk || !bk.active || bk.visibility !== "public") return json({ error: "Ese libro no está a la venta." }, 404);
      const { data: owned } = await admin.from("book_orders").select("id").eq("user_id", user.id).eq("book_id", bk.id).maybeSingle();
      if (owned) return json({ paid: true, book_id: bk.id });
      book = bk;
    }
    const planId = String(b.plan ?? "");
    const basePlan = book ? { amount: book.price_cents, days: null, name: "libro «" + book.title + "»" } as any : PLANS[planId];
    const plan = basePlan && currency === "PEN" ? { ...basePlan, amount: book ? toPen(book.price_cents) : Number(pen[planId]) || toPen(basePlan.amount), sub: basePlan.sub ? basePlan.sub + "_PEN" : undefined } : basePlan;
    if (!plan) return json({ error: "Plan no válido." }, 400);
    if (planId === "prueba") {
      const { data: used } = await admin.from("memberships").select("id").eq("user_id", user.id).eq("plan", "prueba").limit(1);
      if (used?.length) return json({ error: "La prueba de 7 días se usa una sola vez. Elige Semillas o Eagle." }, 409);
    }
    const anti = {
      first_name: S(b.first_name, 50), last_name: S(b.last_name, 50),
      phone_number: S(b.phone, 20).replace(/[^\d+]/g, ""), device_finger_print_id: S(b.deviceId, 80),
    };
    const email = S(b.email, 120) || user.email;

    // ---- Planes mensuales: cliente + tarjeta guardada + suscripción ----
    if (!book) {
      const planKey = Deno.env.get(plan.sub!);
      if (!planKey) return json({ error: "Falta configurar " + plan.sub + " en Supabase (id del plan creado en tu panel de Culqi)." }, 500);
      const { data: prev } = await admin.from("subscriptions").select("culqi_customer").eq("user_id", user.id).not("culqi_customer", "is", null).order("created_at", { ascending: false }).limit(1).maybeSingle();
      let customer = prev?.culqi_customer as string | undefined;
      if (!customer) {
        const c = await culqi("/customers", "POST", {
          first_name: anti.first_name || "Usuario", last_name: anti.last_name || "Semillas", email,
          address: S(b.address, 100) || "Lima", address_city: S(b.city, 40) || "Lima", country_code: S(b.country, 2) || "PE",
          phone_number: anti.phone_number || "999999999", metadata: { user_id: user.id },
        });
        if (c.out?.id) customer = c.out.id;
        else {
          const f = await culqi("/customers?email=" + encodeURIComponent(email), "GET");
          customer = f.out?.data?.[0]?.id;
          if (!customer) return fail(c.out, "No se pudo registrar tus datos de pago.");
        }
      }
      const cardBody: any = { customer_id: customer, token_id: S(b.token, 120) };
      if (b.auth3ds && typeof b.auth3ds === "object") cardBody.authentication_3DS = b.auth3ds;
      const card = await culqi("/cards", "POST", cardBody);
      if (!card.out?.id) {
        if (card.status === 200 || card.out?.action_code === "REVIEW") return json({ needs3ds: true });
        return fail(card.out);
      }
      // Prueba: cobro único de $1 a la tarjeta guardada
      let chargeId: string | null = null;
      if (planId === "prueba") {
        const ch = await culqi("/charges", "POST", {
          amount: plan.amount, currency_code: currency, email, source_id: card.out.id,
          description: "Semillas de Identidad - prueba 7 días", antifraud_details: anti, metadata: { user_id: user.id, plan: planId },
        });
        if (ch.status !== 201) return fail(ch.out);
        chargeId = ch.out.id ?? null;
      }
      const sub = await culqi("/recurrent/subscriptions/create", "POST", { card_id: card.out.id, plan_id: planKey, tyc: true, metadata: { user_id: user.id, plan: planId } });
      if (!sub.out?.id) {
        if (planId === "prueba") return json({ error: "Se cobró $1, pero no se pudo crear la suscripción mensual: " + (sub.out?.user_message || sub.out?.merchant_message || "error de Culqi") + ". Escríbenos con este código: " + chargeId }, 500);
        return fail(sub.out, "No se pudo crear la suscripción.");
      }
      const subPlan = planId === "eagle_mes" ? "eagle_mes" : "semillas";
      const next = sub.out.next_billing_date ? new Date(typeof sub.out.next_billing_date === "number" ? sub.out.next_billing_date * (sub.out.next_billing_date < 1e12 ? 1000 : 1) : sub.out.next_billing_date) : null;
      // Si cambia de plan (por ejemplo de Semillas a Eagle), se cancela la suscripción anterior en Culqi
      const { data: olds } = await admin.from("subscriptions").select("id,culqi_sub").eq("user_id", user.id).eq("status", "active");
      for (const o of olds ?? []) {
        if (o.culqi_sub && o.culqi_sub !== sub.out.id) await culqi("/recurrent/subscriptions/" + o.culqi_sub, "DELETE");
        await admin.from("subscriptions").update({ status: "replaced", updated_at: new Date().toISOString() }).eq("id", o.id);
      }
      await admin.from("subscriptions").insert({ user_id: user.id, plan: subPlan, provider: "culqi", currency, culqi_customer: customer, culqi_card: card.out.id, culqi_sub: sub.out.id, trial: planId === "prueba", next_billing: next && !isNaN(+next) ? next.toISOString() : null });
      const expires = new Date(Date.now() + plan.days * 864e5).toISOString();
      const { error } = await admin.from("memberships").insert({
        user_id: user.id, plan: planId, charge_id: chargeId ?? sub.out.id, subscription_id: sub.out.id,
        amount: planId === "prueba" ? plan.amount : plan.amount, currency, expires_at: expires,
      });
      if (error) return json({ error: "El pago se hizo pero no se pudo activar el plan. Escríbenos con este código: " + sub.out.id }, 500);
      const { data: t2 } = await admin.rpc("tier_of", { uid: user.id });
      return json({ paid: true, tier: t2, expires });
    }

    const payload: any = {
      amount: plan.amount,
      currency_code: currency,
      email,
      source_id: S(b.token, 120),
      description: "Semillas de Identidad - " + plan.name,
      antifraud_details: anti,
      metadata: { user_id: user.id, plan: "libro", book_id: book.id },
    };
    if (b.auth3ds && typeof b.auth3ds === "object") payload.authentication_3DS = b.auth3ds;
    const { status: rs, out } = await culqi("/charges", "POST", payload);
    const r = { status: rs };

    if (r.status === 201 && book) {
      const { error } = await admin.from("book_orders").insert({
        user_id: user.id, book_id: book.id, amount: plan.amount, currency, author_share_cents: Math.round(plan.amount * (100 - book.commission_pct) / 100), charge_id: out.id ?? null,
      });
      if (error) return json({ error: "El pago se hizo pero no se pudo registrar la compra. Escríbenos con este código: " + (out.id ?? "") }, 500);
      // Envío por correo del PDF (enlace válido 7 días)
      let emailed = false;
      const rk = Deno.env.get("RESEND_API_KEY");
      if (rk) {
        const { data: link } = await admin.storage.from("tienda").createSignedUrl(book.id + ".pdf", 7 * 86400);
        if (link?.signedUrl) {
          const to = S(b.email, 120) || user.email;
          const html = `<div style="font-family:Georgia,serif;max-width:560px;margin:auto;color:#2C2520">
            <h2 style="font-weight:400">Gracias por tu compra</h2>
            <p>Ya tienes <b>${book.title}</b>${book.author ? " de " + book.author : ""}.</p>
            <p><a href="${link.signedUrl}" style="background:#4A574D;color:#fff;padding:12px 18px;border-radius:999px;text-decoration:none">Descargar el PDF</a></p>
            <p style="font-size:13px;color:#6E6259">El enlace vence en 7 días. También puedes leerlo cuando quieras en theaglelife.com/app → Tienda → Mis compras.</p></div>`;
          const m = await fetch("https://api.resend.com/emails", {
            method: "POST",
            headers: { Authorization: "Bearer " + rk, "Content-Type": "application/json" },
            body: JSON.stringify({ from: Deno.env.get("MAIL_FROM") ?? "Semillas de Identidad <onboarding@resend.dev>", to: [to], subject: "Tu libro: " + book.title, html }),
          });
          emailed = m.ok;
          if (emailed) await admin.from("book_orders").update({ emailed: true }).eq("user_id", user.id).eq("book_id", book.id);
        }
      }
      return json({ paid: true, book_id: book.id, emailed });
    }
    if (r.status === 200) return json({ needs3ds: true }); // el banco pide autenticación 3DS
    return json({ error: out.user_message || out.merchant_message || "La tarjeta fue rechazada. No se hizo ningún cobro." }, 402);
  } catch (e) {
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
