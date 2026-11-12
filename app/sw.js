// Service worker: instalar la app y usarla sin internet (app, Biblia y libros descargados).
const V = "eagle-v24";                 // la app (se renueva en cada versión)
const BIBLIA = "eagle-biblia";         // Biblia: se conserva entre versiones
const LIBROS = "eagle-libros";         // libros guardados para leer sin internet: se conservan
self.addEventListener("install", e => e.waitUntil(
  caches.open(V).then(c => c.addAll(["./", "index.html", "config.js", "supabase.js", "manifest.webmanifest"].map(u => new Request(u, { cache: "reload" }))).catch(() => {})).then(() => self.skipWaiting())));
self.addEventListener("activate", e => e.waitUntil(
  caches.keys().then(ks => Promise.all(ks.filter(k => k.startsWith("eagle-v") && k !== V || k.startsWith("semillas")).map(k => caches.delete(k)))).then(() => self.clients.claim())));
self.addEventListener("fetch", e => {
  const u = new URL(e.request.url);
  if (e.request.method !== "GET" || u.origin !== location.origin) return;
  if (u.pathname.includes("/sonidos/") || u.pathname.includes("/fondos/")) return;   // audio y video en streaming
  if (u.pathname.includes("/biblia/")) {            // la Biblia: primero caché (y queda guardada)
    e.respondWith(caches.open(BIBLIA).then(c => c.match(e.request).then(r => r || fetch(e.request).then(res => { if (res.ok) c.put(e.request, res.clone()); return res; }))));
    return;
  }
  e.respondWith(fetch(e.request).then(res => {      // la app: primero red (siempre la versión nueva); sin internet, la guardada
    if (res.ok) { const cl = res.clone(); caches.open(V).then(c => c.put(e.request, cl)); }
    return res;
  }).catch(() => caches.match(e.request, { ignoreSearch: true }).then(r => r || (e.request.mode === "navigate" ? caches.match("index.html") : undefined))));
});
