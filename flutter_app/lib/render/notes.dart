/// 区块作业说明 (装柜工人注意事项) 与前/后视图的堆叠合成
///
/// 逐字移植自 Viewer3D.html 的 describeAllocation / buildStackedLayers (中英双语文字也相同)。
/// 约定: startLength = 该区块离「柜门端」的距离 (cm); 第 1 区块最靠近柜门。
library;

import '../core/models.dart';

/// 数字显示: 整数不带小数点 (与 JS 的字串拼接一致)
String fmt(num v) {
  final d = v.toDouble();
  return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
}

class SectionInfo {
  SectionInfo({
    required this.section,
    required this.name,
    required this.color,
    required this.pcsPerBox,
    required this.boxes,
    required this.pcs,
    required this.horizontal,
    required this.vertical,
    required this.columns,
    required this.boxDims,
    required this.rotated,
    required this.widthUnit,
    required this.depthUnit,
    required this.startLength,
    required this.endLength,
    required this.lengthUsed,
    required this.blockWidth,
    required this.blockHeight,
    required this.weightKg,
    required this.notes,
  });

  final int section;
  final String name;
  final int color;
  final double pcsPerBox, pcs, widthUnit, depthUnit, startLength, endLength, lengthUsed, blockWidth, blockHeight, weightKg;
  final int boxes, horizontal, vertical, columns;
  final String boxDims;
  final bool rotated;
  final List<String> notes;
}

SectionInfo describeAllocation(Allocation alloc, ContainerResult c, int idx) {
  final allocs = c.allocations;
  final widthUnit = alloc.widthUnit;
  final blockWidth = alloc.horizontal * widthUnit;
  final blockHeight = alloc.vertical * alloc.boxH;
  final pcsPerBox = alloc.pcsPerBox > 0
      ? alloc.pcsPerBox
      : (alloc.pcsPlaced / (alloc.boxesPlaced < 1 ? 1 : alloc.boxesPlaced)).roundToDouble();
  final weightKg = alloc.boxWeight * alloc.boxesPlaced;
  final endLength = alloc.endLength;
  final sideGap = round2(c.W - blockWidth);
  final topGap = round2(c.H - blockHeight);
  final next = idx + 1 < allocs.length ? allocs[idx + 1] : null;
  final prev = idx > 0 ? allocs[idx - 1] : null;
  final notes = <String>[];

  notes.add(alloc.rotated
      ? '箱子横放旋转 90°: 箱长 ${fmt(alloc.boxL)} cm 朝柜宽方向，箱宽 ${fmt(alloc.boxW)} cm 朝柜深方向 Rotated 90°'
      : '箱子正放: 箱宽 ${fmt(alloc.boxW)} cm 朝柜宽方向，箱长 ${fmt(alloc.boxL)} cm 朝柜深方向 Standard orientation');
  notes.add('每层横排 ${alloc.horizontal} 箱 × 直排 ${alloc.vertical} 层，前后共 ${alloc.columns} 列 '
      '(${alloc.horizontal}×${alloc.vertical}×${alloc.columns})');
  notes.add('起点离柜门 ${fmt(alloc.startLength)} cm，终点 ${fmt(endLength)} cm，占深 ${fmt(alloc.lengthUsed)} cm');
  if (alloc.fullGrid > alloc.boxesPlaced) {
    notes.add('最后一列未排满，实际 ${alloc.boxesPlaced} 箱 (满格 ${alloc.fullGrid}) — 最靠柜底的一列请从一侧靠边排放 Last column partial');
  }
  if (sideGap > 1) notes.add('左右合计留隙 ${fmt(sideGap)} cm — 请靠中间排并用气袋/木条填缝，防止横向滑动 Fill side gaps');
  if (topGap >= alloc.boxH * 0.5) {
    notes.add('顶部留空 ${fmt(topGap)} cm — 此区块不堆满，外露的上方空间请勿再堆放其他货物，必要时加固定带 Headroom left');
  }
  if (prev != null && prev.blockHeight > blockHeight + 1) {
    notes.add('门侧相邻区块 (${prev.name}) 比本区块高 ${fmt(round2(prev.blockHeight - blockHeight))} cm — '
        '本区块上方留有空隙，装柜时需先放稳本区块 Neighbour taller');
  }
  if (next != null && next.blockHeight > blockHeight + 1) {
    notes.add('柜底侧相邻区块 (${next.name}) 比本区块高 ${fmt(round2(next.blockHeight - blockHeight))} cm — '
        '请确认高处货物后方有挡板/固定 Back neighbour taller');
  }
  if (idx == allocs.length - 1) {
    final rest = round2(c.L - endLength);
    if (rest > 1) notes.add('此区块之后至柜底尚余 ${fmt(rest)} cm 空间，请用填充物顶紧避免货物前后滑动 Remaining length at back');
  }
  if (idx == 0) {
    notes.add('最靠柜门: 开门后最先看到本区块，卸货时最先取出 First out');
    if (alloc.startLength > 1) {
      notes.add('货物顶住柜底后，本区块与柜门之间尚余 ${fmt(alloc.startLength)} cm，请用填充物顶紧避免货物前后滑动 Fill the gap at the door');
    }
  }

  return SectionInfo(
    section: idx + 1, name: alloc.name, color: alloc.color, pcsPerBox: pcsPerBox, boxes: alloc.boxesPlaced,
    pcs: alloc.pcsPlaced, horizontal: alloc.horizontal, vertical: alloc.vertical, columns: alloc.columns,
    boxDims: '${fmt(alloc.boxL)}×${fmt(alloc.boxW)}×${fmt(alloc.boxH)}', rotated: alloc.rotated,
    widthUnit: widthUnit, depthUnit: alloc.depthUnit, startLength: alloc.startLength, endLength: endLength,
    lengthUsed: alloc.lengthUsed, blockWidth: round2(blockWidth), blockHeight: round2(blockHeight),
    weightKg: round2(weightKg), notes: notes,
  );
}

/// 正面/背面视图的一层 (近端物品挡住, 没堆到柜顶时上方露出次近物品的合成)
class StackLayer {
  StackLayer({
    required this.name,
    required this.color,
    required this.horizontal,
    required this.vertical,
    required this.boxH,
    required this.widthUnit,
    required this.pcsPerBox,
    required this.yOffset,
  });
  final String name;
  final int color, horizontal, vertical;
  final double boxH, widthUnit, pcsPerBox, yOffset;
}

List<StackLayer> buildStackedLayers(ContainerResult c, bool fromFront) {
  final order = fromFront ? c.allocations : c.allocations.reversed.toList();
  final layers = <StackLayer>[];
  var usedHeight = 0.0;
  for (final alloc in order) {
    if (usedHeight >= c.H - 0.01) break;
    final remaining = c.H - usedHeight;
    final fit = (remaining / alloc.boxH).floor();
    final vCount = alloc.vertical < fit ? alloc.vertical : fit;
    if (vCount <= 0) continue;
    layers.add(StackLayer(
      name: alloc.name, color: alloc.color, horizontal: alloc.horizontal, vertical: vCount, boxH: alloc.boxH,
      widthUnit: alloc.widthUnit,
      pcsPerBox: alloc.boxesPlaced > 0 ? (alloc.pcsPlaced / alloc.boxesPlaced).roundToDouble() : 0,
      yOffset: usedHeight,
    ));
    usedHeight += vCount * alloc.boxH;
  }
  return layers;
}
