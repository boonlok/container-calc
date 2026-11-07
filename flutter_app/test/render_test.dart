import 'package:container_calc/core/algorithm.dart';
import 'package:container_calc/core/models.dart';
import 'package:container_calc/render/draw.dart';
import 'package:container_calc/render/flat_views.dart';
import 'package:container_calc/render/iso.dart';
import 'package:container_calc/render/notes.dart';
import 'package:flutter_test/flutter_test.dart';

final presets = [
  Preset(name: '20GP', length: 589, width: 235, height: 239, maxPayload: 28180),
  Preset(name: '45HC', length: 1355, width: 235, height: 269, maxPayload: 27600),
];

Item item(int id, String n, double pcs, double l, double w, double h, {int color = 0xFFE74C3C}) =>
    Item(id: id, name: n, totalPcs: pcs, pcsPerBox: 1, boxL: l, boxW: w, boxH: h, color: color);

void main() {
  final result = packContainers([item(1, 'A', 300, 60, 40, 40), item(2, 'B', 800, 30, 30, 25, color: 0xFF3498DB), item(3, 'C', 60, 100, 50, 50, color: 0xFF2ECC71)], presets);

  test('notes: bilingual worker notes match the web version wording', () {
    final c = result.containers.first;
    final info = describeAllocation(c.allocations.first, c, 0);
    expect(info.notes.first, startsWith('箱子'));
    expect(info.notes.any((n) => n.contains('First out')), isTrue);
    expect(info.notes.every((n) => RegExp(r'[一-鿿]').hasMatch(n)), isTrue);
    expect(fmt(1250.0), '1250');
    expect(fmt(33.5), '33.5');
  });

  test('flat views produce commands inside the canvas', () {
    final c = result.containers.first;
    final front = drawFlatView(c, buildStackedLayers(c, true));
    final right = drawRightView(c);
    for (final d in [front, right]) {
      expect(d.cmds.length, greaterThan(10));
      for (final cmd in d.cmds.whereType<Poly>()) {
        for (final p in cmd.pts) {
          expect(p.x, inInclusiveRange(-1, d.width + 1));
          expect(p.y, inInclusiveRange(-1, d.height + 1));
        }
      }
    }
  });

  test('iso: only the visible shell is drawn (no per-box explosion)', () {
    // 26k 个箱子的单区块
    final big = packContainers([item(1, 'S', 30000, 20, 15, 10)], [presets[1]]);
    final c = big.containers.first;
    final sw = Stopwatch()..start();
    final d = renderIso(c, IsoCamera.defaultFor(c));
    sw.stop();
    expect(lastPolygonCount, lessThan(6000), reason: 'polygons=$lastPolygonCount');
    expect(d.cmds.length, greaterThan(100));
    expect(sw.elapsedMilliseconds, lessThan(800), reason: '${sw.elapsedMilliseconds}ms');
  });

  test('iso: partial last column shows fewer boxes than a full grid', () {
    final r = packContainers([item(1, 'P', 100, 50, 40, 30)], [presets[0]]);
    final c = r.containers.first, a = c.allocations.first;
    expect(a.fullGrid, greaterThan(a.boxesPlaced)); // 前提: 最后一列没排满
    renderIso(c, IsoCamera.defaultFor(c), labels: false);
    final partial = lastPolygonCount;
    // 同尺寸、刚好排满的情况多边形数应不少于未排满的 (至少不会因多画箱子而更多)
    final full = packContainers([item(1, 'P', a.fullGrid.toDouble(), 50, 40, 30)], [presets[0]]).containers.first;
    renderIso(full, IsoCamera.defaultFor(full), labels: false);
    expect(partial, lessThanOrEqualTo(lastPolygonCount + 40));
  });

  test('iso: every viewpoint renders; closeups fade other sections', () {
    final c = result.containers.first;
    for (final vp in overviewViewpoints(c)) {
      final d = renderIso(c, IsoCamera(vp.dir), w: 420, h: 300);
      expect(d.cmds.whereType<Poly>().length, greaterThan(5), reason: vp.label);
    }
    expect(c.allocations.length, greaterThan(1));
    final plain = renderIso(c, IsoCamera.defaultFor(c), focus: null);
    final focused = renderIso(c, IsoCamera(closeupViewpoints(c, 0).first.dir), focus: 0);
    final fadedFills = focused.cmds.whereType<Poly>().where((p) => p.fill != null && (p.fill! >> 24) < 40).length;
    expect(fadedFills, greaterThan(0));
    expect(plain.cmds.whereType<Poly>().where((p) => p.fill != null && (p.fill! >> 24) < 40).length, lessThan(5));
    expect(closeupViewpoints(c, 0).length, 3);
  });

  test('models: json round trip + sanitising', () {
    final j = result.toJson();
    final back = PackResult.fromJson(j);
    expect(back, isNotNull);
    expect(back!.containers.length, result.containers.length);
    expect(back.containers.first.allocations.first.boxesPlaced, result.containers.first.allocations.first.boxesPlaced);
    // 恶意内容: 颜色会被中和, 不合理的资料整个丢弃
    expect(colorFromHex('red;background:url(x)'), 0xFF888888);
    expect(PackResult.fromJson({'containers': [{'containerType': 'x', 'L': 100, 'W': 100, 'H': 100, 'allocations': [{'horizontal': 0}]}]}), isNull);
    final items = Item.fromJson({'id': '"><x>', 'name': 'n', 'color': '"><img>', 'boxL': '"><b>', 'totalPcs': 5}, 0);
    expect(items.boxL, 0);
    expect(items.color, 0xFF888888);
  });
}
