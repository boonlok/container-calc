// 离线支援: 货柜里常常没有讯号。打开过一次之后, 没网络也能打开装柜画面 (进度本来就存在手机上)。
// 策略 = 网络优先: 有网络就拿最新版本 (部署后不会卡在旧版), 网络失败或太慢才用快取。
// 只处理本网站自己的档案; Supabase 等外部请求完全不经过这里。
const CACHE = 'container-calc-v1';
const SLOW_MS = 4000; // 已有快取时, 网络超过这么久没回应就先用快取

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));

function sameOrigin(url) {
  try { return new URL(url, self.location.href).origin === self.location.origin; } catch (_) { return false; }
}

async function remember(cache, req, res) {
  if (res && res.ok && res.type === 'basic' && res.status === 200) {
    try { await cache.put(req, res.clone()); } catch (_) { /* 空间不足等: 不影响使用 */ }
  }
}

async function networkFirst(req) {
  const cache = await caches.open(CACHE);
  const cached = await cache.match(req, { ignoreSearch: true });
  const network = fetch(req).then(async (res) => { await remember(cache, req, res); return res; });
  if (!cached) return network; // 第一次: 不设超时, 慢也要等它下载完
  const slow = new Promise((resolve) => setTimeout(() => resolve(cached), SLOW_MS));
  try {
    return await Promise.race([network, slow]);
  } catch (_) {
    return cached;
  }
}

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET' || !sameOrigin(req.url)) return;
  e.respondWith(networkFirst(req));
});

// 页面画好第一帧后, 把这次实际下载过的档案清单传过来, 一次补进快取
// (第一次打开时 service worker 还没接手, 那些档案不会自动进快取)
self.addEventListener('message', (e) => {
  const urls = (e.data && e.data.type === 'cache-urls' && Array.isArray(e.data.urls)) ? e.data.urls : [];
  e.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    for (const u of urls.slice(0, 200)) {
      if (!sameOrigin(u)) continue;
      const clean = u.split('#')[0];
      if (await cache.match(clean, { ignoreSearch: true })) continue;
      try { await remember(cache, new Request(clean), await fetch(clean)); } catch (_) { /* 略过 */ }
    }
  })());
});
