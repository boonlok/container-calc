/* ============================================================
   PDF 中文字体: 每份 PDF 只嵌入「实际用到的字」
   ============================================================
   基础字体 (fonts/NotoSansSC-subset.ttf, ~1.4MB, Noto Sans SC, SIL OFL) 只在导出 PDF 时才下载 (之后浏览器会缓存),
   再用 harfbuzz 的 WebAssembly 版 hb-subset 现场裁成只含本份 PDF 用到的字 (通常几十 KB) 交给 jsPDF 嵌入。
   做法参考 subset-font (MIT, papandreou) 与 harfbuzzjs (MIT)。任何一步失败, Export.html 都会退回「文字转图片」的旧做法。
   ============================================================ */
(function () {
  'use strict';
  let wasmPromise = null, basePromise = null;

  function cfg() { return window.PDF_CJK || null; }

  function initWasm() {
    if (!wasmPromise) {
      wasmPromise = fetch(cfg().wasmUrl).then(function (r) {
        if (!r.ok) throw new Error('wasm ' + r.status);
        return r.arrayBuffer();
      }).then(function (buf) { return WebAssembly.instantiate(buf); }).then(function (res) {
        const ex = res.instance.exports;
        ex._initialize();
        return ex;
      });
    }
    return wasmPromise;
  }

  // 载入基础字体与它涵盖的字符清单
  function load() {
    if (!cfg()) return Promise.reject(new Error('no PDF_CJK config'));
    if (!basePromise) {
      basePromise = Promise.all([
        fetch(cfg().fontUrl).then(function (r) { if (!r.ok) throw new Error('font ' + r.status); return r.arrayBuffer(); }),
        fetch(cfg().coverUrl).then(function (r) { if (!r.ok) throw new Error('cover ' + r.status); return r.text(); }),
        initWasm(),
      ]).then(function (v) { return { font: new Uint8Array(v[0]), chars: new Set(Array.from(v[1])) }; });
      basePromise.catch(function () { basePromise = null; }); // 失败后下次可重试
    }
    return basePromise;
  }

  // 回传只含 text 里字符的 TTF (Uint8Array)
  async function subset(text) {
    const base = await load();
    const hb = await initWasm();
    const heap = function () { return new Uint8Array(hb.memory.buffer); }; // wasm 内存增长时旧的 view 会失效, 每次重取
    const input = hb.hb_subset_input_create_or_fail();
    if (!input) throw new Error('hb_subset_input_create_or_fail failed');
    const fontPtr = hb.malloc(base.font.byteLength);
    heap().set(base.font, fontPtr);
    const blob = hb.hb_blob_create(fontPtr, base.font.byteLength, 2 /* WRITABLE */, 0, 0);
    const face = hb.hb_face_create(blob, 0);
    hb.hb_blob_destroy(blob);
    const unicodes = hb.hb_subset_input_unicode_set(input);
    for (const ch of text) hb.hb_set_add(unicodes, ch.codePointAt(0));
    hb.hb_subset_input_set_flags(input, hb.hb_subset_input_get_flags(input) | 0x1 /* NO_HINTING */);
    let sub = 0;
    try { sub = hb.hb_subset_or_fail(face, input); } finally { hb.hb_subset_input_destroy(input); }
    if (!sub) { hb.hb_face_destroy(face); hb.free(fontPtr); throw new Error('hb_subset_or_fail failed'); }
    const result = hb.hb_face_reference_blob(sub);
    const off = hb.hb_blob_get_data(result, 0), len = hb.hb_blob_get_length(result);
    const out = heap().slice(off, off + len);
    hb.hb_blob_destroy(result); hb.hb_face_destroy(sub); hb.hb_face_destroy(face); hb.free(fontPtr);
    if (!len) throw new Error('empty subset');
    return out;
  }

  window.PdfFont = { load: load, subset: subset };
})();
