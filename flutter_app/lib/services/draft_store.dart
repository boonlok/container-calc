/// 草稿自动保存: 物品清单和货运信息存在这台电脑的浏览器里, 重新整理或不小心关掉都不会白填。
/// 每个帐号各自一份; 主动登出时清除 (共用电脑不留资料)。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';

String _key(String email) => 'draft_${email.toLowerCase()}';

Future<void> saveDraft(String email, List<Item> items, ShipmentInfo shipment) async {
  try {
    final p = await SharedPreferences.getInstance();
    final hasContent = items.any((i) => i.name.isNotEmpty || i.totalPcs > 0) || shipment.customer.isNotEmpty || shipment.remark.isNotEmpty;
    if (!hasContent) {
      await p.remove(_key(email));
      return;
    }
    await p.setString(_key(email), jsonEncode({'items': items.map((i) => i.toJson()).toList(), 'shipment': shipment.toJson(), 'at': DateTime.now().toIso8601String()}));
  } catch (_) {/* 储存不可用: 只是不自动保存 */}
}

class Draft {
  Draft(this.items, this.shipment);
  final List<Item> items;
  final ShipmentInfo shipment;
}

Future<Draft?> loadDraft(String email) async {
  try {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key(email));
    if (raw == null) return null;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final list = (j['items'] as List?) ?? const [];
    final items = <Item>[for (var i = 0; i < list.length && i < 500; i++) if (list[i] is Map) Item.fromJson((list[i] as Map).cast<String, Object?>(), i)];
    final sh = j['shipment'];
    return Draft(items, sh is Map ? ShipmentInfo.fromJson(sh.cast<String, Object?>()) : ShipmentInfo());
  } catch (_) {
    return null;
  }
}

Future<void> clearDraftFor(String email) async {
  try {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key(email));
  } catch (_) {/* 同上 */}
}
