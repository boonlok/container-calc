/// 常用物品库: 常出货的产品 (名称 + 箱规 + 每箱数量 + 重量) 存在这台电脑, 下次点选就能加入清单, 不用重打。
/// 每个帐号各自一份; 这是产品资料 (不含客户), 登出时保留。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';

String _key(String email) => 'library_${email.toLowerCase()}';
const maxLibraryItems = 500;

Future<List<Item>> loadLibrary(String email) async {
  try {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key(email));
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return [for (var i = 0; i < list.length && i < maxLibraryItems; i++) if (list[i] is Map) Item.fromJson((list[i] as Map).cast<String, Object?>(), i)];
  } catch (_) {
    return [];
  }
}

Future<void> _save(String email, List<Item> items) async {
  try {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key(email), jsonEncode([for (final i in items.take(maxLibraryItems)) i.toJson()]));
  } catch (_) {/* 储存不可用 */}
}

bool _usable(Item i) => i.name.trim().isNotEmpty && i.pcsPerBox > 0 && i.boxL > 0 && i.boxW > 0 && i.boxH > 0;

/// 把物品存进常用库 (同名的会更新成新的箱规); 回传 (新增数, 更新数)
Future<(int, int)> addToLibrary(String email, List<Item> items) async {
  final lib = await loadLibrary(email);
  var added = 0, updated = 0;
  for (final it in items.where(_usable)) {
    final entry = it.copy()..totalPcs = 0; // 数量每次不同, 不存
    final i = lib.indexWhere((x) => x.name.trim().toLowerCase() == it.name.trim().toLowerCase());
    if (i >= 0) {
      entry.id = lib[i].id;
      lib[i] = entry;
      updated++;
    } else {
      entry.id = lib.fold(0, (m, x) => x.id > m ? x.id : m) + 1;
      lib.add(entry);
      added++;
    }
  }
  lib.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  await _save(email, lib);
  return (added, updated);
}

Future<List<Item>> removeFromLibrary(String email, int id) async {
  final lib = (await loadLibrary(email))..removeWhere((x) => x.id == id);
  await _save(email, lib);
  return lib;
}
