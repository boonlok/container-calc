/// 工人装柜模式 Worker loading mode
///
/// 手机优先: 一次只看一件事 —— 现在这一列放什么、放几箱、怎么放。
/// 大按钮单手可按, 进度自动保存在本机, 屏幕不熄灭。顺序是柜底 → 柜门。
library;

import 'package:flutter/material.dart';

import '../core/loading_plan.dart';
import '../core/models.dart';
import '../render/flat_views.dart';
import '../render/iso.dart';
import '../render/notes.dart';
import '../services/download.dart';
import '../services/progress_store.dart';
import 'draw_view.dart';
import 'iso_view.dart';
import 'theme.dart';

const sealChecklist = [
  '空隙已用气袋/木条填紧 Gaps filled with airbags or timber',
  '货物高度没有超过柜门框 Cargo is below the door frame',
  '靠门的货物已加固定带 Door-side cargo is strapped',
  '已拍照留底 Photos taken',
  '柜门已关好并上封条 Doors closed and sealed',
];

class WorkerScreen extends StatefulWidget {
  const WorkerScreen({super.key, required this.container, required this.unit, required this.totalUnits, this.onExit});
  final ContainerResult container;
  final int unit, totalUnits;
  final VoidCallback? onExit; // null = 从工人链接打开, 没有上一页

  @override
  State<WorkerScreen> createState() => _WorkerScreenState();
}

class _WorkerScreenState extends State<WorkerScreen> {
  late final LoadingPlan plan = LoadingPlan(widget.container);
  late final String _key = progressKey(widget.container);
  LoadProgress progress = LoadProgress();
  bool ready = false;
  bool show3d = false;

  @override
  void initState() {
    super.initState();
    keepScreenOn();
    loadProgress(_key, plan.steps.length).then((p) {
      if (!mounted) return;
      setState(() {
        progress = p;
        ready = true;
      });
    });
  }

  void _setDone(int d) {
    setState(() => progress.done = d.clamp(0, plan.steps.length));
    saveProgress(_key, progress);
  }

  void _toggleCheck(int i) {
    setState(() => progress.checklist.contains(i) ? progress.checklist.remove(i) : progress.checklist.add(i));
    saveProgress(_key, progress);
  }

  Future<void> _reset() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('从头开始？ Start over?', style: TextStyle(fontSize: 17)),
        content: const Text('这个货柜的装柜进度会清零。 Progress for this container will be cleared.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消 Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: redErr), onPressed: () => Navigator.pop(ctx, true), child: const Text('清零 Clear')),
        ],
      ),
    );
    if (yes != true) return;
    await clearProgress(_key);
    setState(() {
      progress = LoadProgress();
      show3d = false;
    });
  }

  void _openOverview() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _OverviewSheet(plan: plan, done: progress.done, onJump: (i) {
        Navigator.pop(ctx);
        _setDone(i);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) return const Scaffold(backgroundColor: navy, body: Center(child: CircularProgressIndicator(color: orange)));
    final finished = progress.done >= plan.steps.length;
    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        child: Column(children: [
          _header(),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: finished ? _finished() : _stepBody(plan.steps[progress.done]),
              ),
            ),
          ),
          if (!finished) _bottomBar(plan.steps[progress.done]),
        ]),
      ),
    );
  }

  Widget _header() {
    final boxes = plan.boxesDone(progress.done), total = plan.totalBoxes;
    final pct = total == 0 ? 0.0 : boxes / total;
    return Container(
      decoration: const BoxDecoration(gradient: LinearGradient(colors: [navy, navyLight])),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 12),
      child: Column(children: [
        Row(children: [
          if (widget.onExit != null)
            IconButton(key: const ValueKey('workerBack'), tooltip: '返回 Back', onPressed: widget.onExit, icon: const Icon(Icons.arrow_back, color: Colors.white))
          else
            const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('货柜 UNIT ${widget.unit}/${widget.totalUnits}', style: const TextStyle(color: yellow, fontSize: 11.5, fontWeight: FontWeight.w600)),
              Text(widget.container.containerType, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            ]),
          ),
          IconButton(key: const ValueKey('workerOverview'), tooltip: '全部区块 All sections', onPressed: _openOverview, icon: const Icon(Icons.format_list_numbered, color: Colors.white)),
          IconButton(tooltip: '从头开始 Start over', onPressed: _reset, icon: const Icon(Icons.restart_alt, color: Colors.white70)),
        ]),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: pct, minHeight: 10, color: orange, backgroundColor: Colors.white24),
            ),
            const SizedBox(height: 5),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('已装 Loaded  $boxes / $total 箱', style: const TextStyle(color: Colors.white, fontSize: 12.5)),
              Text('${(pct * 100).toStringAsFixed(0)}%', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _stepBody(LoadStep s) {
    final a = widget.container.allocations[s.allocIndex];
    final info = describeAllocation(a, widget.container, s.allocIndex);
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 820;
      final main = _instructionCard(s, a);
      final diagram = _diagramCard(s, a);
      final howTo = _howToCard(a, info, s);
      return SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(children: [main, const SizedBox(height: 12), howTo])),
                const SizedBox(width: 12),
                Expanded(child: diagram),
              ])
            : Column(children: [main, const SizedBox(height: 12), diagram, const SizedBox(height: 12), howTo]),
      );
    });
  }

  Widget _instructionCard(LoadStep s, Allocation a) {
    final info = describeAllocation(a, widget.container, s.allocIndex);
    final color = Color(a.color);
    final onColor = color.computeLuminance() > 0.55 ? navy : Colors.white;
    final layout = LoadingPlan.layoutOf(a, s.boxes);
    final full = s.boxes == a.horizontal * a.vertical;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: softShadow),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: color,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('第 ${s.sectionNo} 种货 / 共 ${plan.sectionCount} 种  Item ${s.sectionNo} of ${plan.sectionCount}', style: TextStyle(color: onColor, fontSize: 12)),
            const SizedBox(height: 2),
            Text(a.name, style: TextStyle(color: onColor, fontSize: 21, fontWeight: FontWeight.w800, height: 1.25)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('第 ${s.columnNo} 列', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: navy, height: 1.1)),
              const SizedBox(width: 8),
              Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('/ 共 ${s.columnsInSection} 列  Column', style: const TextStyle(fontSize: 13, color: textSecondary))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              _bigStat('${a.horizontal}', '横排 Across'),
              _sep('×'),
              _bigStat('${a.vertical}', '层 Layers'),
              _sep('='),
              _bigStat('${s.boxes}', '箱 Boxes', highlight: true),
            ]),
            if (s.index == 0) ...[
              const SizedBox(height: 12),
              _callout(Icons.login, const Color(0xFFE8F1FB), const Color(0xFF1B4F8A), '从货柜最里面开始，第一列顶住柜底。\nStart at the far end, first column against the far wall.'),
            ],
            if (s.isSectionStart && s.index > 0) ...[
              const SizedBox(height: 12),
              _callout(Icons.swap_vert, const Color(0xFFE8F1FB), const Color(0xFF1B4F8A), '换货了：请核对物品名称和箱规 ${info.boxDims} cm。\nNew item: check the name and box size.'),
            ],
            if (!full) ...[
              const SizedBox(height: 12),
              _callout(Icons.warning_amber_rounded, const Color(0xFFFFF3E0), const Color(0xFF9A4A00),
                  '这一列不满：只放 ${s.boxes} 箱。从最下层放起，铺满 ${layout.fullLayers} 层${layout.topLayerBoxes > 0 ? '，最上面再放 ${layout.topLayerBoxes} 箱' : ''}，靠左边排。\nPartial column: ${s.boxes} boxes, from the bottom, against the left side.'),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _bigStat(String v, String label, {bool highlight = false}) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(color: highlight ? const Color(0xFFFFF1E8) : const Color(0xFFF3F5F8), borderRadius: BorderRadius.circular(10)),
          child: Column(children: [
            Text(v, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: highlight ? const Color(0xFFC24F14) : navy, height: 1.1)),
            Text(label, style: const TextStyle(fontSize: 11, color: textSecondary)),
          ]),
        ),
      );

  Widget _sep(String t) => Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text(t, style: const TextStyle(fontSize: 20, color: textSecondary)));

  Widget _callout(IconData icon, Color bg, Color fg, String text) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: fg),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: fg, height: 1.45))),
        ]),
      );

  Widget _diagramCard(LoadStep s, Allocation a) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: softShadow),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: SegmentedButton<bool>(
              key: const ValueKey('viewToggle'),
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: false, label: Text('这一列怎么放 This column', style: TextStyle(fontSize: 12))),
                ButtonSegment(value: true, label: Text('在柜里的位置 In container', style: TextStyle(fontSize: 12))),
              ],
              selected: {show3d},
              onSelectionChanged: (v) => setState(() => show3d = v.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: show3d
                ? IsoView(widget.container, height: 300, load: LoadView(s.allocIndex, s.column), xShift: plan.doorGap, camera: doorCamera(widget.container), labels: false, hint: false)
                : DrawView(drawColumnFace(widget.container, a, s.boxes)),
          ),
        ]),
      );

  Widget _howToCard(Allocation a, SectionInfo info, LoadStep s) {
    final across = a.rotated ? a.boxL : a.boxW, deep = a.rotated ? a.boxW : a.boxL;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: softShadow),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('怎么摆 How to place', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: navy)),
        const SizedBox(height: 8),
        _fact(Icons.swap_horiz, '左右方向 Across', '${fmt(across)} cm'),
        _fact(Icons.vertical_align_center, '往里方向 Depth', '${fmt(deep)} cm'),
        _fact(Icons.height, '高度 Height', '${fmt(a.boxH)} cm'),
        if (a.rotated) ...[
          const SizedBox(height: 4),
          _callout(Icons.rotate_90_degrees_cw_outlined, const Color(0xFFE8F1FB), const Color(0xFF1B4F8A), '箱子要横放旋转 90°，长边朝左右。 Rotate 90°, long side across.'),
        ],
        const Divider(height: 22, color: borderColor),
        _fact(Icons.place_outlined, '离柜底 From far wall', '${fmt(plan.fromFarWall(s))}–${fmt(plan.fromFarWall(s) + a.depthUnit)} cm'),
        _fact(Icons.inventory_2_outlined, '每箱 Per box', '${fmt(info.pcsPerBox)} PCS${a.boxWeight > 0 ? ' · ${fmt(a.boxWeight)} kg' : ''}'),
        const SizedBox(height: 6),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: Material(type: MaterialType.transparency, child: ExpansionTile(
            key: ValueKey('notes${s.allocIndex}'),
            initiallyExpanded: s.isSectionStart,
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: Text('本区块注意事项 Notes', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: navy)),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 工人从柜底顶紧开始装, 空隙留在柜门这边: 「柜底尚余空间」这条不适用
              for (final n in info.notes.where((n) => !n.contains('Remaining length at back') && !n.startsWith('起点离柜门')))
                Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• $n', style: const TextStyle(fontSize: 13, color: Color(0xFF334155), height: 1.45))),
            ],
          )),
        ),
      ]),
    );
  }

  Widget _fact(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Icon(icon, size: 18, color: textSecondary),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: textSecondary))),
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: navy)),
        ]),
      );

  Widget _bottomBar(LoadStep s) => Container(
        decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(0, -2))]),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Row(children: [
              SizedBox(
                height: 64,
                width: 72,
                child: OutlinedButton(
                  key: const ValueKey('stepBack'),
                  style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: progress.done > 0 ? () => _setDone(progress.done - 1) : null,
                  child: const Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.undo, size: 20), Text('上一步', style: TextStyle(fontSize: 11)), Text('Undo', style: TextStyle(fontSize: 10))]),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 64,
                  child: FilledButton.icon(
                    key: const ValueKey('stepDone'),
                    style: FilledButton.styleFrom(backgroundColor: greenOk, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    onPressed: () => _setDone(progress.done + 1),
                    icon: const Icon(Icons.check_circle_outline, size: 26),
                    label: Text('这 ${s.boxes} 箱装好了  Done', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );

  Widget _finished() {
    final all = progress.checklist.length >= sealChecklist.length;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(children: [
            const SizedBox(height: 6),
            const Icon(Icons.check_circle, color: greenOk, size: 64),
            const SizedBox(height: 6),
            const Text('全部装完了！', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: navy)),
            Text('All ${plan.totalBoxes} boxes loaded', style: const TextStyle(fontSize: 14, color: textSecondary)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: softShadow),
              child: Material(type: MaterialType.transparency, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(8, 8, 8, 2),
                  child: Text('封柜前检查 Before sealing', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: navy)),
                ),
                for (var i = 0; i < sealChecklist.length; i++)
                  CheckboxListTile(
                    key: ValueKey('seal$i'),
                    value: progress.checklist.contains(i),
                    activeColor: greenOk,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    title: Text(sealChecklist[i], style: const TextStyle(fontSize: 14)),
                    onChanged: (_) => _toggleCheck(i),
                  ),
              ])),
            ),
            const SizedBox(height: 12),
            if (plan.doorGap > 1) ...[
              _callout(Icons.straighten, const Color(0xFFFFF3E0), const Color(0xFF9A4A00), '货物顶住柜底后，靠柜门这边约剩 ${fmt(plan.doorGap)} cm，请用填充物顶紧。\nAbout${fmt(plan.doorGap)} cm is left at the door, fill it so cargo cannot slide.'),
              const SizedBox(height: 12),
            ],
            if (all) _callout(Icons.verified_outlined, const Color(0xFFE7F3EE), greenOk, '检查完成，这个货柜可以封柜出运。 Checks complete, ready to ship.'),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: () => _setDone(plan.steps.length - 1), icon: const Icon(Icons.undo), label: const Text('回到最后一列 Back to last column')),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(height: 260, child: LayoutBuilder(builder: (context, box) => CustomPaint(size: Size(box.maxWidth, 260), painter: DrawListPainter(renderIso(widget.container, doorCamera(widget.container), w: box.maxWidth, h: 260, labels: false, xShift: plan.doorGap))))),
            ),
          ]),
        ),
      ),
    );
  }
}

class _OverviewSheet extends StatelessWidget {
  const _OverviewSheet({required this.plan, required this.done, required this.onJump});
  final LoadingPlan plan;
  final int done;
  final void Function(int step) onJump;

  @override
  Widget build(BuildContext context) {
    final c = plan.container;
    // 依装柜顺序 (柜底先装) 列出区块
    final order = [for (var i = c.allocations.length - 1; i >= 0; i--) i];
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
          const Text('装柜顺序 Loading order', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: navy)),
          const Text('从柜底装到柜门，点一下可跳到该货 From far end to door, tap to jump', style: TextStyle(fontSize: 12, color: textSecondary)),
          const SizedBox(height: 10),
          for (var n = 0; n < order.length; n++) _row(context, n, order[n]),
        ]),
      ),
    );
  }

  Widget _row(BuildContext context, int n, int allocIndex) {
    final a = plan.container.allocations[allocIndex];
    final (got, total) = plan.sectionProgress(allocIndex, done);
    final first = plan.firstStepOf(allocIndex);
    final isDone = got >= total;
    final current = done < plan.steps.length && plan.steps[done].allocIndex == allocIndex;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: current ? const Color(0xFFFFF7F1) : Colors.white,
        border: Border.all(color: current ? orange : borderColor, width: current ? 1.5 : 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(type: MaterialType.transparency, child: ListTile(
        onTap: () => onJump(first),
        leading: CircleAvatar(
          backgroundColor: Color(a.color),
          child: isDone ? const Icon(Icons.check, color: Colors.white) : Text('${n + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ),
        title: Text(a.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        subtitle: Text('$got / $total 箱 · ${a.columns} 列 · ${a.horizontal}×${a.vertical} · ${fmt(a.lengthUsed)} cm 长', style: const TextStyle(fontSize: 12)),
      )),
    );
  }
}
