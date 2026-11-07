{{flutter_js}}
{{flutter_build_config}}
// 不使用 Flutter 自带的 service worker (已淘汰, 会和 sw.js 的离线快取互相取代); 离线快取由 sw.js 负责
_flutter.loader.load();
