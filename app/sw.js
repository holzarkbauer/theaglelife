// Service worker: permite instalar la app y leer la Biblia sin conexión.
const V = "eagle-v16";
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", e => e.waitUntil(
  caches.keys().then(ks => Promise.all(ks.filter(k => k !== V).map(k => caches.delete(k)))).then(() => self.clients.claim())));
self.addEventListener("fetch", e => {
  const u = new URL(e.request.url);
  if (e.request.method !== "GET" || u.origin !== location.origin) return;
  if (u.pathname.includes("/biblia/")) {            // la Biblia: primero caché
    e.respondWith(caches.open(V).then(c => c.match(e.request).then(r => r || fetch(e.request).then(res => { if (res.ok) c.put(e.request, res.clone()); return res; }))));
    return;
  }
  e.respondWith(fetch(e.request).then(res => {      // la app: primero red (siempre la versión nueva)
    if (res.ok) { const cl = res.clone(); caches.open(V).then(c => c.put(e.request, cl)); }
    return res;
  }).catch(() => caches.match(e.request)));
});
