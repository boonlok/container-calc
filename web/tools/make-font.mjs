// 产生 PDF 用的中文字体子集 fonts/NotoSansSC-subset.ttf (+ 字符清单 .txt)
// 来源字体: Noto Sans SC (SIL OFL 1.1), 可从 https://github.com/google/fonts/tree/main/ofl/notosanssc 下载 NotoSansSC[wght].ttf
// 用法: node tools/make-font.mjs <NotoSansSC[wght].ttf 的路径>      (需要 npm i -D subset-font)
// 处理: 1) 只保留 GB2312 一级常用字 + 全部 GB2312 符号 + 拉丁/标点/日文假名/全角字符
//       2) 删掉可变字体专用表 (gvar/HVAR/fvar...) 与排版表 (GPOS/GSUB...): jsPDF 只用默认字重的轮廓, 这些表只会增大体积
import subsetFont from 'subset-font';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const here = path.dirname(fileURLToPath(import.meta.url));
const src = process.argv[2];
if (!src) { console.error('用法: node tools/make-font.mjs <NotoSansSC[wght].ttf>'); process.exit(1); }

const dec = new TextDecoder('gb18030');
const range = (a, b) => { let s = ''; for (let c = a; c <= b; c++) s += String.fromCodePoint(c); return s; };
let chars = range(0x20, 0x7e);
const addGb = (hi0, hi1) => {
  for (let hi = hi0; hi <= hi1; hi++) for (let lo = 0xa1; lo <= 0xfe; lo++) {
    const s = dec.decode(new Uint8Array([hi, lo]));
    if (s.length === 1 && s !== '\ufffd') chars += s;
  }
};
addGb(0xa1, 0xa9);  // 符号区 (含 ①②③ 等)
addGb(0xb0, process.env.FONT_FULL ? 0xf7 : 0xd7);  // 一级汉字 3755 (FONT_FULL=1: 再加二级汉字 3008, 共 6763, Flutter 版用)
chars += '呎吋' + range(0xa0, 0xff) + range(0x2010, 0x2027) + range(0x2030, 0x203e) + range(0x2460, 0x2473) +
  range(0x3000, 0x303f) + range(0x3040, 0x30ff) + range(0xff01, 0xff5e) + '≤≥≠±×÷°℃²³µ→←↑↓✓✔';
chars = [...new Set(chars)].join('');

// variationAxes: 把可变字体固定在 Regular (wght=400) 并套用轮廓差量, noHinting: 去掉 hinting 指令 (PDF 用不到)
let ttf = await subsetFont(fs.readFileSync(src), chars, { targetFormat: 'truetype', variationAxes: { wght: 400 }, noHinting: true });

// 重建 TTF, 只留 jsPDF 需要的表
const KEEP = ['cmap', 'glyf', 'head', 'hhea', 'hmtx', 'loca', 'maxp', 'name', 'post', 'OS/2', 'prep', 'cvt ', 'fpgm'];
const buf = Buffer.from(ttf);
const n = buf.readUInt16BE(4);
const tables = [];
for (let i = 0; i < n; i++) {
  const o = 12 + i * 16, tag = buf.toString('latin1', o, o + 4);
  if (KEEP.includes(tag)) tables.push({ tag, off: buf.readUInt32BE(o + 8), len: buf.readUInt32BE(o + 12) });
}
tables.sort((a, b) => (a.tag < b.tag ? -1 : 1));
const pad4 = (x) => (x + 3) & ~3;
let total = 12 + tables.length * 16;
tables.forEach((t) => { t.newOff = total; total += pad4(t.len); });
const out = Buffer.alloc(total);
out.writeUInt32BE(0x00010000, 0); out.writeUInt16BE(tables.length, 4);
const sr = 2 ** Math.floor(Math.log2(tables.length));
out.writeUInt16BE(sr * 16, 6); out.writeUInt16BE(Math.log2(sr), 8); out.writeUInt16BE(tables.length * 16 - sr * 16, 10);
const sum32 = (b) => { let s = 0; for (let i = 0; i < b.length; i += 4) s = (s + b.readUInt32BE(i)) >>> 0; return s; };
tables.forEach((t, i) => {
  buf.copy(out, t.newOff, t.off, t.off + t.len);
  const o = 12 + i * 16;
  out.write(t.tag, o, 'latin1');
  out.writeUInt32BE(sum32(out.subarray(t.newOff, t.newOff + pad4(t.len))), o + 4);
  out.writeUInt32BE(t.newOff, o + 8); out.writeUInt32BE(t.len, o + 12);
});
const head = tables.find((t) => t.tag === 'head');
out.writeUInt32BE(0, head.newOff + 8);
out.writeUInt32BE((0xb1b0afba - sum32(out)) >>> 0, head.newOff + 8); // checksumAdjustment

const outDir = process.env.FONT_OUT || path.join(here, '..', 'fonts');
fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, 'NotoSansSC-subset.ttf'), out);
fs.writeFileSync(path.join(outDir, 'NotoSansSC-subset.txt'), chars);
console.log('chars', [...chars].length, 'ttf bytes', out.length, 'tables', tables.map((t) => t.tag + ':' + t.len).join(' '));
