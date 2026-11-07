import 'package:container_calc/core/import_list.dart';
import 'package:container_calc/services/memory_backend.dart';
import 'package:container_calc/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const colors = [0xFFE74C3C, 0xFF3498DB, 0xFF2ECC71];

void main() {
  group('parseImport', () {
    test('Excel copy with Chinese headers in any order', () {
      const text = '高(cm)\t品名\t总数量\t长(cm)\t宽(cm)\t每箱数量\t毛重(kg)\n'
          '40\t钢管 Steel Pipe\t3,600\t60\t40\t12\t18.5\n'
          '25\t配件盒 Parts\t8400\t30\t30\t20\t\n';
      final r = parseImport(text, colors: colors);
      expect(r.headerFound, isTrue);
      expect(r.goodItems.length, 2);
      final a = r.goodItems.first;
      expect([a.name, a.totalPcs, a.pcsPerBox, a.boxL, a.boxW, a.boxH, a.boxWeight], ['钢管 Steel Pipe', 3600, 12, 60, 40, 40, 18.5]);
      expect(r.goodItems[1].boxWeight, 0);
      expect(a.boxesNeeded, 300);
    });

    test('English headers, CSV with quoted commas', () {
      const text = 'Item,Qty,PCS/CTN,Length,Width,Height,Weight\n"Cable, black",1000,50,40,30,20,8\n';
      final r = parseImport(text, colors: colors);
      expect(r.goodItems.single.name, 'Cable, black');
      expect(r.goodItems.single.pcsPerBox, 50);
      expect(r.goodItems.single.boxL, 40);
    });

    test('no header: default column order', () {
      final r = parseImport('A\t100\t10\t50\t40\t30\nB\t20\t1\t100\t50\t50\t35', colors: colors);
      expect(r.headerFound, isFalse);
      expect(r.goodItems.length, 2);
      expect(r.goodItems[1].boxWeight, 35);
      expect(r.goodItems[1].color, colors[1]);
    });

    test('millimetres are converted, and are detected when the unit is wrong', () {
      const text = 'A\t100\t10\t600\t400\t400';
      final cm = parseImport(text, colors: colors);
      expect(looksLikeMillimetres(cm), isTrue);
      final mm = parseImport(text, millimetres: true, colors: colors);
      expect(mm.goodItems.single.boxL, 60);
      expect(looksLikeMillimetres(mm), isFalse);
    });

    test('unit is taken from the header automatically, but the user can override it', () {
      const text = '品名\t数量\t入数\t长(mm)\t宽(mm)\t高(mm)\n钢管\t100\t10\t600\t400\t400';
      final auto = parseImport(text, colors: colors);
      expect(auto.millimetres, isTrue);
      expect(auto.unitFromHeader, isTrue);
      expect(auto.goodItems.single.boxL, 60);
      final forcedCm = parseImport(text, millimetres: false, colors: colors);
      expect(forcedCm.goodItems.single.boxL, 600);
      expect(parseImport('A\t100\t10\t60\t40\t40', colors: colors).millimetres, isFalse);
    });

    test('bad rows are reported with their line number and skipped', () {
      final r = parseImport('名称\t总数量\t每箱数量\t长\t宽\t高\nOK\t10\t1\t10\t10\t10\n\t10\t1\t10\t10\t10\nBad\tabc\t1\t10\t10\t10', colors: colors);
      expect(r.goodItems.length, 1);
      expect(r.badCount, 2);
      expect(r.rows[1].lineNo, 3);
      expect(r.rows[1].errors.join(), contains('名称'));
      expect(r.rows[2].errors.join(), contains('总数量'));
    });

    test('empty input', () => expect(parseImport('  \n ', colors: colors).rows, isEmpty));
  });

  group('draft autosave', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<AppState> loggedIn(MemoryBackend b) async {
      final s = AppState(b);
      await s.login('a@x.com', 'secret1');
      return s;
    }

    test('unfinished list survives a refresh; explicit logout clears it', () async {
      final b = MemoryBackend();
      await b.register('a@x.com', 'secret1', '', '');
      var s = await loggedIn(b);
      s.importItems(parseImport('钢管\t100\t10\t50\t40\t30', colors: colors).goodItems, replace: true);
      s.shipment.customer = '客户A';
      await s.saveDraftNow();

      // 重新整理 = 新的 AppState (内存清空), 同一个帐号再登入
      s = await loggedIn(b);
      expect(s.items.single.name, '钢管');
      expect(s.shipment.customer, '客户A');

      await s.logout(clearDraft: true);
      s = await loggedIn(b);
      expect(s.items.where((i) => i.name.isNotEmpty), isEmpty);
    });

    test('drafts are per account', () async {
      final b = MemoryBackend();
      await b.register('a@x.com', 'secret1', '', '');
      await b.register('b@x.com', 'secret1', '', '');
      await b.login('a@x.com', 'secret1');
      await b.adminUpdateUser('b@x.com', status: 'active');
      await b.logout();
      final s = await loggedIn(b);
      s.importItems(parseImport('只属于A\t100\t10\t50\t40\t30', colors: colors).goodItems, replace: true);
      await s.logout(); // 没有清除草稿
      final other = AppState(b);
      await other.login('b@x.com', 'secret1');
      expect(other.items.any((i) => i.name == '只属于A'), isFalse);
    });

    test('import appends or replaces', () async {
      final b = MemoryBackend();
      await b.register('a@x.com', 'secret1', '', '');
      final s = await loggedIn(b);
      final two = parseImport('A\t1\t1\t1\t1\t1\nB\t1\t1\t1\t1\t1', colors: colors).goodItems;
      s.importItems(two, replace: true);
      expect(s.items.map((i) => i.name), ['A', 'B']);
      s.importItems(two, replace: false);
      expect(s.items.length, 4);
      expect(s.items.map((i) => i.id).toSet().length, 4, reason: 'ids stay unique');
    });
  });
}
