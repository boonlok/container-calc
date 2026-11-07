/// 现场装柜顺序 Loading sequence
///
/// 工人是站在柜门往里装的, 所以顺序一定是「柜底 → 柜门」: 最后一个区块先装 (离柜门最远), 每个区块由远到近一列一列装。
/// 每一列就是一个工作步骤, 工人每装完一列按一下。
library;

import 'models.dart';

class LoadStep {
  const LoadStep({
    required this.index,
    required this.allocIndex,
    required this.column,
    required this.columnNo,
    required this.columnsInSection,
    required this.boxes,
    required this.boxesBefore,
    required this.sectionNo,
  });

  final int index; // 整柜第几步 (0 起)
  final int allocIndex; // 对应 container.allocations 的序号
  final int column; // 区块内的列序号 (0 = 离柜门最近)
  final int columnNo; // 本区块第几列要装 (1 起, 依装柜顺序)
  final int columnsInSection;
  final int boxes; // 本列箱数
  final int boxesBefore; // 这一步之前已装箱数 (整柜)
  final int sectionNo; // 第几个要装的区块 (1 起, 依装柜顺序)

  bool get isSectionStart => columnNo == 1;
}

/// 一列里的箱子怎么摆: 由下往上, 同一层从左到右 (站在柜门看)
class ColumnLayout {
  const ColumnLayout({required this.fullLayers, required this.topLayerBoxes, required this.horizontal});
  final int fullLayers, topLayerBoxes, horizontal;
}

class LoadingPlan {
  LoadingPlan(this.container) : steps = _build(container);

  final ContainerResult container;
  final List<LoadStep> steps;

  int get totalBoxes => container.allocations.fold(0, (s, a) => s + a.boxesPlaced);
  int get sectionCount => container.allocations.length;

  /// 所有货物占用的总长度
  double get usedLength => container.allocations.fold(0.0, (s, a) => s + a.lengthUsed);

  /// 货物全部顶住柜底后, 靠柜门这边剩下的长度
  double get doorGap {
    final g = container.L - usedLength;
    return g < 0 ? 0 : round2(g);
  }

  /// 这一步的货离柜底多远 (工人从最里面开始, 量柜底比量柜门直觉)
  double fromFarWall(LoadStep s) {
    var d = 0.0;
    for (var i = 0; i < s.index; i++) {
      d += container.allocations[steps[i].allocIndex].depthUnit;
    }
    return round2(d);
  }

  static int boxesInColumn(Allocation a, int column) {
    final perColumn = a.horizontal * a.vertical;
    final remaining = a.boxesPlaced - column * perColumn;
    if (remaining <= 0) return 0;
    return remaining < perColumn ? remaining : perColumn;
  }

  static ColumnLayout layoutOf(Allocation a, int boxes) =>
      ColumnLayout(fullLayers: boxes ~/ a.horizontal, topLayerBoxes: boxes % a.horizontal, horizontal: a.horizontal);

  static List<LoadStep> _build(ContainerResult c) {
    final out = <LoadStep>[];
    var before = 0, sectionNo = 0;
    for (var i = c.allocations.length - 1; i >= 0; i--) {
      final a = c.allocations[i];
      sectionNo++;
      final cols = <int>[for (var k = a.columns - 1; k >= 0; k--) if (boxesInColumn(a, k) > 0) k];
      for (var n = 0; n < cols.length; n++) {
        final boxes = boxesInColumn(a, cols[n]);
        out.add(LoadStep(
          index: out.length, allocIndex: i, column: cols[n], columnNo: n + 1, columnsInSection: cols.length,
          boxes: boxes, boxesBefore: before, sectionNo: sectionNo,
        ));
        before += boxes;
      }
    }
    return out;
  }

  /// 已完成 done 步时已装的箱数
  int boxesDone(int done) {
    if (done <= 0) return 0;
    if (done >= steps.length) return totalBoxes;
    return steps[done].boxesBefore;
  }

  /// 第一个属于该区块的步骤序号
  int firstStepOf(int allocIndex) => steps.indexWhere((s) => s.allocIndex == allocIndex);

  /// 该区块已完成几箱 / 共几箱
  (int, int) sectionProgress(int allocIndex, int done) {
    final a = container.allocations[allocIndex];
    var n = 0;
    for (var i = 0; i < done && i < steps.length; i++) {
      if (steps[i].allocIndex == allocIndex) n += steps[i].boxes;
    }
    return (n, a.boxesPlaced);
  }
}
