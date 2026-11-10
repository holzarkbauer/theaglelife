// Supabase Edge Function «visionboard»: puente entre The Eagle Life y el estudio de 4haus (imágenes, música y voz).
// El navegador nunca ve la llave de 4haus: vive en los secretos de Supabase.
// Secretos (Edge Functions → Secrets):
//   FOURHAUS_API_URL  → ej. https://api.4haus.us   (cuando 4haus publique su API)
//   FOURHAUS_API_KEY  → la llave de cliente que 4haus le entregue a The Eagle Life
// Mientras no existan, la función responde { connected:false } y la app deja subir fotos propias.
// Contrato esperado de 4haus (ver PROMPT-4HAUS.md):
//   POST {URL}/v1/images  { prompt, style, aspect_ratio, reference_image_url?, user_ref, client_ref } → { job_id } o { images:[{url}] }
//   GET  {URL}/v1/jobs/{id}                                                                     → { status:"queued|running|succeeded|failed", images?:[{url}], error? }
//   GET  {URL}/v1/music?mood=wake|exercise|goal|focus|prayer&minutes=N                          → { tracks:[{id,title,url,duration,license}] }
//   POST {URL}/v1/voice   { text, voice, language:"es" }                                         → { url }
//   GET  {URL}/v1/voices?language=es                                                           → { voices:[{id,name,gender,description,sample_url}] }
import { createClient } from "npm:@supabase/supabase-js@2";

const LIMIT = [0, 3, 12, 40];          // imágenes IA por mes: Gratis, Prueba, Semillas, Eagle (se cambia en app_settings: vision_images)
const STYLE: Record<string, string> = {
  real: "photorealistic, natural light, 35mm, high detail",
  cine: "cinematic still, warm golden hour light, shallow depth of field, film grain",
  ilus: "soft painterly illustration, gentle colors, storybook style",
  oleo: "classical oil painting, rich textures, warm palette",
};
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
const S = (v: unknown, n: number) => String(v ?? "").slice(0, n);

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const auth = req.headers.get("Authorization") ?? "";
    const asUser = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: auth } } });
    const { data: { user } } = await asUser.auth.getUser();
    if (!user) return json({ error: "Inicia sesión para usar tu Vision Board." }, 401);
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const b: any = await req.json().catch(() => ({}));
    const API = (Deno.env.get("FOURHAUS_API_URL") ?? "").replace(/\/$/, ""), KEY = Deno.env.get("FOURHAUS_API_KEY") ?? "";
    const connected = !!(API && KEY);
    const { data: t } = await admin.rpc("tier_of", { uid: user.id });
    const tier = Math.min(3, Math.max(0, Number(t ?? 0)));
    let limits = LIMIT;
    const { data: st } = await admin.from("app_settings").select("value").eq("key", "vision_images").maybeSingle();
    if (Array.isArray(st?.value) && st.value.length === 4) limits = st.value.map(Number);
    const month = new Date().toISOString().slice(0, 8) + "01";
    const { data: row } = await admin.from("ai_tokens").select("images").eq("user_id", user.id).eq("month", month).maybeSingle();
    const used = Number(row?.images ?? 0), limit = limits[tier];
    const quota = { used, limit, left: Math.max(0, limit - used) };
    const call = async (path: string, init: RequestInit = {}) => {
      const r = await fetch(API + path, { ...init, headers: { Authorization: "Bearer " + KEY, "Content-Type": "application/json", ...(init.headers ?? {}) } });
      const out: any = await r.json().catch(() => ({}));
      if (!r.ok) throw new Error(out?.error?.message ?? out?.error ?? ("4haus respondió " + r.status));
      return out;
    };
    // Guarda la imagen generada en el almacenamiento privado del usuario y devuelve un enlace temporal
    const keep = async (imgUrl: string, dreamId: string) => {
      const r = await fetch(imgUrl);
      if (!r.ok) throw new Error("No se pudo descargar la imagen generada.");
      const path = user.id + "/" + S(dreamId, 40).replace(/[^\w-]/g, "") + "-" + Date.now() + ".jpg";
      const { error } = await admin.storage.from("vision").upload(path, await r.arrayBuffer(), { contentType: r.headers.get("content-type") ?? "image/jpeg", upsert: true });
      if (error) throw error;
      await admin.rpc("add_vision_image", { uid: user.id });
      const { data: s } = await admin.storage.from("vision").createSignedUrl(path, 3600);
      return { path, url: s?.signedUrl, quota: { used: used + 1, limit, left: Math.max(0, limit - used - 1) } };
    };

    if (b.action === "status") return json({ connected, quota, tier });
    if (!connected) return json({ error: "El estudio de imágenes de 4haus aún no está conectado. Mientras, puedes subir tus propias fotos.", code: "not_connected" }, 503);

    if (b.action === "image") {
      if (limit <= 0) return json({ error: "Las imágenes con IA se activan con la prueba de 7 días.", code: "needs_plan" }, 402);
      if (used >= limit) return json({ error: "Usaste tus " + limit + " imágenes de este mes. Se renuevan el día 1.", code: "quota", quota }, 429);
      const prompt = S(b.prompt, 600).trim();
      if (prompt.length < 8) return json({ error: "Describe tu sueño con un poco más de detalle." }, 400);
      let ref: string | undefined;
      if (b.ref_path) {
        const p = S(b.ref_path, 200);
        if (!p.startsWith(user.id + "/")) return json({ error: "Foto no válida." }, 400);
        const { data: s } = await admin.storage.from("vision").createSignedUrl(p, 900);
        ref = s?.signedUrl;
      }
      const full = prompt + ". Uplifting, hopeful, wholesome, family friendly. " + (STYLE[String(b.style)] ?? STYLE.real) +
        (ref ? ". Keep the person from the reference photo recognizable as the main subject." : "");
      const out = await call("/v1/images", { method: "POST", body: JSON.stringify({
        prompt: full, style: S(b.style, 20), aspect_ratio: "4:5", reference_image_url: ref, user_ref: user.id, client_ref: "theaglelife:" + S(b.dream_id, 40),
      }) });
      if (out.images?.[0]?.url) return json(await keep(out.images[0].url, b.dream_id));
      if (out.job_id) return json({ job: out.job_id });
      return json({ error: "4haus no devolvió una imagen." }, 502);
    }
    if (b.action === "job") {
      const out = await call("/v1/jobs/" + encodeURIComponent(S(b.job, 120)));
      if (out.status === "succeeded" && out.images?.[0]?.url) return json(await keep(out.images[0].url, b.dream_id));
      if (out.status === "failed") return json({ error: out.error ?? "No se pudo crear la imagen. Prueba con otra descripción." }, 422);
      return json({ job: b.job, status: out.status });
    }
    if (b.action === "music") {
      if (tier < 1) return json({ error: "La música de 4haus es parte de los planes.", code: "needs_plan" }, 402);
      const out = await call("/v1/music?mood=" + encodeURIComponent(S(b.mood, 20)) + "&minutes=" + Math.min(90, Math.max(1, Number(b.minutes) || 10)));
      return json({ tracks: (out.tracks ?? []).slice(0, 10) });
    }
    // Catálogo de voces de 4haus (para que el administrador las agregue desde el Backoffice)
    if (b.action === "voices") {
      const { data: isAdm } = await asUser.rpc("is_admin");
      if (!isAdm) return json({ error: "Solo el administrador puede ver el catálogo de voces." }, 403);
      const out = await call("/v1/voices?language=es");
      return json({ voices: (out.voices ?? []).slice(0, 200) });
    }
    if (b.action === "voice") {
      // b.voice_id = id de la voz en The Eagle Life (tabla voices). Se respeta el plan mínimo de cada voz.
      let vid = S(b.voice, 60), minTier = 1;
      if (b.voice_id) {
        const { data: v } = await admin.from("voices").select("provider_voice_id,min_tier,active,provider").eq("id", S(b.voice_id, 40)).maybeSingle();
        if (!v || !v.active || v.provider !== "4haus") return json({ error: "Esa voz ya no está disponible." }, 404);
        vid = v.provider_voice_id; minTier = Number(v.min_tier ?? 1);
      }
      if (tier < minTier) return json({ error: "Esa voz es parte de los planes.", code: "needs_plan" }, 402);
      const out = await call("/v1/voice", { method: "POST", body: JSON.stringify({ text: S(b.text, 1500), voice: vid || "es-calida", language: "es" }) });
      return json({ url: out.url });
    }
    return json({ error: "Acción no válida." }, 400);
  } catch (e) {
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
