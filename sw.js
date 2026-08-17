// Service worker — offline app shell + dictionary cache.
// Bump VERSION whenever a precached file changes so clients refresh it.
const VERSION = "v1.9";
const SHELL = "shell-" + VERSION;
const RUNTIME = "runtime-" + VERSION;
const PRECACHE = [
  "./",
  "index.html",
  "config.js",
  "dict.json",
  "vendor/firebase-bundle-2.js",
  "vendor/fsrs-bundle.js",
  "manifest.json",
  "icons/favicon.svg",
  "icons/icon-192.png",
  "icons/icon-512.png",
];

self.addEventListener("install", e => {
  e.waitUntil(caches.open(SHELL).then(c => c.addAll(PRECACHE)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== SHELL && k !== RUNTIME).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

// index.html and config.js should update promptly; the dictionary and vendor
// bundle are immutable (renamed when they change), so cache-first is safe.
const NETWORK_FIRST = new Set(["/", "/index.html", "/config.js"]);
// Fonts plus pronunciation audio (Wikimedia Commons lookups and files) —
// cache-first so heard-once words replay offline.
const FONT_HOSTS = new Set(["fonts.googleapis.com", "fonts.gstatic.com",
  "commons.wikimedia.org", "upload.wikimedia.org"]);

self.addEventListener("fetch", e => {
  const req = e.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);

  if (url.origin === location.origin){
    if (req.mode === "navigate" || NETWORK_FIRST.has(url.pathname)){
      e.respondWith(
        fetch(req).then(res => {
          const copy = res.clone();
          caches.open(SHELL).then(c => c.put(req, copy));
          return res;
        }).catch(() =>
          caches.match(req).then(hit => hit || caches.match("index.html")))
      );
    } else {
      e.respondWith(
        caches.match(req).then(hit => hit || fetch(req).then(res => {
          const copy = res.clone();
          caches.open(RUNTIME).then(c => c.put(req, copy));
          return res;
        }))
      );
    }
    return;
  }

  if (FONT_HOSTS.has(url.hostname)){
    e.respondWith(
      caches.match(req).then(hit => hit || fetch(req).then(res => {
        const copy = res.clone();
        caches.open(RUNTIME).then(c => c.put(req, copy));
        return res;
      }))
    );
  }
  // Anything else (Firebase auth/Firestore) goes straight to the network.
});
