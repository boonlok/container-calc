/// 数据模型 Data models
///
/// 与 JavaScript 版 (JavaScript.html) 的字段一一对应, 序列化格式 (toJson) 也相同,
/// 所以 Apps Script / Supabase 网页版保存的历史记录可以直接在 Flutter 版载入, 反之亦然。
library;

import 'dart:math' as math;

double round2(double n) => (n * 100).round() / 100;

double _num(Object? v, [double d = 0]) {
  final n = v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');
  return (n == null || n.isNaN || n.isInfinite) ? d : n;
}

String _str(Object? s, [int max = 200]) {
  final t = s == null ? '' : s.toString();
  return t.length > max ? t.substring(0, max) : t;
}

/// 只接受 #rrggbb, 其它一律当作灰色 (载入的记录不可信, 不让它进入样式/绘图)
int colorFromHex(Object? c, {int fallback = 0xFF888888}) {
  final s = c?.toString() ?? '';
  if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(s)) return fallback;
  return 0xFF000000 | int.parse(s.substring(1), radix: 16);
}

String colorToHex(int argb) => '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// 物品清单里的一行 (输入值, 0 表示还没填)
class Item {
  Item({
    required this.id,
    this.name = '',
    this.totalPcs = 0,
    this.pcsPerBox = 0,
    this.boxL = 0,
    this.boxW = 0,
    this.boxH = 0,
    this.boxWeight = 0,
    this.color = 0xFFE74C3C,
  });

  int id;
  String name;
  double totalPcs, pcsPerBox, boxL, boxW, boxH, boxWeight;
  int color;

  int get boxesNeeded => (totalPcs > 0 && pcsPerBox > 0) ? (totalPcs / pcsPerBox).ceil() : 0;

  Item copy() => Item(
      id: id, name: name, totalPcs: totalPcs, pcsPerBox: pcsPerBox, boxL: boxL, boxW: boxW,
      boxH: boxH, boxWeight: boxWeight, color: color);

  Map<String, Object?> toJson() => {
        'id': id, 'name': name, 'color': colorToHex(color),
        'totalPcs': totalPcs == 0 ? '' : _clean(totalPcs), 'pcsPerBox': pcsPerBox == 0 ? '' : _clean(pcsPerBox),
        'boxL': boxL == 0 ? '' : _clean(boxL), 'boxW': boxW == 0 ? '' : _clean(boxW), 'boxH': boxH == 0 ? '' : _clean(boxH),
        'boxWeight': boxWeight == 0 ? '' : _clean(boxWeight),
      };

  static Object _clean(double v) => v == v.roundToDouble() ? v.toInt() : v;

  /// 清洗后建立 (与 sanitizeItems 相同的规则)
  static Item fromJson(Map<String, Object?> j, int index) => Item(
        id: _num(j['id'], index + 1.0).floor(),
        name: _str(j['name']),
        color: colorFromHex(j['color']),
        totalPcs: _num(j['totalPcs']), pcsPerBox: _num(j['pcsPerBox']),
        boxL: _num(j['boxL']), boxW: _num(j['boxW']), boxH: _num(j['boxH']), boxWeight: _num(j['boxWeight']),
      );
}

/// 柜型预设
class Preset {
  Preset({
    this.id,
    required this.name,
    required this.length,
    required this.width,
    required this.height,
    required this.maxPayload,
    this.active = true,
    this.owner = '',
  });

  final int? id; // 后端行 id (_row)
  final String name;
  final double length, width, height, maxPayload;
  final bool active;
  final String owner; // 空 = 共用预设

  bool get isShared => owner.trim().isEmpty;
  double get volume => length * width * height;
}

/// 柜内一个物品区块 (沿柜深连续的一段)
class Allocation {
  Allocation({
    required this.itemId,
    required this.name,
    required this.color,
    required this.boxesPlaced,
    required this.pcsPlaced,
    required this.boxL,
    required this.boxW,
    required this.boxH,
    required this.horizontal,
    required this.vertical,
    required this.columns,
    required this.rotated,
    required this.depthUnit,
    required this.boxWeight,
    required this.pcsPerBox,
    required this.lengthUsed,
    required this.startLength,
  });

  final int itemId;
  final String name;
  final int color;
  final int boxesPlaced;
  final double pcsPlaced;
  final double boxL, boxW, boxH;
  final int horizontal, vertical, columns;
  final bool rotated;
  final double depthUnit, boxWeight, pcsPerBox, lengthUsed, startLength;

  /// 箱子在柜宽方向占的尺寸
  double get widthUnit => rotated ? boxL : boxW;
  double get blockWidth => horizontal * widthUnit;
  double get blockHeight => vertical * boxH;
  double get endLength => round2(startLength + lengthUsed);
  int get fullGrid => columns * horizontal * vertical;

  Map<String, Object?> toJson() => {
        'itemId': itemId, 'name': name, 'color': colorToHex(color), 'boxesPlaced': boxesPlaced, 'pcsPlaced': pcsPlaced,
        'boxL': boxL, 'boxW': boxW, 'boxH': boxH, 'horizontal': horizontal, 'vertical': vertical, 'columns': columns,
        'rotated': rotated, 'depthUnit': depthUnit, 'boxWeight': boxWeight, 'pcsPerBox': pcsPerBox,
        'lengthUsed': lengthUsed, 'startLength': startLength,
      };

  /// 清洗 + 校验; 不合理 (非正数) 则回传 null, 调用方改为重新计算
  static Allocation? fromJson(Map<String, Object?> a) {
    final al = Allocation(
      itemId: _num(a['itemId']).floor(), name: _str(a['name']), color: colorFromHex(a['color']),
      boxesPlaced: _num(a['boxesPlaced']).floor(), pcsPlaced: _num(a['pcsPlaced']),
      boxL: _num(a['boxL']), boxW: _num(a['boxW']), boxH: _num(a['boxH']),
      horizontal: _num(a['horizontal']).floor(), vertical: _num(a['vertical']).floor(), columns: _num(a['columns']).floor(),
      rotated: a['rotated'] == true, depthUnit: _num(a['depthUnit']), boxWeight: _num(a['boxWeight']),
      pcsPerBox: _num(a['pcsPerBox']), lengthUsed: _num(a['lengthUsed']), startLength: _num(a['startLength']),
    );
    final ok = al.horizontal > 0 && al.vertical > 0 && al.columns > 0 && al.boxL > 0 && al.boxW > 0 &&
        al.boxH > 0 && al.depthUnit > 0 && al.boxesPlaced > 0;
    return ok ? al : null;
  }
}

class ContainerResult {
  ContainerResult({
    required this.containerType,
    required this.L,
    required this.W,
    required this.H,
    required this.allocations,
    required this.utilization,
    required this.totalWeightUsed,
    required this.maxPayload,
  });

  final String containerType;
  final double L, W, H;
  final List<Allocation> allocations;
  final double utilization, totalWeightUsed, maxPayload;

  Map<String, Object?> toJson() => {
        'containerType': containerType, 'L': L, 'W': W, 'H': H, 'utilization': utilization,
        'totalWeightUsed': totalWeightUsed, 'maxPayload': maxPayload,
        'allocations': allocations.map((a) => a.toJson()).toList(),
      };

  static ContainerResult? fromJson(Map<String, Object?> c) {
    final raw = c['allocations'];
    final allocs = <Allocation>[];
    if (raw is List) {
      for (final a in raw.take(200)) {
        if (a is! Map) return null;
        final al = Allocation.fromJson(a.cast<String, Object?>());
        if (al == null) return null;
        allocs.add(al);
      }
    }
    final r = ContainerResult(
      containerType: _str(c['containerType']), L: _num(c['L']), W: _num(c['W']), H: _num(c['H']), allocations: allocs,
      utilization: _num(c['utilization']), totalWeightUsed: _num(c['totalWeightUsed']), maxPayload: _num(c['maxPayload']),
    );
    return (r.L > 0 && r.W > 0 && r.H > 0) ? r : null;
  }
}

class Unfulfilled {
  Unfulfilled(this.name, this.boxesRemaining);
  final String name;
  final int boxesRemaining;
}

class PackResult {
  PackResult(this.containers, this.unfulfilled, {List<Item>? items}) : items = items ?? const [];

  final List<ContainerResult> containers;
  final List<Unfulfilled> unfulfilled;

  /// 计算当时的物品清单 (PDF 总览用; 不进历史记录)
  final List<Item> items;

  Map<String, Object?> toJson() => {
        'containers': containers.map((c) => c.toJson()).toList(),
        'unfulfilled': unfulfilled.map((u) => {'name': u.name, 'boxesRemaining': u.boxesRemaining}).toList(),
      };

  /// 与 sanitizeResult 相同: 任何不合理就回传 null
  static PackResult? fromJson(Object? r, {List<Item> items = const []}) {
    if (r is! Map) return null;
    final raw = r['containers'];
    if (raw is! List || raw.isEmpty) return null;
    final cs = <ContainerResult>[];
    for (final c in raw.take(800)) {
      if (c is! Map) return null;
      final cr = ContainerResult.fromJson(c.cast<String, Object?>());
      if (cr == null) return null;
      cs.add(cr);
    }
    final un = <Unfulfilled>[];
    final ru = r['unfulfilled'];
    if (ru is List) {
      for (final u in ru.take(500)) {
        if (u is Map) un.add(Unfulfilled(_str(u['name']), _num(u['boxesRemaining']).floor()));
      }
    }
    return PackResult(cs, un, items: items);
  }

  int get totalBoxes => containers.fold(0, (s, c) => s + c.allocations.fold(0, (s2, a) => s2 + a.boxesPlaced));
  double get totalPcs => containers.fold(0.0, (s, c) => s + c.allocations.fold(0.0, (s2, a) => s2 + a.pcsPlaced));
  double get avgUtilization =>
      containers.isEmpty ? 0 : containers.fold(0.0, (s, c) => s + c.utilization) / containers.length;
}

/// 货运信息 (PDF 表头/表格用)
class ShipmentInfo {
  ShipmentInfo({
    this.customer = '',
    this.etd = '',
    this.eta = '',
    this.shippingLine = '',
    this.remark = '',
    this.drawn = '',
    this.checked = '',
    this.confirmed = '',
    List<Accessory>? accessories,
  }) : accessories = accessories ?? [];

  String customer, etd, eta, shippingLine, remark, drawn, checked, confirmed;
  List<Accessory> accessories;

  Map<String, Object?> toJson() => {
        'customer': customer, 'etd': etd, 'eta': eta, 'shippingLine': shippingLine, 'remark': remark,
        'drawn': drawn, 'checked': checked, 'confirmed': confirmed,
        'accessories': accessories.where((a) => a.name.isNotEmpty).map((a) => {'name': a.name, 'qty': a.qty}).toList(),
      };

  static ShipmentInfo fromJson(Map<String, Object?> j) {
    String s(String k, [int m = 300]) => _str(j[k], m);
    String d(String k) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s(k)) ? s(k) : '';
    final acc = <Accessory>[];
    final ra = j['accessories'];
    if (ra is List) {
      for (final a in ra.take(100)) {
        if (a is Map) acc.add(Accessory(name: _str(a['name'], 100), qty: _str(a['qty'], 30)));
      }
    }
    return ShipmentInfo(
      customer: s('customer'), etd: d('etd'), eta: d('eta'), shippingLine: s('shippingLine'), remark: s('remark'),
      drawn: s('drawn'), checked: s('checked'), confirmed: s('confirmed'), accessories: acc,
    );
  }
}

class Accessory {
  Accessory({this.name = '', this.qty = ''});
  String name, qty;
}

/// 登入用户资料 (profiles 表)
class UserProfile {
  UserProfile({
    required this.email,
    required this.role,
    required this.status,
    this.companyName = '',
    this.companyAddress = '',
    this.logoDataUrl = '',
  });

  final String email, role, status, companyName, companyAddress, logoDataUrl;
  bool get isAdmin => role == 'admin';
  bool get isActive => status == 'active';
}

/// 历史记录列表里的一行 (不含 data, 载入时才单独取)
class HistoryRow {
  HistoryRow({required this.id, required this.name, required this.date, required this.totalItems, required this.totalContainers, required this.summary, required this.owner});
  final String id, name, date, summary, owner;
  final int totalItems, totalContainers;
}

int clampInt(int v, int lo, int hi) => math.max(lo, math.min(hi, v));
