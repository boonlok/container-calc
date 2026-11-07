/// 工人链接 Worker link
///
/// 把单个货柜的装柜计划压缩后放进网址的 # 后面, 工人手机扫码就能打开, 不需要登入。
/// # 后面的内容不会发送到任何服务器。链接里只有柜型和物品资料, 不含客户名称、公司或账号资料。
/// 打开时一律经过 ContainerResult.fromJson 清洗 (链接内容不可信)。
library;

import 'dart:convert';

import 'package:archive/archive.dart';

import '../core/models.dart';

const _prefix = 'load=';

class WorkerPlan {
  WorkerPlan(this.container, this.unit, this.totalUnits);
  final ContainerResult container;
  final int unit, totalUnits;
}

String encodeWorkerPayload(ContainerResult c, int unit, int totalUnits) {
  // 用数组而不是物件: 网址越短, 二维码越容易扫
  final compact = [
    unit, totalUnits, c.containerType, c.L, c.W, c.H, c.maxPayload, c.utilization, c.totalWeightUsed,
    [
      for (final a in c.allocations)
        [
          a.itemId, a.name, colorToHex(a.color), a.boxesPlaced, a.pcsPlaced, a.boxL, a.boxW, a.boxH, a.horizontal, a.vertical,
          a.columns, a.rotated ? 1 : 0, a.depthUnit, a.boxWeight, a.pcsPerBox, a.lengthUsed, a.startLength,
        ],
    ],
  ];
  final gz = GZipEncoder().encode(utf8.encode(jsonEncode(compact)));
  return base64Url.encode(gz).replaceAll('=', '');
}

/// 无法解读或内容不合理时回传 null
WorkerPlan? decodeWorkerPayload(String payload) {
  try {
    if (payload.isEmpty || payload.length > 200000) return null;
    final bytes = GZipDecoder().decodeBytes(base64Url.decode(base64Url.normalize(payload)));
    if (bytes.length > 2000000) return null;
    final d = jsonDecode(utf8.decode(bytes));
    if (d is! List || d.length < 10 || d[9] is! List) return null;
    final allocs = <Map<String, Object?>>[];
    for (final a in (d[9] as List).take(200)) {
      if (a is! List || a.length < 17) return null;
      allocs.add({
        'itemId': a[0], 'name': a[1], 'color': a[2], 'boxesPlaced': a[3], 'pcsPlaced': a[4], 'boxL': a[5], 'boxW': a[6], 'boxH': a[7],
        'horizontal': a[8], 'vertical': a[9], 'columns': a[10], 'rotated': a[11] == 1, 'depthUnit': a[12], 'boxWeight': a[13],
        'pcsPerBox': a[14], 'lengthUsed': a[15], 'startLength': a[16],
      });
    }
    final c = ContainerResult.fromJson({
      'containerType': d[2], 'L': d[3], 'W': d[4], 'H': d[5], 'maxPayload': d[6], 'utilization': d[7], 'totalWeightUsed': d[8], 'allocations': allocs,
    });
    if (c == null || c.allocations.isEmpty) return null;
    final unit = d[0] is num ? (d[0] as num).toInt() : 1, total = d[1] is num ? (d[1] as num).toInt() : 1;
    return WorkerPlan(c, unit.clamp(1, 9999), total.clamp(1, 9999));
  } catch (_) {
    return null;
  }
}

/// 目前网址若是工人链接, 取出 payload
String? workerPayloadFrom(Uri uri) {
  final f = uri.fragment;
  return f.startsWith(_prefix) ? f.substring(_prefix.length) : null;
}

String workerLink(Uri base, ContainerResult c, int unit, int totalUnits) {
  final clean = Uri(scheme: base.scheme, host: base.host, port: base.hasPort ? base.port : null, path: base.path);
  return '$clean#$_prefix${encodeWorkerPayload(c, unit, totalUnits)}';
}
