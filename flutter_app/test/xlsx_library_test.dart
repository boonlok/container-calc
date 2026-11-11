import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:container_calc/core/import_list.dart';
import 'package:container_calc/core/models.dart';
import 'package:container_calc/core/xlsx_reader.dart';
import 'package:container_calc/services/library_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const colors = [0xFFE74C3C, 0xFF3498DB, 0xFF2ECC71];

Uint8List _zip(Map<String, String> files) {
  final a = Archive();
  files.forEach((name, body) {
    final b = utf8.encode(body);
    a.addFile(ArchiveFile(name, b.length, b));
  });
  return Uint8List.fromList(ZipEncoder().encode(a));
}

void main() {
  group('xlsx', () {
    test('real workbook (written by ExcelJS): first sheet, shared strings, formulas, mm header', () {
      final bytes = File('test/fixtures/packing_list.xlsx').readAsBytesSync();
      expect(looksLikeXlsx(bytes), isTrue);
      final tsv = xlsxToTsv(bytes);
      expect(tsv.split('\n').first, startsWith('品名\t数量\t入数\t长(mm)'));
      expect(tsv, isNot(contains('ignore me')), reason: 'only the first sheet');
      final r = parseImport(tsv, colors: colors);
      expect(r.millimetres, isTrue);
      expect(r.goodItems.length, 3, reason: 'the 合计 row has no dimensions and is skipped');
      final a = r.goodItems.first;
      expect([a.name, a.totalPcs, a.pcsPerBox, a.boxL, a.boxW, a.boxH, a.boxWeight], ['钢管 Steel Pipe', 3600, 12, 60, 40, 40, 18.5]);
      expect(r.goodItems[1].boxWeight, 0);
      expect(r.goodItems[2].boxWeight, 35, reason: 'formula cells use their cached value');
      expect(r.badCount, 1);
    });

    test('inline strings and sparse cells (gaps keep their column)', () {
      final bytes = _zip({
        'xl/worksheets/sheet1.xml': '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>'
            '<row r="1"><c r="A1" t="inlineStr"><is><t>Item</t></is></c><c r="B1" t="inlineStr"><is><t>Qty</t></is></c><c r="C1" t="inlineStr"><is><t>PCS/CTN</t></is></c>'
            '<c r="D1" t="inlineStr"><is><t>L</t></is></c><c r="E1" t="inlineStr"><is><t>W</t></is></c><c r="F1" t="inlineStr"><is><t>H</t></is></c></row>'
            '<row r="2"><c r="A2" t="inlineStr"><is><t>Box</t></is></c><c r="B2"><v>100</v></c><c r="C2"><v>10</v></c><c r="D2"><v>50</v></c><c r="F2"><v>30</v></c></row>'
            '</sheetData></worksheet>',
      });
      final rows = xlsxToTsv(bytes).split('\n');
      expect(rows[1].split('\t'), ['Box', '100', '10', '50', '', '30']);
    });

    test('garbage is rejected with a readable message', () {
      expect(() => xlsxToTsv(Uint8List.fromList([0x50, 0x4B, 1, 2, 3])), throwsA(isA<FormatException>()));
      expect(looksLikeXlsx(Uint8List.fromList(utf8.encode('a,b,c'))), isFalse);
    });
  });

  group('item library', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));
    Item it(String n, {double l = 50}) => Item(id: 9, name: n, totalPcs: 999, pcsPerBox: 10, boxL: l, boxW: 40, boxH: 30, boxWeight: 5);

    test('save, update by name, skip incomplete, quantities not stored', () async {
      var (added, updated) = await addToLibrary('a@x.com', [it('钢管'), it('配件'), Item(id: 3, name: '未完成')]);
      expect((added, updated), (2, 0));
      (added, updated) = await addToLibrary('a@x.com', [it('钢管', l: 60)]);
      expect((added, updated), (0, 1));
      final lib = await loadLibrary('a@x.com');
      expect(lib.map((e) => e.name), ['配件', '钢管']);
      expect(lib.firstWhere((e) => e.name == '钢管').boxL, 60);
      expect(lib.every((e) => e.totalPcs == 0), isTrue);
      expect(lib.map((e) => e.id).toSet().length, 2);
    });

    test('per account, and removable', () async {
      await addToLibrary('a@x.com', [it('A')]);
      expect(await loadLibrary('b@x.com'), isEmpty);
      final id = (await loadLibrary('a@x.com')).single.id;
      expect(await removeFromLibrary('a@x.com', id), isEmpty);
    });
  });
}
