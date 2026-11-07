// 把 Apps Script 版的 Index.html 与各个 include 档合成一个静态 dist/index.html,
// 并在 Auth 之前注入 Supabase 的 SDK、你的 config.js 与适配层 api-supabase.js。
// 用法: node build.js     (产出 web/dist/, 整个 dist 目录丢到任何静态托管即可)
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(here, '..');
const dist = path.join(here, 'dist');

const SUPABASE_SDK = '<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/dist/umd/supabase.js" ' +
  'integrity="sha384-0w2KAL2YHP6wKOkUDzkCDGgVvfmHnj02DHeQ6XcHOgTfFsGyonKOpShMH1x6nk9o" crossorigin="anonymous"></script>';

let configFile = path.join(here, 'config.js');
if (!fs.existsSync(configFile)) {
  console.warn('! 找不到 web/config.js, 暂用 config.example.js (请复制一份并填入你的 Supabase 网址与 anon key)');
  configFile = path.join(here, 'config.example.js');
}
const config = fs.readFileSync(configFile, 'utf8');
const shim = fs.readFileSync(path.join(here, 'api-supabase.js'), 'utf8');
const pdfFontJs = fs.readFileSync(path.join(here, 'vendor', 'pdf-font.js'), 'utf8');

// 程序里写死的中文字 (备注、标签、表头...): PDF 字体子集一定要包含它们
const CJK_RE = /[①-⑳　-ヿ一-鿿＀-￯]/g;
const staticChars = [...new Set(['Index', 'Auth', 'Render', 'Viewer3D', 'Export', 'JavaScript', 'Effects', 'Stylesheet']
  .flatMap((n) => fs.readFileSync(path.join(root, n + '.html'), 'utf8').match(CJK_RE) || []))].join('');
const pdfCfg = '<script>window.PDF_CJK = ' + JSON.stringify({
  fontUrl: 'fonts/NotoSansSC-subset.ttf', coverUrl: 'fonts/NotoSansSC-subset.txt', wasmUrl: 'vendor/harfbuzz-subset.wasm', staticChars,
}) + ';</script>\n<script>\n' + pdfFontJs + '\n</script>\n';

let html = fs.readFileSync(path.join(root, 'Index.html'), 'utf8');
html = html.replace(/<\?!= include\('(\w+)'\); \?>/g, (m, name) => {
  const body = fs.readFileSync(path.join(root, name + '.html'), 'utf8');
  if (name === 'Auth') return pdfCfg + SUPABASE_SDK + '\n<script>\n' + config + '\n</script>\n<script>\n' + shim + '\n</script>\n' + body;
  return body;
});
if (/<\?/.test(html)) throw new Error('仍有未处理的 Apps Script 标签 <? ... ?>');
html = html.replace('<head>', '<head>\n  <title>集装箱装载计算器 Container Loading Calculator</title>\n  <meta name="viewport" content="width=device-width, initial-scale=1">');

fs.mkdirSync(dist, { recursive: true });
// PDF 中文字体与 wasm: 导出 PDF 时才会下载
for (const [from, to] of [['fonts/NotoSansSC-subset.ttf', 'fonts/NotoSansSC-subset.ttf'], ['fonts/NotoSansSC-subset.txt', 'fonts/NotoSansSC-subset.txt'], ['fonts/OFL.txt', 'fonts/OFL.txt'], ['vendor/harfbuzz-subset.wasm', 'vendor/harfbuzz-subset.wasm']]) {
  fs.mkdirSync(path.dirname(path.join(dist, to)), { recursive: true });
  fs.copyFileSync(path.join(here, from), path.join(dist, to));
}
fs.writeFileSync(path.join(dist, 'index.html'), html);
// Cloudflare Pages / Netlify 会读取 _headers: 禁止被别的网站 iframe 嵌入 (点击劫持), 其余常见安全标头
fs.writeFileSync(path.join(dist, '_headers'),
  '/*\n  X-Frame-Options: DENY\n  Content-Security-Policy: frame-ancestors \'none\'\n  X-Content-Type-Options: nosniff\n  Referrer-Policy: strict-origin-when-cross-origin\n');
console.log('OK  dist/index.html', (html.length / 1024).toFixed(0) + ' KB');
