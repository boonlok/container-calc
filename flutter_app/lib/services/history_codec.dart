/// 历史记录的打包与还原 (与网页版格式相同, 可互相载入)
///
/// 网页版: 完整内容 → gzip → base64, 存成 {v:2, z:"..."}; 小的直接存原始 JSON。
/// Flutter 版写出原始 JSON (Supabase 的 jsonb 可放 2MB), 太大才用 gzip; 读取两种格式都认。
library;

import 'dart:convert';

import 'package:archive/archive.dart';

import '../core/models.dart';

const _rawLimit = 1500000; // 超过这个字数才压缩

Map<String, Object?> packHistory(List<Item> items, PackResult? result, ShipmentInfo shipment) {
  final full = <String, Object?>{
    'items': items.map((i) => i.toJson()).toList(),
    if (result != null) 'result': result.toJson(),
    'shipment': shipment.toJson(),
  };
  final json = jsonEncode(full);
  if (json.length <= _rawLimit) return full;
  final z = base64Encode(GZipEncoder().encode(utf8.encode(json)));
  return {'v': 2, 'z': z};
}

class UnpackedHistory {
  UnpackedHistory(this.items, this.result, this.shipment);
  final List<Item> items;
  final PackResult? result; // null = 记录里没有可信的结果, 调用方应重新计算
  final ShipmentInfo? shipment;
}

/// 记录来自服务器, 可能是别的帐号写入的 —— 一律清洗后才使用
UnpackedHistory unpackHistory(Map<String, Object?> raw) {
  var data = raw;
  final z = raw['z'];
  if (z is String) {
    final bytes = GZipDecoder().decodeBytes(base64Decode(z));
    if (bytes.length > 5000000) throw const FormatException('record too large');
    data = (jsonDecode(utf8.decode(bytes)) as Map).cast<String, Object?>();
  }
  final rawItems = data['items'];
  if (rawItems is! List) throw const FormatException('bad record');
  final items = <Item>[];
  for (var i = 0; i < rawItems.length && i < 500; i++) {
    final it = rawItems[i];
    if (it is Map) items.add(Item.fromJson(it.cast<String, Object?>(), i));
  }
  // 旧记录的货物靠柜门摆放, 载入时统一成顶住柜底
  final result = PackResult.fromJson(data['result'], items: items)?.pushedToFarWall();
  final sh = data['shipment'];
  return UnpackedHistory(items, result, sh is Map ? ShipmentInfo.fromJson(sh.cast<String, Object?>()) : null);
}
