/// 读取 Excel .xlsx 的第一个工作表, 转成 Tab 分隔文字 (再交给 parseImport)
///
/// .xlsx 其实是一个 zip, 里面是 XML: workbook.xml 列出工作表, sheetN.xml 存储存格,
/// 文字放在 sharedStrings.xml。这里只读取「值」, 不处理公式计算、合并储存格与格式。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

bool looksLikeXlsx(Uint8List bytes) => bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B; // "PK" = zip

String? _read(Archive a, String name) {
  final f = a.findFile(name);
  return f == null ? null : utf8.decode(f.content, allowMalformed: true);
}

/// "AB12" → 27 (A=0)
int _colIndex(String ref) {
  var n = 0;
  for (final ch in ref.codeUnits) {
    if (ch < 65 || ch > 90) break;
    n = n * 26 + (ch - 64);
  }
  return n - 1;
}

String _cellText(XmlElement e) => e.findAllElements('t').map((t) => t.innerText).join();

/// 回传第一个工作表的 Tab 分隔文字; 不是有效的 xlsx 时丢出 FormatException
String xlsxToTsv(Uint8List bytes, {int maxRows = 1000}) {
  final Archive a;
  try {
    a = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const FormatException('不是有效的 Excel 档案 Not a valid .xlsx file');
  }

  // 找第一个工作表的路径
  var sheetPath = 'xl/worksheets/sheet1.xml';
  final wb = _read(a, 'xl/workbook.xml'), rels = _read(a, 'xl/_rels/workbook.xml.rels');
  if (wb != null && rels != null) {
    final first = XmlDocument.parse(wb).findAllElements('sheet').firstOrNull;
    final rid = first?.getAttribute('r:id') ?? first?.attributes.where((x) => x.name.local == 'id').firstOrNull?.value;
    if (rid != null) {
      final rel = XmlDocument.parse(rels).findAllElements('Relationship').where((r) => r.getAttribute('Id') == rid).firstOrNull;
      final target = rel?.getAttribute('Target');
      if (target != null) sheetPath = target.startsWith('/') ? target.substring(1) : 'xl/$target';
    }
  }
  final sheet = _read(a, sheetPath);
  if (sheet == null) throw const FormatException('Excel 档案里找不到工作表 No worksheet found');

  final shared = <String>[];
  final ss = _read(a, 'xl/sharedStrings.xml');
  if (ss != null) {
    for (final si in XmlDocument.parse(ss).findAllElements('si')) {
      shared.add(_cellText(si));
    }
  }

  final lines = <String>[];
  for (final row in XmlDocument.parse(sheet).findAllElements('row')) {
    if (lines.length >= maxRows) break;
    final cells = <int, String>{};
    var next = 0;
    for (final c in row.findElements('c')) {
      final ref = c.getAttribute('r');
      final idx = ref != null ? _colIndex(ref) : next;
      next = idx + 1;
      final type = c.getAttribute('t');
      final v = c.getElement('v')?.innerText ?? '';
      String text;
      switch (type) {
        case 's':
          final i = int.tryParse(v);
          text = (i != null && i >= 0 && i < shared.length) ? shared[i] : '';
        case 'inlineStr':
          text = _cellText(c);
        case 'b':
          text = v == '1' ? 'TRUE' : 'FALSE';
        default:
          text = v;
      }
      if (idx >= 0 && idx < 200) cells[idx] = text.replaceAll('\t', ' ').replaceAll('\n', ' ').trim();
    }
    if (cells.values.every((t) => t.isEmpty)) continue;
    final width = cells.keys.reduce((m, k) => k > m ? k : m) + 1;
    lines.add([for (var i = 0; i < width; i++) cells[i] ?? ''].join('\t'));
  }
  return lines.join('\n');
}
