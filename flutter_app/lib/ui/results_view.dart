/// 计算结果: 总览 → 货柜卡片 → 选中货柜的 3D / 2D 视图 → 视角合集 (含混装柜特写 + 工人注意事项) → 明细
library;

import 'package:flutter/material.dart';

import '../core/loading_plan.dart';
import '../core/models.dart';
import '../render/draw.dart' as dr;
import '../render/flat_views.dart';
import '../render/iso.dart';
import '../render/notes.dart';
import '../services/download.dart';
import '../services/pdf_export.dart';
import '../services/share_link.dart';
import '../state/app_state.dart';
import 'dialogs.dart';
import 'draw_view.dart';
import 'iso_view.dart';
import 'share_dialog.dart';
import 'theme.dart';
import 'worker_screen.dart';

class ResultsView extends StatefulWidget {
  const ResultsView({super.key, required this.state});
  final AppState state;

  @override
  State<ResultsView> createState() => _ResultsViewState();
}

class _ResultsViewState extends State<ResultsView> {
  bool exporting = false;

  Future<void> _export({required bool openForPrint}) async {
    final s = widget.state;
    if (s.result == null || exporting) return;
    setState(() => exporting = true);
    s.toast('正在生成 PDF... Generating PDF, please wait...');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    try {
      final bytes = await buildPdf(
        result: s.result!, shipment: s.shipment, user: s.user, itemsFallback: s.items,
        linkFor: (c, unit, total) => workerLink(Uri.base, c, unit, total),
      );
      if (openForPrint) {
        openPdfInNewTab(bytes);
        s.toast('已在新分页打开 PDF，可从那里打印 PDF opened in a new tab — print from there');
      } else {
        downloadPdf(bytes, 'container-loading-plan-A3-${DateTime.now().millisecondsSinceEpoch}.pdf');
        s.toast('PDF 已下载 (A3) PDF downloaded ✓');
      }
    } catch (e) {
      s.toast('PDF 生成失败 PDF generation failed: $e', error: true);
    }
    if (mounted) setState(() => exporting = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final r = state.result;
    if (r == null || r.containers.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 50),
        child: Center(
          child: Text('尚无结果，请先完成物品与柜型设定后按下计算按钮\nNo results yet — fill in items and containers above, then calculate.',
              textAlign: TextAlign.center, style: TextStyle(color: textSecondary)),
        ),
      );
    }
    final types = <String, int>{};
    for (final c in r.containers) {
      types[c.containerType] = (types[c.containerType] ?? 0) + 1;
    }
    final mix = types.entries.map((e) => '${e.value}× ${e.key}').join(' + ');
    final idx = state.selectedIndex.clamp(0, r.containers.length - 1);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('④ 计算结果 Results', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: navy)),
      const SizedBox(height: 10),
      Wrap(spacing: 12, runSpacing: 12, children: [
        _stat(Icons.view_in_ar, '总集装箱数 Containers', '${r.containers.length}'),
        _stat(Icons.dashboard_outlined, '柜型组合 Container Mix', mix, small: true),
        _stat(Icons.inventory_2_outlined, '总箱数 / PCS Boxes / PCS', '${r.totalBoxes} 箱 / ${fmt(r.totalPcs)} pcs', small: true),
        _stat(Icons.speed, '平均利用率 Avg. Utilization', '${(r.avgUtilization * 100).toStringAsFixed(1)}%'),
      ]),
      const SizedBox(height: 14),
      if (r.unfulfilled.isNotEmpty)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFFFBEAE8), border: Border.all(color: redErr), borderRadius: BorderRadius.circular(6)),
          child: Text('⚠ 以下物品无法装入已选柜型 (尺寸或重量超限) Could not be placed (too large or too heavy):\n${r.unfulfilled.map((u) => '${u.name}（还剩 ${u.boxesRemaining} 箱未装 undelivered）').join(', ')}',
              style: const TextStyle(color: redErr, fontSize: 13)),
        ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [for (var i = 0; i < r.containers.length; i++) _doorCard(r.containers[i], i, i == idx)]),
      ),
      const SizedBox(height: 14),
      _workerBanner(context, r, idx),
      const SizedBox(height: 14),
      _ContainerDetail(key: ValueKey(r.containers[idx]), container: r.containers[idx], index: idx),
      const SizedBox(height: 16),
      Wrap(spacing: 10, runSpacing: 10, children: [
        OutlinedButton.icon(onPressed: exporting ? null : () => _export(openForPrint: true), icon: const Icon(Icons.print_outlined, size: 18), label: const Text('打印 Print')),
        OutlinedButton.icon(
            key: const ValueKey('exportPdf'),
            onPressed: exporting ? null : () => _export(openForPrint: false),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: Text(exporting ? '生成中 Generating...' : '导出 PDF Export as PDF')),
        OutlinedButton.icon(onPressed: () => showSaveCalculationDialog(context, state), icon: const Icon(Icons.save_outlined, size: 18), label: const Text('保存此次计算 Save Calculation')),
      ]),
    ]);
  }

  /// 最醒目的下一步: 把计划交给现场工人
  Widget _workerBanner(BuildContext context, PackResult r, int idx) {
    final c = r.containers[idx];
    final plan = LoadingPlan(c);
    void open() => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (ctx) => WorkerScreen(container: c, unit: idx + 1, totalUnits: r.containers.length, onExit: () => Navigator.of(ctx).pop())));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFF8A3D), orange]), borderRadius: BorderRadius.circular(14), boxShadow: softShadow),
      child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 16, runSpacing: 12, children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('货柜 ${idx + 1} 可以开始装了 Unit ${idx + 1} is ready to load', style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text('共 ${plan.steps.length} 列、${plan.totalBoxes} 箱，从柜底装到柜门，手机上一列一列照着做。 ${plan.steps.length} columns, ${plan.totalBoxes} boxes, far end to door.',
                style: const TextStyle(color: Colors.white, fontSize: 12.5)),
          ]),
        ),
        Wrap(spacing: 10, runSpacing: 8, children: [
          FilledButton.icon(
            key: const ValueKey('startLoading'),
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: orangeDark, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14)),
            onPressed: open,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('开始装柜 Start Loading', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          OutlinedButton.icon(
            key: const ValueKey('workerQrBtn'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white70), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
            onPressed: () => showWorkerShareDialog(context, widget.state, c, idx + 1, r.containers.length),
            icon: const Icon(Icons.qr_code_2),
            label: const Text('工人二维码 Worker QR'),
          ),
        ]),
      ]),
    );
  }

  Widget _stat(IconData icon, String label, String value, {bool small = false}) => Container(
        constraints: const BoxConstraints(minWidth: 240),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: softShadow),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: const Color(0xFFFFF1E8), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: orangeDark, size: 21),
          ),
          const SizedBox(width: 12),
          Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 11, color: textSecondary)),
            const SizedBox(height: 1),
            Text(value, style: TextStyle(fontSize: small ? 15 : 23, color: navy, fontWeight: FontWeight.w800)),
          ]),
        ]),
      );

  Widget _doorCard(ContainerResult c, int i, bool selected) => GestureDetector(
        onTap: () => widget.state.selectContainer(i),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            width: 190,
            margin: const EdgeInsets.only(right: 12, bottom: 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [navyLight, navy]),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? orange : Colors.transparent, width: 2.5),
              boxShadow: softShadow,
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('UNIT · ${(i + 1).toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 10, color: yellow)),
              Text(c.containerType.split(' ').first, style: const TextStyle(fontSize: 17, color: Colors.white, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: c.utilization.clamp(0.0, 1.0), minHeight: 5, color: yellow, backgroundColor: Colors.black26)),
              const SizedBox(height: 5),
              Text('${(c.utilization * 100).toStringAsFixed(1)}% 已使用 used', style: const TextStyle(fontSize: 10.5, color: Color(0xFFC6D1DD))),
              const SizedBox(height: 6),
              Wrap(spacing: 4, runSpacing: 4, children: [
                for (final col in {for (final a in c.allocations) a.color})
                  Container(width: 9, height: 9, decoration: BoxDecoration(color: Color(col), shape: BoxShape.circle, border: Border.all(color: Colors.white54))),
              ]),
            ]),
          ),
        ),
      );
}

class _ContainerDetail extends StatelessWidget {
  const _ContainerDetail({super.key, required this.container, required this.index});
  final ContainerResult container;
  final int index;

  Widget _cell(String title, Widget child, {Widget? legend}) => Container(
        color: Colors.white,
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: const TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          child,
          if (legend != null) ...[const SizedBox(height: 8), legend],
        ]),
      );

  Widget _legend(List<StackLayer> layers) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final l in layers) _legendRow(l.color, l.name, '${fmt(l.pcsPerBox)} PCS/箱 · H${l.horizontal}×V${l.vertical}'),
      ]);

  Widget _legendRow(int color, String name, String meta) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: Color(color), borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 7),
          Expanded(child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600))),
          Text(meta, style: const TextStyle(fontSize: 10.5, color: textSecondary)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final c = container;
    final util = (c.utilization * 100).toStringAsFixed(1);
    final wPct = c.maxPayload > 0 ? (c.totalWeightUsed / c.maxPayload * 100).toStringAsFixed(1) : '—';
    final front = buildStackedLayers(c, true), back = buildStackedLayers(c, false);
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: softShadow),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: navy,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Wrap(alignment: WrapAlignment.spaceBetween, spacing: 12, runSpacing: 6, children: [
            Text('集装箱 UNIT #${index + 1} · ${c.containerType}', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
            Text('内尺寸 DIMS: ${fmt(c.L)}×${fmt(c.W)}×${fmt(c.H)} cm   体积利用 VOL: $util%   载重 WT: ${fmt(c.totalWeightUsed)} / ${fmt(c.maxPayload)} kg ($wPct%)',
                style: const TextStyle(color: Color(0xFFC6D1DD), fontSize: 10.5)),
          ]),
        ),
        LayoutBuilder(builder: (context, box) {
          final two = box.maxWidth >= 900;
          final cells = <Widget>[
            _cell('3D 视图 · 可拖曳旋转 Drag to Rotate', IsoView(c, height: 420)),
            _cell('侧视图 RIGHT VIEW (长度 × 高度 length × height)', DrawView(drawRightView(c)),
                legend: Column(children: [for (final a in c.allocations) _legendRow(a.color, a.name, 'V${a.vertical} × 深${a.columns} 列')])),
            _cell('正面视图 FRONT VIEW (近柜门 near door)', DrawView(drawFlatView(c, front)), legend: _legend(front)),
            _cell('背面视图 BACK VIEW (柜内最深处 far end)', DrawView(drawFlatView(c, back)), legend: _legend(back)),
          ];
          if (!two) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: cells);
          return Column(children: [
            // 不能用 IntrinsicHeight: IsoView 里的 LayoutBuilder 不支援量测固有高度
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: cells[0]), Expanded(child: cells[1])]),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: cells[2]), Expanded(child: cells[3])]),
          ]);
        }),
        const Divider(height: 1, color: borderColor),
        Padding(padding: const EdgeInsets.all(16), child: _ViewPointsGallery(container: c)),
        const Divider(height: 1, color: borderColor),
        _allocTable(c),
        if (c.utilization < 0.35)
          Container(
            color: const Color(0xFFFBEAE8),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Text('⚠ 此货柜空间利用率偏低 ($util%)，建议考虑并柜或改用较小柜型 Consider consolidating or using a smaller container.', style: const TextStyle(fontSize: 12, color: redErr)),
          ),
        if (c.utilization >= 0.75)
          Container(
            color: const Color(0xFFE7F3EE),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: const Text('✓ 空间利用率良好 Good space utilization', style: TextStyle(fontSize: 12, color: greenOk)),
          ),
      ]),
    );
  }

  Widget _allocTable(ContainerResult c) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 36,
          dataRowMinHeight: 36,
          dataRowMaxHeight: 44,
          headingTextStyle: const TextStyle(fontSize: 10.5, color: textSecondary, fontWeight: FontWeight.w600),
          dataTextStyle: const TextStyle(fontSize: 13, color: navy),
          columns: const [
            DataColumn(label: Text('物品 Item')),
            DataColumn(label: Text('箱数 Boxes')),
            DataColumn(label: Text('PCS')),
            DataColumn(label: Text('排列 Layout (H × V × 深Depth)')),
            DataColumn(label: Text('占用长度 Length Used')),
            DataColumn(label: Text('离柜门 From Door')),
            DataColumn(label: Text('重量 Weight')),
          ],
          rows: [
            for (final a in c.allocations)
              DataRow(cells: [
                DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 12, height: 12, decoration: BoxDecoration(color: Color(a.color), borderRadius: BorderRadius.circular(3))),
                  const SizedBox(width: 8),
                  Text(a.name),
                ])),
                DataCell(Text('${a.boxesPlaced}')),
                DataCell(Text(fmt(a.pcsPlaced))),
                DataCell(Text('${a.horizontal} × ${a.vertical} × ${a.columns}${a.rotated ? ' (旋转90° rotated)' : ''}')),
                DataCell(Text('${fmt(a.lengthUsed)} cm')),
                DataCell(Text('${fmt(a.startLength)}–${fmt(a.endLength)} cm')),
                DataCell(Text(a.boxWeight > 0 ? '${fmt(round2(a.boxWeight * a.boxesPlaced))} kg' : '—')),
              ]),
          ],
        ),
      );
}

/// 视角合集: 整柜 6 个固定角度; 混装柜再加「每个物品区块 3 个特写角度 + 工人注意事项」
class _ViewPointsGallery extends StatelessWidget {
  const _ViewPointsGallery({required this.container});
  final ContainerResult container;

  Widget _thumb(dr.DrawList list, String label, {int? borderColor2}) => SizedBox(
        width: 260,
        child: Container(
          decoration: BoxDecoration(border: Border.all(color: borderColor2 == null ? borderColor : Color(borderColor2), width: borderColor2 == null ? 1 : 1.5), borderRadius: BorderRadius.circular(4), color: const Color(0xFFFAFBFC)),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            DrawView(list),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: Text(label, style: const TextStyle(fontSize: 10, color: textSecondary))),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = container;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('📷 多角度视角合集 View Points Gallery', style: TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      const Text('整柜总览 Overview Angles', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: textSecondary)),
      const SizedBox(height: 8),
      Wrap(spacing: 10, runSpacing: 10, children: [
        for (final vp in overviewViewpoints(c)) _thumb(renderIso(c, IsoCamera(vp.dir), w: 420, h: 300), vp.label),
      ]),
      if (c.allocations.length > 1) ...[
        const SizedBox(height: 16),
        const Text('各物品区块特写 Per-Item Close-Ups (混装柜 · 装柜注意)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: textSecondary)),
        const SizedBox(height: 8),
        for (var i = 0; i < c.allocations.length; i++) _section(c, i),
      ],
    ]);
  }

  Widget _section(ContainerResult c, int i) {
    final info = describeAllocation(c.allocations[i], c, i);
    final vps = closeupViewpoints(c, i);
    return Container(
      key: ValueKey('section${i + 1}'),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(border: Border(left: BorderSide(color: Color(info.color), width: 4))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 12, runSpacing: 4, alignment: WrapAlignment.spaceBetween, children: [
          Text('Section ${info.section} · ${info.name}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
          Text('${fmt(info.pcsPerBox)} PCS/箱 · ${info.boxes} 箱 · ${fmt(info.pcs)} PCS · H${info.horizontal}×V${info.vertical}×深${info.columns}${info.weightKg > 0 ? ' · ${fmt(info.weightKg)} kg' : ''}',
              style: const TextStyle(fontSize: 11.5, color: textSecondary)),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (var k = 0; k < vps.length; k++) _thumb(renderIso(c, IsoCamera(vps[k].dir), w: 420, h: 300, focus: i), closeupAngleLabels[k], borderColor2: info.color),
        ]),
        const SizedBox(height: 8),
        for (final n in info.notes)
          Padding(padding: const EdgeInsets.only(left: 4, bottom: 2), child: Text('• $n', style: const TextStyle(fontSize: 12, color: textSecondary, height: 1.5))),
      ]),
    );
  }
}
