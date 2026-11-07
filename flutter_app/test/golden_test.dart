// 装箱算法必须与网页版 (JavaScript.html) 逐项一致: 基准数据由 tool/make_golden.js 用 node 产生。
import 'dart:convert';
import 'dart:io';

import 'package:container_calc/core/algorithm.dart';
import 'package:container_calc/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final golden = jsonDecode(File('test/golden/algo_golden.json').readAsStringSync()) as List;

  test('golden file has scenarios', () => expect(golden.length, greaterThan(40)));

  for (final s in golden) {
    final sc = s as Map<String, dynamic>;
    test('matches web version: ${sc['name']}', () {
      final items = (sc['items'] as List)
          .map((j) => Item.fromJson((j as Map).cast<String, Object?>(), 0))
          .toList();
      final presets = (sc['presets'] as List)
          .map((p) => Preset(
              name: p['name'] as String, length: (p['L'] as num).toDouble(), width: (p['W'] as num).toDouble(),
              height: (p['H'] as num).toDouble(), maxPayload: (p['maxPayload'] as num).toDouble()))
          .toList();
      final got = packContainers(items, presets);
      final want = sc['result'] as Map<String, dynamic>;
      final wc = want['containers'] as List;

      expect(got.containers.length, wc.length, reason: 'container count');
      for (var i = 0; i < wc.length; i++) {
        final w = wc[i] as Map<String, dynamic>, g = got.containers[i];
        expect(g.containerType, w['containerType']);
        expect(g.utilization, closeTo((w['utilization'] as num).toDouble(), 1e-9));
        expect(g.totalWeightUsed, closeTo((w['totalWeightUsed'] as num).toDouble(), 1e-9));
        final wa = w['allocations'] as List;
        expect(g.allocations.length, wa.length, reason: 'allocations in container $i');
        for (var k = 0; k < wa.length; k++) {
          final a = wa[k] as Map<String, dynamic>, b = g.allocations[k];
          expect(b.itemId, a['itemId']);
          expect(b.boxesPlaced, a['boxesPlaced']);
          expect(b.pcsPlaced, closeTo((a['pcsPlaced'] as num).toDouble(), 1e-9));
          expect(b.horizontal, a['horizontal']);
          expect(b.vertical, a['vertical']);
          expect(b.columns, a['columns']);
          expect(b.rotated, a['rotated']);
          expect(b.lengthUsed, closeTo((a['lengthUsed'] as num).toDouble(), 1e-9));
          expect(b.startLength, closeTo((a['startLength'] as num).toDouble(), 1e-9));
        }
      }
      final wu = want['unfulfilled'] as List;
      expect(got.unfulfilled.length, wu.length);
      for (var i = 0; i < wu.length; i++) {
        expect(got.unfulfilled[i].name, wu[i]['name']);
        expect(got.unfulfilled[i].boxesRemaining, wu[i]['boxesRemaining']);
      }
    });
  }

  test('validateItems reports bilingual errors', () {
    final errs = validateItems([Item(id: 1)]);
    expect(errs.length, greaterThanOrEqualTo(4));
    expect(errs.every((e) => RegExp(r'[一-鿿]').hasMatch(e) && RegExp(r'[A-Za-z]').hasMatch(e)), isTrue);
  });
}
