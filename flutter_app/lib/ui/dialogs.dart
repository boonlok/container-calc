/// 对话框: 柜型新增/编辑、历史记录、保存命名
library;

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../render/notes.dart' show fmt;
import '../state/app_state.dart';
import 'theme.dart';

Future<void> showPresetDialog(BuildContext context, AppState state, Preset? existing) async {
  final name = TextEditingController(text: existing?.name ?? '');
  String n(double? v) => v == null ? '' : fmt(v);
  final l = TextEditingController(text: n(existing?.length));
  final w = TextEditingController(text: n(existing?.width));
  final h = TextEditingController(text: n(existing?.height));
  final p = TextEditingController(text: n(existing?.maxPayload));
  Widget field(String label, TextEditingController c, {bool number = true}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(controller: c, keyboardType: number ? TextInputType.number : null, decoration: InputDecoration(labelText: label)),
      );
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(existing == null ? '新增自定义柜型 Add Custom Container' : '编辑柜型 Edit Container', style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          field('柜型名称 Container Name', name, number: false),
          field('内部长度 Length (cm)', l),
          field('内部宽度 Width (cm)', w),
          field('内部高度 Height (cm)', h),
          field('最大载重 Max Payload (kg)', p),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消 Cancel')),
        FilledButton(
          onPressed: () async {
            final length = double.tryParse(l.text) ?? 0, width = double.tryParse(w.text) ?? 0, height = double.tryParse(h.text) ?? 0;
            if (name.text.trim().isEmpty || length <= 0 || width <= 0 || height <= 0) {
              state.toast('请完整填写柜型名称与尺寸 Please fill in name and dimensions', error: true);
              return;
            }
            // 共用预设只有 admin 能改; 一般使用者编辑时改为「另存为自己的柜型」
            final asCopy = existing != null && existing.isShared && !(state.user?.isAdmin ?? false);
            final ok = await state.savePreset(Preset(
              id: asCopy ? null : existing?.id, name: name.text, length: length, width: width, height: height,
              maxPayload: double.tryParse(p.text) ?? 999999, active: existing?.active ?? true,
            ));
            if (ok) {
              state.toast(asCopy ? '共用柜型不能直接修改，已另存为你自己的柜型 Shared preset copied to your own ✓' : '柜型已保存 Container saved ✓');
              if (ctx.mounted) Navigator.pop(ctx);
            }
          },
          child: const Text('保存 Save'),
        ),
      ],
    ),
  );
}

Future<void> showSaveCalculationDialog(BuildContext context, AppState state) async {
  final d = DateTime.now();
  final c = TextEditingController(text: '装载计算 ${d.year}/${d.month}/${d.day}');
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('为此次计算命名 Name this calculation', style: TextStyle(fontSize: 16)),
      content: SizedBox(width: 380, child: TextField(controller: c, autofocus: true)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消 Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('保存 Save')),
      ],
    ),
  );
  if (name == null) return;
  try {
    await state.saveHistory(name);
    state.toast('已保存 Saved ✓');
  } catch (e) {
    state.handleError(e);
  }
}

Future<void> showHistoryDialog(BuildContext context, AppState state) => showDialog<void>(context: context, builder: (ctx) => _HistoryDialog(state: state));

class _HistoryDialog extends StatefulWidget {
  const _HistoryDialog({required this.state});
  final AppState state;

  @override
  State<_HistoryDialog> createState() => _HistoryDialogState();
}

class _HistoryDialogState extends State<_HistoryDialog> {
  List<HistoryRow>? rows;
  String error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.state.backend.listHistory();
      if (mounted) setState(() => rows = r);
    } catch (e) {
      widget.state.handleError(e);
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> _open(HistoryRow r) async {
    final nav = Navigator.of(context);
    try {
      await widget.state.applyHistory(r.id);
      nav.pop();
    } on FormatException {
      widget.state.toast('记录内容无法读取 Record unreadable', error: true);
    } catch (e) {
      widget.state.handleError(e);
    }
  }

  Future<void> _delete(HistoryRow r) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text('确定删除「${r.name}」？ Delete this record?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消 Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: redErr), onPressed: () => Navigator.pop(ctx, true), child: const Text('删除 Delete')),
        ],
      ),
    );
    if (yes != true) return;
    try {
      final next = await widget.state.backend.deleteHistory(r.id);
      if (mounted) setState(() => rows = next);
    } catch (e) {
      widget.state.handleError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.state.user?.isAdmin ?? false;
    return AlertDialog(
      title: const Text('历史记录 Calculation History', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 640,
        child: rows == null
            ? Text(error.isEmpty ? '加载中 Loading...' : error)
            : rows!.isEmpty
                ? const Text('暂无记录 No saved calculations yet')
                : ListView(shrinkWrap: true, children: [
                    for (final r in rows!)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(6)),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(r.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                              Text('${r.date}${isAdmin && r.owner.isNotEmpty ? ' · ${r.owner}' : ''} · ${r.totalItems} 物品 items · ${r.totalContainers} 柜 containers · ${r.summary}',
                                  style: const TextStyle(fontSize: 11.5, color: textSecondary)),
                            ]),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(onPressed: () => _open(r), child: const Text('载入 Load')),
                          IconButton(tooltip: '删除 Delete', icon: const Icon(Icons.close, size: 16), onPressed: () => _delete(r)),
                        ]),
                      ),
                  ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭 Close'))],
    );
  }
}
