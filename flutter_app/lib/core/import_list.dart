/// 从 Excel 复制贴上 / CSV 档案汇入装箱单
///
/// 支援 Tab (从 Excel/Google Sheets 复制) 或逗号分隔。有表头时依表头文字认栏位 (中英文都行, 顺序随意),
/// 没有表头就依预设顺序: 名称, 总数量, 每箱数量, 长, 宽, 高, 每箱重量(可省略)。
/// 尺寸可以是 cm 或 mm (mm 会自动换算)。
library;

import 'models.dart';

enum ImportField { name, totalPcs, pcsPerBox, length, width, height, weight }

const _defaultOrder = [ImportField.name, ImportField.totalPcs, ImportField.pcsPerBox, ImportField.length, ImportField.width, ImportField.height, ImportField.weight];

/// 表头关键字 (小写比对, 包含即可)。顺序重要: 先比对较长、较特定的词
const _keywords = <ImportField, List<String>>{
  ImportField.pcsPerBox: ['每箱数', '每箱pcs', '每箱个数', '入数', '装箱数', 'pcs/box', 'pcs/ctn', 'per box', 'per carton', 'qty/ctn', 'qty/box', 'pcs per'],
  ImportField.weight: ['每箱重', '重量', '毛重', 'weight', 'kg', 'g.w', 'gw'],
  ImportField.totalPcs: ['总数', '数量', '总pcs', 'total', 'qty', 'quantity', 'pcs'],
  ImportField.length: ['长', 'length', 'l(', 'l '],
  ImportField.width: ['宽', 'width', 'w(', 'w '],
  ImportField.height: ['高', 'height', 'h(', 'h '],
  ImportField.name: ['名称', '品名', '物品', '产品', '货名', '型号', 'name', 'item', 'description', 'part', 'model'],
};

class ImportRow {
  ImportRow(this.lineNo, this.item, this.errors);
  final int lineNo; // 原始资料的第几行 (1 起)
  final Item item;
  final List<String> errors;
  bool get ok => errors.isEmpty;
}

class ImportResult {
  ImportResult(this.rows, this.headerFound, this.columns, {this.millimetres = false, this.unitFromHeader = false});
  final bool millimetres; // 实际采用的单位
  final bool unitFromHeader; // 单位是从表头 (如「长(mm)」) 认出来的
  final List<ImportRow> rows;
  final bool headerFound;
  final List<ImportField?> columns; // 每一栏被认成什么
  List<Item> get goodItems => [for (final r in rows) if (r.ok) r.item];
  int get badCount => rows.where((r) => !r.ok).length;
}

List<String> _splitLine(String line, String sep) {
  if (sep == '\t') return line.split('\t').map((s) => s.trim()).toList();
  // 逗号分隔: 支援用双引号包住含逗号的栏位
  final out = <String>[];
  final buf = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      if (quoted && i + 1 < line.length && line[i + 1] == '"') {
        buf.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (ch == sep && !quoted) {
      out.add(buf.toString().trim());
      buf.clear();
    } else {
      buf.write(ch);
    }
  }
  out.add(buf.toString().trim());
  return out;
}

double? _number(String s) {
  final t = s.replaceAll(',', '').replaceAll(RegExp(r'[^0-9.\-]'), '');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

ImportField? _fieldOf(String header) {
  final h = header.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  if (h.isEmpty) return null;
  for (final e in _keywords.entries) {
    for (final k in e.value) {
      if (h == k.trim() || h.contains(k)) return e.key;
    }
  }
  return null;
}

/// millimetres: true/false = 使用者指定; null = 自动 (表头写了 mm 就用 mm, 否则 cm)
/// colors: 依序给新物品配色; startId: 新物品的起始 id
ImportResult parseImport(String text, {bool? millimetres, required List<int> colors, int startId = 1}) {
  final lines = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n').where((l) => l.trim().isNotEmpty).toList();
  if (lines.isEmpty) return ImportResult(const [], false, const [], millimetres: millimetres ?? false);
  final sep = lines.first.contains('\t') ? '\t' : (lines.first.contains(',') ? ',' : (lines.first.contains(';') ? ';' : '\t'));
  final table = [for (final l in lines) _splitLine(l, sep)];

  // 第一行里, 本该是数字的栏位都不是数字 → 视为表头
  final first = table.first;
  final headerCandidates = [for (final c in first) _fieldOf(c)];
  final numericCount = first.skip(1).where((c) => _number(c) != null).length;
  final headerFound = headerCandidates.whereType<ImportField>().length >= 2 || (numericCount == 0 && first.length > 1);

  List<ImportField?> columns;
  if (headerFound && headerCandidates.whereType<ImportField>().length >= 2) {
    // 同一个栏位类型只认第一次出现
    final seen = <ImportField>{};
    columns = [for (final f in headerCandidates) (f != null && seen.add(f)) ? f : null];
    if (!columns.contains(ImportField.name)) {
      final idx = columns.indexOf(null);
      if (idx >= 0) columns[idx] = ImportField.name;
    }
  } else {
    // 没有表头: 依预设顺序; 栏数以最长的一行为准 (第一行可能省略了最后的重量)
    final width = table.fold<int>(0, (m, r) => r.length > m ? r.length : m);
    columns = [for (var i = 0; i < width; i++) i < _defaultOrder.length ? _defaultOrder[i] : null];
  }

  // 表头的长宽高栏写了 mm (例如「长(mm)」「Length (mm)」) → 自动用毫米
  var unitFromHeader = false;
  if (headerFound) {
    for (var i = 0; i < first.length && i < columns.length; i++) {
      final f = columns[i];
      if ((f == ImportField.length || f == ImportField.width || f == ImportField.height) && RegExp(r'mm|毫米', caseSensitive: false).hasMatch(first[i])) unitFromHeader = true;
    }
  }
  final useMm = millimetres ?? unitFromHeader;
  final factor = useMm ? 0.1 : 1.0;
  final rows = <ImportRow>[];
  for (var r = headerFound ? 1 : 0; r < table.length && rows.length < 500; r++) {
    final cells = table[r];
    String cell(ImportField f) {
      final i = columns.indexOf(f);
      return (i >= 0 && i < cells.length) ? cells[i] : '';
    }

    final errors = <String>[];
    double need(ImportField f, String label) {
      final v = _number(cell(f));
      if (v == null || v <= 0) errors.add('$label 不是大于 0 的数字 $label must be a number > 0');
      return v ?? 0;
    }

    final name = cell(ImportField.name);
    if (name.isEmpty) errors.add('缺少名称 missing name');
    final total = need(ImportField.totalPcs, '总数量 PCS');
    final perBox = need(ImportField.pcsPerBox, '每箱数量 PCS/box');
    final l = need(ImportField.length, '长 L'), w = need(ImportField.width, '宽 W'), h = need(ImportField.height, '高 H');
    final weight = _number(cell(ImportField.weight)) ?? 0;
    rows.add(ImportRow(
      r + 1,
      Item(
        id: startId + rows.length,
        name: name.length > 200 ? name.substring(0, 200) : name,
        totalPcs: total,
        pcsPerBox: perBox,
        boxL: round2(l * factor),
        boxW: round2(w * factor),
        boxH: round2(h * factor),
        boxWeight: weight < 0 ? 0 : weight,
        color: colors[rows.length % colors.length],
      ),
      errors,
    ));
  }
  return ImportResult(rows, headerFound, columns, millimetres: useMm, unitFromHeader: unitFromHeader && millimetres == null);
}

/// 尺寸看起来像 mm (常见纸箱边长不会超过 200 cm): 用来提醒使用者切换单位
bool looksLikeMillimetres(ImportResult r) {
  final dims = [for (final row in r.rows) ...[row.item.boxL, row.item.boxW, row.item.boxH]].where((v) => v > 0).toList();
  if (dims.isEmpty) return false;
  return dims.where((v) => v > 200).length >= (dims.length / 2);
}
