// Supabase Edge Function «coach»: el agente de IA de theaglelife.com/app (coach de 90 días, guías y agente de estudio).
// Conversación: Claude Haiku 5.5. Razonamiento avanzado (plan de 90 días, semanas y evaluaciones de las guías): Claude Opus 5.5.
// La llave vive en el secreto ANTHROPIC_API_KEY (Edge Functions → Secrets). Nunca en el navegador.
// Límites por mes según el plan (se cambian en Backoffice → Ajustes): 0 Gratis · 1 Prueba · 2 Semillas · 3 Eagle
import { createClient } from "npm:@supabase/supabase-js@2";

const MODEL = "claude-haiku-5-5";
const MODEL_ADV = "claude-opus-5-5";
const ADV_MODES = ["plan", "week", "eval"];             // modos que usan Opus
const MAX_TOKENS = 8000;                               // tope por respuesta
const MONTHLY = [0, 600_000, 4_000_000, 8_000_000];    // tokens Haiku por mes
const MONTHLY_OPUS = [0, 15_000, 115_000, 330_000];    // tokens Opus por mes
// Tope para la suma de TODOS los usuarios gratuitos en el mes (cámbialo con el secreto FREE_POOL_TOKENS)
const FREE_POOL = Number(Deno.env.get("FREE_POOL_TOKENS") ?? 20_000_000);
const DAILY_CALLS = 300;                               // freno anti-abuso

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Método no permitido." }, 405);
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const auth = req.headers.get("Authorization") ?? "";
    const sb = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: auth } } });
    const { data: u } = await sb.auth.getUser(auth.replace(/^Bearer\s+/i, ""));
    const user = u?.user;
    if (!user) return json({ error: "Inicia sesión para usar el agente." }, 401);
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    const body: any = await req.json();
    const { data: tierData } = await admin.rpc("tier_of", { uid: user.id });
    const tier = Number(tierData) || 0;
    // Ajustes del backoffice (si existen) reemplazan los valores por defecto
    let monthly = MONTHLY, monthlyOpus = MONTHLY_OPUS, freePool = FREE_POOL;
    const { data: st } = await admin.from("app_settings").select("key,value").in("key", ["monthly_tokens", "opus_tokens", "free_pool_tokens"]);
    for (const row of st ?? []) {
      if (row.key === "monthly_tokens" && Array.isArray(row.value) && row.value.length === 4) monthly = row.value.map(Number);
      if (row.key === "opus_tokens" && Array.isArray(row.value) && row.value.length === 4) monthlyOpus = row.value.map(Number);
      if (row.key === "free_pool_tokens" && Number(row.value) > 0) freePool = Number(row.value);
    }
    const ti = Math.min(3, Math.max(0, tier));
    const limit = monthly[ti], limitOpus = monthlyOpus[ti];
    const month = new Date().toISOString().slice(0, 8) + "01";
    const { data: row } = await admin.from("ai_tokens").select("tokens,opus").eq("user_id", user.id).eq("month", month).maybeSingle();
    const used = Number(row?.tokens ?? 0), usedOpus = Number(row?.opus ?? 0);
    const meter = (u = used, o = usedOpus) => ({ used: u, limit, opus: o, opus_limit: limitOpus, tier });

    if (body.mode === "usage") return json({ tokens: meter() });
    if (body.mode === "ping") return json({ ok: true, key: !!Deno.env.get("ANTHROPIC_API_KEY"), tier, tokens: meter() });
    if (limit <= 0 && limitOpus <= 0)
      return json({ error: "La IA se activa con la prueba de 7 días ($1). Después sigue con el plan Semillas ($7 al mes).", code: "needs_plan", tokens: meter() }, 402);

    const { data: calls, error: e1 } = await sb.rpc("bump_ai_usage");
    if (e1) return json({ error: "No se pudo registrar el uso: " + e1.message }, 500);
    if ((calls as number) > DAILY_CALLS) return json({ error: "Demasiadas consultas hoy. Vuelve mañana." }, 429);

    if (tier === 0 && limit > 0) {
      const { data: pool } = await admin.from("ai_global").select("free_tokens").eq("month", month).maybeSingle();
      if (Number(pool?.free_tokens ?? 0) >= freePool)
        return json({ error: "La IA gratuita de este mes ya se usó por completo. Activa la prueba de 7 días para seguir hoy.", code: "needs_plan", tokens: meter() }, 429);
    }
    // Opus para razonamiento avanzado; si se acabó su cupo, se usa Haiku y se avisa
    const want = Math.min(Math.max(Number(body.max_tokens) || 900, 100), MAX_TOKENS);
    let useOpus = ADV_MODES.includes(String(body.mode)) && limitOpus - usedOpus >= Math.min(want, 4000);
    let notice = "";
    if (ADV_MODES.includes(String(body.mode)) && !useOpus && limitOpus > 0) notice = "Usaste tu razonamiento avanzado del mes; esta respuesta la preparó el modelo rápido.";
    if (!useOpus && used >= limit) {
      return json({ error: "Usaste los " + limit.toLocaleString("es") + " tokens de IA de tu plan este mes. Se renuevan el día 1, o puedes subir de plan.", code: "quota", tokens: meter() }, 429);
    }

    const system = String(body.system ?? "").slice(0, 20000);
    const messages = (Array.isArray(body.messages) ? body.messages : [])
      .filter((m: any) => (m?.role === "user" || m?.role === "assistant") && typeof m?.content === "string")
      .slice(-40)
      .map((m: any) => ({ role: m.role, content: m.content.slice(0, 40000) }));
    while (messages.length && messages[0].role !== "user") messages.shift();
    if (!messages.length) return json({ error: "Conversación vacía." }, 400);
    const left = useOpus ? limitOpus - usedOpus : limit - used;
    const max_tokens = Math.min(Math.max(Number(body.max_tokens) || 900, 100), MAX_TOKENS, Math.max(300, left));

    const key = Deno.env.get("ANTHROPIC_API_KEY");
    if (!key) return json({ error: "Falta configurar el secreto ANTHROPIC_API_KEY en Supabase." }, 500);
    const r = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({ model: useOpus ? MODEL_ADV : MODEL, max_tokens, system, messages }),
    });
    const out: any = await r.json();
    if (!r.ok) {
      const m = String(out?.error?.message ?? ("error " + r.status));
      const why = r.status === 401 ? "La clave ANTHROPIC_API_KEY no es válida. Revísala en Supabase → Edge Functions → Secrets."
        : r.status === 429 ? "Hay muchas consultas al mismo tiempo. Intenta en un minuto."
        : /credit|billing|spend/i.test(m) ? "La cuenta de Anthropic no tiene saldo o llegó a su límite de gasto (platform.claude.com → Billing)."
        : "Claude: " + m;
      return json({ error: why }, 502);
    }
    const spent = Number(out.usage?.input_tokens ?? 0) + Number(out.usage?.output_tokens ?? 0);
    const { data: tot } = await admin.rpc("add_ai_usage", { uid: user.id, n_haiku: useOpus ? 0 : spent, n_opus: useOpus ? spent : 0 });
    if (tier === 0) await admin.rpc("add_free_pool", { n: spent });
    const text = (out.content ?? []).filter((c: any) => c.type === "text").map((c: any) => c.text).join("");
    const t: any = tot ?? {};
    return json({ text, stop: out.stop_reason, model: useOpus ? "opus" : "haiku", notice,
      tokens: meter(Number(t.haiku ?? used + (useOpus ? 0 : spent)), Number(t.opus ?? usedOpus + (useOpus ? spent : 0))) });
  } catch (e) {
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
