/// 汇入装箱单: 从 Excel 复制贴上, 或选 CSV 档案
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/import_list.dart';
import '../core/xlsx_reader.dart';
import '../render/notes.dart' show fmt;
import '../services/download.dart';
import '../state/app_state.dart';
import 'theme.dart';

Future<void> showImportDialog(BuildContext context, AppState state) => showDialog<void>(context: context, builder: (_) => _ImportDialog(state: state));

class _ImportDialog extends StatefulWidget {
  const _ImportDialog({required this.state});
  final AppState state;

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final text = TextEditingController();
  bool? mm; // null = 依表头自动判断
  bool replace = true;
  ImportResult? result;

  void _parse() => setState(() => result = text.text.trim().isEmpty ? null : parseImport(text.text, millimetres: mm, colors: colorPalette));

  Future<void> _pickFile() async {
    final bytes = await pickTextFile();
    if (bytes == null) return;
    String s;
    if (looksLikeXlsx(bytes)) {
      try {
        s = xlsxToTsv(bytes);
      } on FormatException catch (e) {
        widget.state.toast(e.message, error: true);
        return;
      }
    } else if (bytes.length > 8 && bytes[0] == 0xD0 && bytes[1] == 0xCF) {
      widget.state.toast('这是旧版 .xls 档案，请在 Excel 另存为 .xlsx 或 CSV 再选 Old .xls format, please save as .xlsx or CSV', error: true);
      return;
    } else {
      s = utf8.decode(bytes, allowMalformed: true);
      if (s.startsWith('﻿')) s = s.substring(1); // Excel 存的 CSV 常带 BOM
    }
    text.text = s;
    _parse();
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = result;
    final suspectMm = r != null && !r.millimetres && looksLikeMillimetres(r);
    return AlertDialog(
      title: const Text('汇入装箱单 Import Packing List', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            const Text('在 Excel 里选好表格 (可以连表头一起) 复制，贴到下面。栏位顺序随意，有表头会自动认；没有表头就按：名称、总数量、每箱数量、长、宽、高、每箱重量。\n'
                'Copy rows from Excel (headers optional) and paste below. Without headers the order is: name, total PCS, PCS/box, L, W, H, weight/box.',
                style: TextStyle(fontSize: 12, color: textSecondary, height: 1.5)),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('importText'),
              controller: text,
              minLines: 5,
              maxLines: 10,
              style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
              decoration: const InputDecoration(hintText: '钢管 Steel Pipe\t3600\t12\t60\t40\t40\t18'),
              onChanged: (_) => _parse(),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              OutlinedButton.icon(onPressed: _pickFile, icon: const Icon(Icons.upload_file, size: 16), label: const Text('选 Excel / CSV 档案 Choose File')),
              const Text('尺寸单位 Unit:', style: TextStyle(fontSize: 12.5)),
              SegmentedButton<bool>(
                key: const ValueKey('importUnit'),
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [ButtonSegment(value: false, label: Text('cm')), ButtonSegment(value: true, label: Text('mm'))],
                selected: {r?.millimetres ?? (mm ?? false)},
                onSelectionChanged: (v) {
                  mm = v.first;
                  _parse();
                },
              ),
            ]),
            if (r != null && r.unitFromHeader) ...[
              const SizedBox(height: 8),
              const Text('表头写的是毫米，已自动换算成厘米 Header says mm, converted to cm automatically', style: TextStyle(fontSize: 12.5, color: greenOk, fontWeight: FontWeight.w600)),
            ],
            if (suspectMm) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFFFF3E0), borderRadius: BorderRadius.circular(8)),
                child: const Text('尺寸看起来是毫米 (mm)，要不要把单位切成 mm？ Dimensions look like millimetres — switch the unit to mm?', style: TextStyle(fontSize: 12.5, color: Color(0xFF9A4A00))),
              ),
            ],
            if (r != null) ...[
              const SizedBox(height: 12),
              Text('认出 ${r.rows.length} 行，可汇入 ${r.goodItems.length} 行${r.badCount > 0 ? '，${r.badCount} 行有问题会略过' : ''}  '
                  '${r.goodItems.length} ready${r.badCount > 0 ? ', ${r.badCount} skipped' : ''}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: navy)),
              const SizedBox(height: 6),
              _preview(r),
            ],
          ]),
        ),
      ),
      actions: [
        if (widget.state.items.any((i) => i.name.isNotEmpty))
          Row(mainAxisSize: MainAxisSize.min, children: [
            Checkbox(value: replace, onChanged: (v) => setState(() => replace = v ?? true)),
            const Text('取代现有物品 Replace current items', style: TextStyle(fontSize: 12.5)),
          ]),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消 Cancel')),
        FilledButton(
          key: const ValueKey('importConfirm'),
          onPressed: (r == null || r.goodItems.isEmpty)
              ? null
              : () {
                  final n = widget.state.importItems(r.goodItems, replace: replace || !widget.state.items.any((i) => i.name.isNotEmpty));
                  widget.state.toast('已汇入 $n 样物品 Imported $n items ✓');
                  Navigator.pop(context);
                },
          child: Text(r == null ? '汇入 Import' : '汇入 ${r.goodItems.length} 样 Import'),
        ),
      ],
    );
  }

  Widget _preview(ImportResult r) => Container(
        constraints: const BoxConstraints(maxHeight: 240),
        decoration: BoxDecoration(border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(8)),
        child: SingleChildScrollView(
          child: Column(children: [
            for (final row in r.rows.take(100))
              Container(
                color: row.ok ? null : const Color(0xFFFBEAE8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 34, child: Text('${row.lineNo}', style: const TextStyle(fontSize: 11.5, color: textSecondary))),
                  Container(width: 10, height: 10, margin: const EdgeInsets.only(top: 3, right: 8), decoration: BoxDecoration(color: Color(row.item.color), borderRadius: BorderRadius.circular(3))),
                  Expanded(
                    child: Text(
                      row.ok
                          ? '${row.item.name}   ${fmt(row.item.totalPcs)} PCS · ${fmt(row.item.pcsPerBox)}/箱 · ${fmt(row.item.boxL)}×${fmt(row.item.boxW)}×${fmt(row.item.boxH)} cm${row.item.boxWeight > 0 ? ' · ${fmt(row.item.boxWeight)} kg' : ''} → ${row.item.boxesNeeded} 箱'
                          : '${row.item.name.isEmpty ? '(无名称)' : row.item.name}: ${row.errors.join('；')}',
                      style: TextStyle(fontSize: 12, color: row.ok ? navy : redErr),
                    ),
                  ),
                ]),
              ),
          ]),
        ),
      );
}
