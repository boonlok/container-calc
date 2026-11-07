/// 装柜进度存在手机/电脑本机: 中途关掉页面、断网、换班, 回来都能接着装
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';

class LoadProgress {
  LoadProgress({this.done = 0, Set<int>? checklist}) : checklist = checklist ?? {};
  int done;
  final Set<int> checklist;
}

/// 用计划内容算出的键: 同一个计划共用进度, 计划一变就是新的进度
String progressKey(ContainerResult c) {
  final s = jsonEncode(c.toJson());
  var h = 0x811c9dc5;
  for (final u in s.codeUnits) {
    h = ((h ^ u) * 0x01000193) & 0xFFFFFFFF;
  }
  return 'load_progress_${h.toRadixString(16)}';
}

Future<LoadProgress> loadProgress(String key, int maxSteps) async {
  try {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(key);
    if (raw == null) return LoadProgress();
    final j = jsonDecode(raw);
    final done = (j['done'] as num?)?.toInt() ?? 0;
    final list = (j['check'] as List?)?.whereType<num>().map((e) => e.toInt()).toSet() ?? <int>{};
    return LoadProgress(done: done.clamp(0, maxSteps), checklist: list);
  } catch (_) {
    return LoadProgress(); // 储存不可用 (无痕模式等): 只是不保留进度
  }
}

Future<void> saveProgress(String key, LoadProgress v) async {
  try {
    final p = await SharedPreferences.getInstance();
    await p.setString(key, jsonEncode({'done': v.done, 'check': v.checklist.toList()}));
  } catch (_) {/* 同上 */}
}

Future<void> clearProgress(String key) async {
  try {
    final p = await SharedPreferences.getInstance();
    await p.remove(key);
  } catch (_) {/* 同上 */}
}
