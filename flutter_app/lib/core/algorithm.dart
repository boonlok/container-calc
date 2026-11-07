/// 装箱算法 Packing algorithm
///
/// 从 JavaScript.html 逐行移植, 行为必须一致 (test/golden_test.dart 用 node 版的输出逐项比对):
///   · 同一个货柜里, 每样物品占一段连续的「深度区块」(像书架分层), 区块内是整齐的 横×直×深 网格
///   · 只允许水平面 90° 旋转, 高度方向固定
///   · 「物品排序 × 选柜策略」共 9 种组合各完整计算一遍, 取 (未装箱数, 柜数, 总柜容积, 平均利用率) 最好的一套
library;

import 'models.dart';

int calcBoxesNeeded(Item it) => (it.totalPcs / it.pcsPerBox).ceil();

/// 装箱过程中的物品 (带剩余箱数)
class PackItem {
  PackItem(this.item) : boxesRemaining = calcBoxesNeeded(item);
  PackItem._copy(this.item, this.boxesRemaining);

  final Item item;
  int boxesRemaining;

  PackItem copy() => PackItem._copy(item, boxesRemaining);
  double get unitVolume => item.boxL * item.boxW * item.boxH;
  double get remainingVolume => unitVolume * boxesRemaining;
}

class Grid {
  Grid(this.horizontal, this.vertical, this.depthUnit, this.rotated);
  final int horizontal, vertical;
  final double depthUnit;
  final bool rotated;
}

int _floorDiv(double a, double b) => (a / b).floor();

/// 决定物品在柜内的最佳排列方向。needed: 还需要放的箱数 —— 两种方向都装得下时选「占用柜长较短」的,
/// 装不下时才选「可放箱数较多」的 (needed 为 null 则只比容量)。
Grid bestFitGrid(double boxL, double boxW, double boxH, double availL, double contW, double contH, {int? needed}) {
  final a = Grid(_floorDiv(contW, boxW), _floorDiv(contH, boxH), boxL, false);
  final b = Grid(_floorDiv(contW, boxL), _floorDiv(contH, boxH), boxW, true);
  final perA = a.horizontal * a.vertical, perB = b.horizontal * b.vertical;
  final totalA = perA * _floorDiv(availL, a.depthUnit < 0.0001 ? 0.0001 : a.depthUnit);
  final totalB = perB * _floorDiv(availL, b.depthUnit < 0.0001 ? 0.0001 : b.depthUnit);
  if (needed != null && needed > 0 && totalA >= needed && totalB >= needed && perA > 0 && perB > 0) {
    final lenA = (needed / perA).ceil() * a.depthUnit, lenB = (needed / perB).ceil() * b.depthUnit;
    if (lenA != lenB) return lenB < lenA ? b : a;
    return perB > perA ? b : a;
  }
  return totalB > totalA ? b : a;
}

class FillResult {
  FillResult(this.utilization, this.allocations, this.totalWeightUsed, this.totalVolumeUsed, this.remainingLength);
  final double utilization;
  final List<Allocation> allocations;
  final double totalWeightUsed, totalVolumeUsed, remainingLength;
}

double _maxPayloadOf(Preset c) => c.maxPayload > 0 ? c.maxPayload : 999999999;

/// 把 items (会被修改 boxesRemaining) 依序填进一个货柜
FillResult simulateFillContainer(List<PackItem> items, Preset cont) {
  var remainingLength = cont.length;
  var totalVolumeUsed = 0.0, totalWeightUsed = 0.0;
  final allocations = <Allocation>[];
  final maxPayload = _maxPayloadOf(cont);

  for (final pi in items) {
    final item = pi.item;
    if (pi.boxesRemaining <= 0) continue;
    if (remainingLength <= 0) break;

    final grid = bestFitGrid(item.boxL, item.boxW, item.boxH, remainingLength, cont.width, cont.height, needed: pi.boxesRemaining);
    final perColumn = grid.horizontal * grid.vertical;
    if (perColumn == 0) continue; // 尺寸超过柜内空间, 此柜型无法容纳该物品

    final maxColumnsAvailable = _floorDiv(remainingLength, grid.depthUnit);
    if (maxColumnsAvailable <= 0) continue;

    final columnsNeeded = (pi.boxesRemaining / perColumn).ceil();
    final columnsToUse = columnsNeeded < maxColumnsAvailable ? columnsNeeded : maxColumnsAvailable;
    var boxesPlaced = pi.boxesRemaining < columnsToUse * perColumn ? pi.boxesRemaining : columnsToUse * perColumn;

    if (item.boxWeight > 0) {
      final weightLeft = maxPayload - totalWeightUsed;
      final maxByWeight = (weightLeft / item.boxWeight).floor();
      final cap = maxByWeight < 0 ? 0 : maxByWeight;
      if (cap < boxesPlaced) boxesPlaced = cap;
    }
    if (boxesPlaced <= 0) continue;

    final actualColumns = (boxesPlaced / perColumn).ceil();
    final lengthUsed = actualColumns * grid.depthUnit;

    allocations.add(Allocation(
      itemId: item.id, name: item.name, color: item.color, boxesPlaced: boxesPlaced,
      pcsPlaced: boxesPlaced * item.pcsPerBox, boxL: item.boxL, boxW: item.boxW, boxH: item.boxH,
      horizontal: grid.horizontal, vertical: grid.vertical, columns: actualColumns, rotated: grid.rotated,
      depthUnit: grid.depthUnit, boxWeight: item.boxWeight, pcsPerBox: item.pcsPerBox,
      lengthUsed: round2(lengthUsed), startLength: round2(cont.length - remainingLength),
    ));

    remainingLength -= lengthUsed;
    totalVolumeUsed += boxesPlaced * item.boxL * item.boxW * item.boxH;
    totalWeightUsed += boxesPlaced * item.boxWeight;
    pi.boxesRemaining -= boxesPlaced;
  }

  final containerVolume = cont.length * cont.width * cont.height;
  return FillResult(containerVolume > 0 ? totalVolumeUsed / containerVolume : 0, allocations, totalWeightUsed,
      totalVolumeUsed, remainingLength);
}

// ---------- 多策略装柜 ----------

typedef OrderFn = int Function(PackItem a, PackItem b);

int _byVolume(PackItem a, PackItem b) => b.remainingVolume.compareTo(a.remainingVolume);

/// 物品排序方式 (key 的顺序固定: 第一个组合 = 原本的算法)
final Map<String, OrderFn> packOrderings = {
  'volume': _byVolume,
  'height': (a, b) {
    final d = b.item.boxH.compareTo(a.item.boxH);
    return d != 0 ? d : _byVolume(a, b);
  },
  'footprint': (a, b) {
    final d = (b.item.boxL * b.item.boxW).compareTo(a.item.boxL * a.item.boxW);
    return d != 0 ? d : _byVolume(a, b);
  },
};

class Candidate {
  Candidate(this.cont, this.result, this.leftover) : vol = cont.volume;
  final Preset cont;
  final FillResult result;
  final int leftover;
  final double vol;
}

typedef PolicyFn = Candidate? Function(List<Candidate> cands);

Candidate? _reduce(List<Candidate> cands, bool Function(Candidate c, Candidate best) better) {
  Candidate? best;
  for (final c in cands) {
    if (best == null || better(c, best)) best = c;
  }
  return best;
}

final Map<String, PolicyFn> packPolicies = {
  'util': (cands) => _reduce(cands, (c, b) => c.result.utilization > b.result.utilization),
  'fit': (cands) {
    final done = cands.where((c) => c.leftover == 0).toList(); // 剩余物品全部放得下的柜型里, 挑最小的
    if (done.isNotEmpty) {
      return _reduce(done, (c, b) => c.vol < b.vol || (c.vol == b.vol && c.result.utilization > b.result.utilization));
    }
    return _reduce(cands, (c, b) => c.result.totalVolumeUsed > b.result.totalVolumeUsed);
  },
  'max': (cands) => _reduce(
      cands,
      (c, b) =>
          c.result.totalVolumeUsed > b.result.totalVolumeUsed ||
          (c.result.totalVolumeUsed == b.result.totalVolumeUsed && c.vol < b.vol)),
};

/// JS 的 Array.sort 是稳定排序, Dart 的 List.sort 不是 —— 用原序号当平手时的依据, 结果才与 JS 版一致
List<PackItem> _stableSorted(List<PackItem> items, OrderFn cmp) {
  final idx = <PackItem, int>{for (var i = 0; i < items.length; i++) items[i]: i};
  final out = List<PackItem>.of(items);
  out.sort((a, b) {
    final d = cmp(a, b);
    return d != 0 ? d : idx[a]!.compareTo(idx[b]!);
  });
  return out;
}

PackResult packWithStrategy(List<Item> itemsInput, List<Preset> presets, OrderFn orderFn, PolicyFn policyFn) {
  final items = itemsInput.map((i) => PackItem(i)).toList();
  final used = <ContainerResult>[];
  var safety = 0;

  while (items.any((i) => i.boxesRemaining > 0) && safety < 800) {
    safety++;
    final sorted = _stableSorted(items, orderFn);

    final cands = <Candidate>[];
    for (final cont in presets) {
      final copies = sorted.map((i) => i.copy()).toList();
      final r = simulateFillContainer(copies, cont);
      if (r.allocations.isEmpty) continue;
      cands.add(Candidate(cont, r, copies.fold(0, (s, i) => s + i.boxesRemaining)));
    }
    final best = policyFn(cands);
    if (best == null) break; // 剩余物品无法装入任何可用柜型

    for (final al in best.result.allocations) {
      items.firstWhere((i) => i.item.id == al.itemId).boxesRemaining -= al.boxesPlaced;
    }
    used.add(ContainerResult(
      containerType: best.cont.name, L: best.cont.length, W: best.cont.width, H: best.cont.height,
      allocations: best.result.allocations, utilization: best.result.utilization,
      totalWeightUsed: round2(best.result.totalWeightUsed), maxPayload: best.cont.maxPayload,
    ));
  }
  return PackResult(used, [for (final i in items) if (i.boxesRemaining > 0) Unfulfilled(i.item.name, i.boxesRemaining)],
      items: itemsInput.map((i) => i.copy()).toList());
}

/// 数值越小越好: [未装箱数, 柜数, 总柜容积, -平均利用率]
List<double> packScore(PackResult r) {
  final left = r.unfulfilled.fold(0, (s, u) => s + u.boxesRemaining).toDouble();
  final vol = r.containers.fold(0.0, (s, c) => s + c.L * c.W * c.H);
  final util = r.containers.isEmpty ? 0.0 : r.avgUtilization;
  return [left, r.containers.length.toDouble(), vol, -util];
}

bool packScoreLess(List<double> a, List<double> b) {
  for (var i = 0; i < a.length; i++) {
    if ((a[i] - b[i]).abs() > 1e-9) return a[i] < b[i];
  }
  return false; // 完全相同: 保留先算出的 (原本算法) 结果
}

PackResult packContainers(List<Item> items, List<Preset> presets) {
  PackResult? best;
  List<double>? bestScore;
  for (final o in packOrderings.values) {
    for (final p in packPolicies.values) {
      final r = packWithStrategy(items, presets, o, p);
      final s = packScore(r);
      if (best == null || packScoreLess(s, bestScore!)) {
        best = r;
        bestScore = s;
      }
    }
  }
  return best!;
}

/// 输入检查 (中英双语讯息), 回传错误清单
List<String> validateItems(List<Item> items) {
  final errors = <String>[];
  if (items.isEmpty) errors.add('请至少添加一样物品 Please add at least one item');
  for (var i = 0; i < items.length; i++) {
    final it = items[i];
    final label = it.name.isEmpty ? '第 ${i + 1} 行 Row ${i + 1}' : it.name;
    if (it.name.trim().isEmpty) errors.add('$label: 缺少物品名称 missing item name');
    if (!(it.totalPcs > 0)) errors.add('$label: 总数量 PCS 需大于 0 PCS must be > 0');
    if (!(it.pcsPerBox > 0)) errors.add('$label: 每箱 PCS 需大于 0 PCS/box must be > 0');
    if (!(it.boxL > 0) || !(it.boxW > 0) || !(it.boxH > 0)) {
      errors.add('$label: 箱子尺寸需为大于 0 的数字 box dimensions must be > 0');
    }
    if (it.boxWeight < 0) errors.add('$label: 重量不能为负 weight cannot be negative');
  }
  return errors;
}
