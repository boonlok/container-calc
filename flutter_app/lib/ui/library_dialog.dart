/// 常用物品库: 点选加入清单 / 把目前清单存进来
library;

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../render/notes.dart' show fmt;
import '../services/library_store.dart';
import '../state/app_state.dart';
import 'theme.dart';

Future<void> showLibraryDialog(BuildContext context, AppState state) => showDialog<void>(context: context, builder: (_) => _LibraryDialog(state: state));

class _LibraryDialog extends StatefulWidget {
  const _LibraryDialog({required this.state});
  final AppState state;

  @override
  State<_LibraryDialog> createState() => _LibraryDialogState();
}

class _LibraryDialogState extends State<_LibraryDialog> {
  List<Item>? lib;
  final picked = <int>{};
  String query = '';

  String get _email => widget.state.user!.email;

  @override
  void initState() {
    super.initState();
    loadLibrary(_email).then((l) {
      if (mounted) setState(() => lib = l);
    });
  }

  Future<void> _saveCurrent() async {
    final (added, updated) = await addToLibrary(_email, widget.state.items);
    final l = await loadLibrary(_email);
    if (!mounted) return;
    setState(() => lib = l);
    widget.state.toast(added + updated == 0
        ? '目前清单没有完整的物品可存 (需要名称、每箱数量和箱规) Nothing complete to save'
        : '已存入常用物品：新增 $added、更新 $updated  Saved: $added new, $updated updated ✓');
  }

  @override
  Widget build(BuildContext context) {
    final all = lib;
    final q = query.trim().toLowerCase();
    final shown = all == null ? <Item>[] : all.where((i) => q.isEmpty || i.name.toLowerCase().contains(q)).toList();
    return AlertDialog(
      title: const Text('常用物品 Item Library', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 600,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('常出货的产品存在这里，下次勾选就能加入清单，只要再填数量。存在这台电脑的浏览器里。\nSave products you ship often, then tick to add them and just fill the quantity. Stored in this browser.',
              style: TextStyle(fontSize: 12, color: textSecondary, height: 1.5)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                key: const ValueKey('librarySearch'),
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search, size: 18), hintText: '搜寻名称 Search'),
                onChanged: (v) => setState(() => query = v),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(key: const ValueKey('librarySaveCurrent'), onPressed: _saveCurrent, icon: const Icon(Icons.bookmark_add_outlined, size: 16), label: const Text('存入目前清单 Save Current')),
          ]),
          const SizedBox(height: 10),
          if (all == null)
            const Padding(padding: EdgeInsets.all(16), child: Text('载入中 Loading...'))
          else if (all.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text('还没有常用物品。先在清单里填好物品，再按「存入目前清单」。\nNo items yet. Fill in your list, then press "Save Current".', style: TextStyle(color: textSecondary, height: 1.5)),
            )
          else
            Container(
              constraints: const BoxConstraints(maxHeight: 340),
              decoration: BoxDecoration(border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(8)),
              child: Material(
                type: MaterialType.transparency,
                child: ListView(shrinkWrap: true, children: [
                  for (final it in shown)
                    CheckboxListTile(
                      key: ValueKey('lib${it.id}'),
                      dense: true,
                      value: picked.contains(it.id),
                      activeColor: orange,
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (v) => setState(() => v == true ? picked.add(it.id) : picked.remove(it.id)),
                      title: Row(children: [
                        Container(width: 10, height: 10, margin: const EdgeInsets.only(right: 8), decoration: BoxDecoration(color: Color(it.color), borderRadius: BorderRadius.circular(3))),
                        Expanded(child: Text(it.name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
                      ]),
                      subtitle: Text('${fmt(it.pcsPerBox)} PCS/箱 · ${fmt(it.boxL)}×${fmt(it.boxW)}×${fmt(it.boxH)} cm${it.boxWeight > 0 ? ' · ${fmt(it.boxWeight)} kg' : ''}', style: const TextStyle(fontSize: 12)),
                      secondary: IconButton(
                        tooltip: '从常用移除 Remove',
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () async {
                          final l = await removeFromLibrary(_email, it.id);
                          if (mounted) setState(() { lib = l; picked.remove(it.id); });
                        },
                      ),
                    ),
                ]),
              ),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭 Close')),
        FilledButton(
          key: const ValueKey('libraryAdd'),
          onPressed: picked.isEmpty
              ? null
              : () {
                  final chosen = [for (final i in all!) if (picked.contains(i.id)) i];
                  // 清单里只有空白列时直接取代, 否则加在后面
                  final onlyBlank = widget.state.items.every((i) => i.name.isEmpty && i.totalPcs == 0);
                  final n = widget.state.importItems(chosen, replace: onlyBlank);
                  widget.state.toast('已加入 $n 样，请填写总数量 Added $n items, now fill in the quantities');
                  Navigator.pop(context);
                },
          child: Text(picked.isEmpty ? '加入清单 Add' : '加入 ${picked.length} 样 Add ${picked.length}'),
        ),
      ],
    );
  }
}
