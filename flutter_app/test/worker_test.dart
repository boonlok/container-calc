import 'dart:io';

import 'package:container_calc/core/algorithm.dart';
import 'package:container_calc/core/loading_plan.dart';
import 'package:container_calc/core/models.dart';
import 'package:container_calc/render/draw.dart';
import 'package:container_calc/render/flat_views.dart';
import 'package:container_calc/render/iso.dart';
import 'package:container_calc/services/pdf_export.dart';
import 'package:container_calc/services/progress_store.dart';
import 'package:container_calc/services/share_link.dart';
import 'package:container_calc/ui/theme.dart';
import 'package:container_calc/ui/worker_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final presets = [Preset(name: '45HC', length: 1355, width: 235, height: 269, maxPayload: 27600)];

Item item(int id, String n, double pcs, double l, double w, double h, {int color = 0xFFE74C3C}) =>
    Item(id: id, name: n, totalPcs: pcs, pcsPerBox: 1, boxL: l, boxW: w, boxH: h, color: color);

ContainerResult mixed() => packContainers([item(1, '钢管 Steel', 305, 60, 40, 40), item(2, '配件 Parts', 423, 30, 30, 25, color: 0xFF3498DB)], presets).containers.first;

void main() {
  group('LoadingPlan', () {
    final c = mixed();
    final plan = LoadingPlan(c);

    test('order is far end to door: last section first, far column first', () {
      expect(plan.steps.first.allocIndex, c.allocations.length - 1);
      expect(plan.steps.first.column, c.allocations.last.columns - 1);
      expect(plan.steps.last.allocIndex, 0);
      expect(plan.steps.last.column, 0);
      // 每一步离柜门的距离都不比下一步近
      double start(LoadStep s) => c.allocations[s.allocIndex].startLength + s.column * c.allocations[s.allocIndex].depthUnit;
      for (var i = 1; i < plan.steps.length; i++) {
        expect(start(plan.steps[i]), lessThan(start(plan.steps[i - 1])));
      }
    });

    test('every box is in exactly one step; partial column has the remainder', () {
      expect(plan.steps.fold(0, (s, x) => s + x.boxes), plan.totalBoxes);
      expect(plan.boxesDone(plan.steps.length), plan.totalBoxes);
      expect(plan.boxesDone(0), 0);
      for (var i = 0; i < c.allocations.length; i++) {
        final a = c.allocations[i];
        final inSection = plan.steps.where((s) => s.allocIndex == i).toList();
        expect(inSection.fold(0, (s, x) => s + x.boxes), a.boxesPlaced);
        // 只有柜底侧第一列可以不满
        final full = a.horizontal * a.vertical;
        for (final s in inSection.skip(1)) {
          expect(s.boxes, full);
        }
      }
    });

    test('positions are measured from the far wall', () {
      expect(plan.fromFarWall(plan.steps.first), 0);
      final last = plan.steps.last;
      final a = c.allocations[last.allocIndex];
      expect(plan.fromFarWall(last) + a.depthUnit, closeTo(plan.usedLength, 0.01));
      expect(plan.doorGap, closeTo(c.L - plan.usedLength, 0.01));
    });

    test('partial layout: bottom layers first', () {
      final a = Allocation(itemId: 1, name: 'x', color: 0, boxesPlaced: 23, pcsPlaced: 23, boxL: 1, boxW: 1, boxH: 1, horizontal: 5, vertical: 8, columns: 1, rotated: false, depthUnit: 1, boxWeight: 0, pcsPerBox: 1, lengthUsed: 1, startLength: 0);
      final l = LoadingPlan.layoutOf(a, 23);
      expect(l.fullLayers, 4);
      expect(l.topLayerBoxes, 3);
    });
  });

  group('worker link', () {
    final c = mixed();

    test('round trip keeps the plan, and is short enough for a QR code', () {
      final link = workerLink(Uri.parse('https://boonlok.github.io/container-calc/?x=1#old'), c, 2, 3);
      expect(link, startsWith('https://boonlok.github.io/container-calc/#load='));
      expect(link.length, lessThan(1100), reason: 'length ${link.length}');
      final p = decodeWorkerPayload(workerPayloadFrom(Uri.parse(link))!)!;
      expect(p.unit, 2);
      expect(p.totalUnits, 3);
      expect(p.container.L, c.L);
      expect(p.container.allocations.length, c.allocations.length);
      final a = p.container.allocations.first, b = c.allocations.first;
      expect([a.name, a.boxesPlaced, a.horizontal, a.vertical, a.columns, a.rotated, a.startLength], [b.name, b.boxesPlaced, b.horizontal, b.vertical, b.columns, b.rotated, b.startLength]);
      expect(LoadingPlan(p.container).steps.length, LoadingPlan(c).steps.length);
    });

    test('garbage or malicious payloads are rejected or neutralised', () {
      expect(decodeWorkerPayload('not-base64!!'), isNull);
      expect(decodeWorkerPayload(''), isNull);
      expect(workerPayloadFrom(Uri.parse('https://x.com/#/home')), isNull);
    });
  });

  group('render', () {
    final c = mixed();

    test('LoadView draws nothing beyond the current column', () {
      final plan = LoadingPlan(c);
      final s0 = plan.steps.first;
      final first = renderIso(c, doorCamera(c), load: LoadView(s0.allocIndex, s0.column), labels: false);
      final firstPolys = lastPolygonCount;
      final sMid = plan.steps[plan.steps.length ~/ 2];
      renderIso(c, doorCamera(c), load: LoadView(sMid.allocIndex, sMid.column), labels: false);
      expect(lastPolygonCount, greaterThan(firstPolys));
      expect(first.cmds.whereType<Poly>(), isNotEmpty);
    });

    test('column face shows filled and empty slots for a partial column', () {
      final a = c.allocations.last;
      final partial = drawColumnFace(c, a, 3);
      final full = drawColumnFace(c, a, a.horizontal * a.vertical);
      int filled(DrawList d) => d.cmds.whereType<Poly>().where((p) => p.fill == a.color).length;
      expect(filled(partial), 3);
      expect(filled(full), a.horizontal * a.vertical);
    });
  });

  testWidgets('worker flow: step through, undo, resume, seal checklist', (tester) async {
    final bytes = File('assets/fonts/NotoSansSC-subset.ttf').readAsBytesSync();
    await (FontLoader('NotoSansSC')..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844); // 手机
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final c = packContainers([item(1, '钢管 Steel', 45, 60, 40, 40), item(2, '配件 Parts', 30, 100, 50, 50, color: 0xFF3498DB)], presets).containers.first;
    final plan = LoadingPlan(c);
    Widget app() => MaterialApp(theme: buildTheme(), home: WorkerScreen(container: c, unit: 1, totalUnits: 1));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'no overflow on a phone');

    final first = plan.steps.first;
    expect(find.text(c.allocations[first.allocIndex].name), findsOneWidget);
    expect(find.text('第 1 列'), findsOneWidget);
    expect(find.textContaining('已装 Loaded  0 / ${plan.totalBoxes}'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('stepDone')));
    await tester.pumpAndSettle();
    expect(find.textContaining('已装 Loaded  ${first.boxes} / ${plan.totalBoxes}'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('stepBack')));
    await tester.pumpAndSettle();
    expect(find.textContaining('已装 Loaded  0 /'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('stepDone')));
    await tester.pumpAndSettle();

    // 关掉再开: 进度还在
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.textContaining('已装 Loaded  ${first.boxes} /'), findsOneWidget);

    // 3D 切换不会出错
    await tester.tap(find.textContaining('在柜里的位置'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 装完: 进入封柜检查
    for (var i = 1; i < plan.steps.length; i++) {
      await tester.tap(find.byKey(const ValueKey('stepDone')));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.textContaining('全部装完了'), findsOneWidget);
    expect(find.byKey(const ValueKey('stepDone')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('seal0')));
    await tester.pumpAndSettle();
    final saved = await loadProgress(progressKey(c), plan.steps.length);
    expect(saved.done, plan.steps.length);
    expect(saved.checklist, {0});
  });

  test('PDF prints a QR code when a link is provided', () async {
    final r = packContainers([item(1, '钢管 Steel', 305, 60, 40, 40), item(2, '配件 Parts', 423, 30, 30, 25, color: 0xFF3498DB)], presets);
    final font = File('assets/fonts/NotoSansSC-subset.ttf').readAsBytesSync();
    final user = UserProfile(email: 't@x.com', role: 'admin', status: 'active', companyName: '测试公司');
    final plain = await buildPdf(result: r, shipment: ShipmentInfo(), user: user, fontBytes: font, now: DateTime(2026, 1, 1));
    final withQr = await buildPdf(result: r, shipment: ShipmentInfo(), user: user, fontBytes: font, now: DateTime(2026, 1, 1), linkFor: (c, u, t) => workerLink(Uri.parse('https://boonlok.github.io/container-calc/'), c, u, t));
    File('build/test_qr.pdf')..createSync(recursive: true)..writeAsBytesSync(withQr);
    expect(withQr.length, greaterThan(plain.length));
  });
}
