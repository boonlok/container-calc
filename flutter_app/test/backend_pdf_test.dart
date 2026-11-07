import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:container_calc/core/algorithm.dart';
import 'package:container_calc/core/models.dart';
import 'package:container_calc/services/backend.dart';
import 'package:container_calc/services/history_codec.dart';
import 'package:container_calc/services/memory_backend.dart';
import 'package:container_calc/services/pdf_export.dart';
import 'package:flutter_test/flutter_test.dart';

Item item(int id, String n, double pcs, double l, double w, double h, {int color = 0xFFE74C3C}) =>
    Item(id: id, name: n, totalPcs: pcs, pcsPerBox: 1, boxL: l, boxW: w, boxH: h, color: color);

final presets = [
  Preset(id: 1, name: '20GP (20呎标准柜)', length: 589, width: 235, height: 239, maxPayload: 28180),
  Preset(id: 2, name: '45HC (45呎高柜)', length: 1355, width: 235, height: 269, maxPayload: 27600),
];

Future<String?> thr(Future<Object?> Function() f) async {
  try {
    await f();
    return null;
  } on AppError catch (e) {
    return e.message;
  }
}

void main() {
  group('MemoryBackend (same rules as schema.sql)', () {
    test('first signup is active admin, later ones wait for approval; isolation holds', () async {
      final b = MemoryBackend();
      expect((await b.register('Admin@X.com', 'secret1', 'A', '')).isFirstUser, isTrue);
      expect((await b.register('u1@x.com', 'secret1', 'B', '')).isFirstUser, isFalse);
      expect(await thr(() => b.register('u1@x.com', 'secret1', '', '')), contains('已被注册'));
      expect((await b.login('u1@x.com', 'secret1')).message, contains('尚未启用'));
      expect((await b.login('u1@x.com', 'wrong')).message, contains('邮箱或密码错误'));

      final la = await b.login('admin@x.com', 'secret1');
      expect(la.user!.isAdmin, isTrue);
      await b.adminUpdateUser('u1@x.com', status: 'active');
      expect(await thr(() => b.adminUpdateUser('admin@x.com', role: 'user')), contains('不能修改自己'));
      expect(await thr(() => b.adminUpdateUser('u1@x.com', role: '<img>')), contains('角色值不正确'));
      // admin 原样送回自己的 role/status + 改公司名: 不应该被挡或被登出
      await b.adminUpdateUser('admin@x.com', role: 'admin', status: 'active', companyName: 'New');
      expect((await b.restoreSession())!.companyName, 'New');

      await b.saveHistory('adminCalc', {'totalItems': 1, 'totalContainers': 1, 'summaryText': 'x'}, {'items': []});
      await b.logout();
      await b.login('u1@x.com', 'secret1');
      expect(await b.listHistory(), isEmpty, reason: 'user must not see admin history');
      expect(await thr(() => b.listUsers()), contains('管理员权限'));
      expect(await thr(() => b.savePreset(Preset(id: 1, name: 'x', length: 1, width: 1, height: 1, maxPayload: 1))), contains('没有权限'));
      final mine = await b.savePreset(Preset(name: 'Mine', length: 500, width: 200, height: 200, maxPayload: 1000));
      expect(mine.length, 5);
      expect(mine.last.owner, 'u1@x.com');
      await b.logout();
      expect(() => b.listPresets(), throwsA(isA<SessionExpired>()));
    });

    test('forgot password flow', () async {
      final b = MemoryBackend();
      await b.register('a@x.com', 'secret1', '', '');
      final m1 = await b.requestPasswordReset('a@x.com'), m2 = await b.requestPasswordReset('nobody@x.com');
      expect(m1, m2, reason: 'must not reveal which emails exist');
      expect(await thr(() => b.resetPasswordWithCode('a@x.com', '000000', 'newpass1')), contains('验证码'));
      await b.resetPasswordWithCode('a@x.com', b.lastResetCodeFor('a@x.com')!, 'newpass1');
      expect((await b.login('a@x.com', 'newpass1')).success, isTrue);
      expect((await b.login('a@x.com', 'secret1')).success, isFalse);
    });
  });

  group('history codec', () {
    final items = [item(1, '钢管 Steel', 300, 60, 40, 40)];
    final result = packContainers(items, presets);
    final ship = ShipmentInfo(customer: '客户', etd: '2026-11-07', accessories: [Accessory(name: 'Screw', qty: '5')]);

    test('round trip', () {
      final u = unpackHistory(jsonDecode(jsonEncode(packHistory(items, result, ship))) as Map<String, Object?>);
      expect(u.items.first.name, '钢管 Steel');
      expect(u.result!.containers.length, result.containers.length);
      expect(u.shipment!.customer, '客户');
      expect(u.shipment!.accessories.first.qty, '5');
    });

    test('reads the web version gzip format {v:2, z}', () {
      final json = jsonEncode({'items': items.map((i) => i.toJson()).toList(), 'result': result.toJson()});
      final z = base64Encode(GZipEncoder().encode(utf8.encode(json)));
      final u = unpackHistory({'v': 2, 'z': z});
      expect(u.items.length, 1);
      expect(u.result, isNotNull);
    });

    test('malicious record is neutralised; broken result triggers recalculation', () {
      final u = unpackHistory({
        'items': [{'id': '"><x>', 'name': 'n', 'color': '"><img>', 'boxL': '"><b>', 'totalPcs': 5}],
        'result': {'containers': [{'containerType': '<img>', 'L': 1, 'W': 1, 'H': 1, 'allocations': [{'horizontal': 0}]}]},
        'shipment': {'etd': 'not-a-date', 'customer': 'c'},
      });
      expect(u.items.first.color, 0xFF888888);
      expect(u.items.first.boxL, 0);
      expect(u.result, isNull);
      expect(u.shipment!.etd, '');
    });
  });

  group('PDF', () {
    final font = File('assets/fonts/NotoSansSC-subset.ttf').readAsBytesSync();
    final user = UserProfile(email: 't@x.com', role: 'admin', status: 'active', companyName: '测试公司 Test Co', companyAddress: '上海市浦东新区 Addr 1');
    final ship = ShipmentInfo(customer: '客户 ABC 株式会社', etd: '2026-11-07', remark: '备注：易碎品，请轻放；禁止倒置，需要在装柜前确认所有货物的包装完整并拍照留底 This side up',
        drawn: '张三', checked: '李四', accessories: [Accessory(name: 'Cable Clip', qty: '10'), Accessory(name: 'Screw')]);
    const cols = [0xFFE74C3C, 0xFF3498DB, 0xFF2ECC71, 0xFFF39C12, 0xFF9B59B6, 0xFF1ABC9C, 0xFFE67E22, 0xFF34495E, 0xFFF1C40F, 0xFFE84393, 0xFF00B894];

    int pageCount(Uint8List b) => RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(b)).length;

    test('mixed container: summary + 4 page kinds per unit, A3 landscape, font subset is small', () async {
      final items = List.generate(11, (i) => item(i + 1, '物品${i + 1} Item ${i + 1}${i % 3 == 0 ? ' 长名称测试用的物品名称' : ''}', 200.0 + i * 40, 20.0 + i * 4, 18.0 + (i % 4) * 5, 15.0 + (i % 5) * 6, color: cols[i]));
      final r = packContainers(items, presets).pushedToFarWall();
      expect(r.containers.length, greaterThan(1));
      final bytes = await buildPdf(result: r, shipment: ship, user: user, fontBytes: font, now: DateTime(2026, 11, 7, 9, 30));
      File('build/test_mixed.pdf')..createSync(recursive: true)..writeAsBytesSync(bytes);
      expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
      final text = latin1.decode(bytes);
      // A3 横向 = 1190.55 x 841.89 pt
      expect(RegExp(r'/MediaBox\s*\[\s*0\s+0\s+1190\.\d+\s+841\.\d+').hasMatch(text), isTrue, reason: 'A3 landscape');
      expect(pageCount(bytes), greaterThanOrEqualTo(1 + 4 * r.containers.where((c) => c.allocations.length > 1).length));
      expect(bytes.length, lessThan(font.length + 3000000), reason: 'size ${bytes.length}');
      // ignore: avoid_print
      print('mixed PDF: ${(bytes.length / 1024).round()} KB, ${pageCount(bytes)} pages');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('single-item container has no close-up page', () async {
      final r = packContainers([item(1, '单品 Single', 100, 50, 40, 30)], presets);
      final bytes = await buildPdf(result: r, shipment: ship, user: user, fontBytes: font);
      File('build/test_single.pdf')..createSync(recursive: true)..writeAsBytesSync(bytes);
      expect(pageCount(bytes), 3 * r.containers.length);
    });
  });
}
