/*! coi-serviceworker v0.1.7 - Guido Zuidhof, licensed under MIT */
/*
 * Adds COOP/COEP headers via a service worker for sites that can't set them
 * server-side (e.g. GitHub Pages). Required by WebContainers.
 * Source: https://github.com/gzuidhof/coi-serviceworker
 */
if (typeof window === 'undefined') {
  self.addEventListener("install", () => self.skipWaiting());
  self.addEventListener("activate", (e) => e.waitUntil(self.clients.claim()));
  self.addEventListener("message", (ev) => {
    if (ev.data && ev.data.type === "deregister") {
      self.registration
        .unregister()
        .then(() => self.clients.matchAll())
        .then((clients) => clients.forEach((client) => client.navigate(client.url)));
    }
  });
  self.addEventListener("fetch", function (e) {
    if (
      e.request.cache === "only-if-cached" &&
      e.request.mode !== "same-origin"
    ) {
      return;
    }
    e.respondWith(
      fetch(e.request).then((response) => {
        if (response.status === 0) return response;
        const newHeaders = new Headers(response.headers);
        newHeaders.set("Cross-Origin-Embedder-Policy", "require-corp");
        newHeaders.set("Cross-Origin-Opener-Policy", "same-origin");
        return new Response(response.body, {
          status: response.status,
          statusText: response.statusText,
          headers: newHeaders,
        });
      })
    );
  });
} else {
  (async function () {
    if (
      window.crossOriginIsolated !== false ||
      window.crossOriginIsolated === undefined
    ) {
      return;
    }
    const registration = await navigator.serviceWorker.register(
      window.document.currentScript.src
    );
    if (registration.active && !navigator.serviceWorker.controller) {
      window.location.reload();
    }
  })();
}
