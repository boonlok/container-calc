/// 主画面: 货运信息 → 物品清单 → 柜型 → 计算 → 结果
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../render/notes.dart' show fmt;
import '../state/app_state.dart';
import 'admin_screen.dart';
import 'dialogs.dart';
import 'import_dialog.dart';
import 'library_dialog.dart';
import 'profile_screen.dart';
import 'results_view.dart';
import 'theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          _TopBar(state: state),
          Expanded(
            child: SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 60),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (state.backend.isDemo)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: const Color(0xFFFFF7E0), borderRadius: BorderRadius.circular(5)),
                          child: const Text('演示模式：尚未设置 Supabase，资料重新整理后会消失 Demo mode: not connected to Supabase, data is lost on refresh',
                              style: TextStyle(fontSize: 12.5, color: Color(0xFF8A6D00))),
                        ),
                      // formGeneration 变化时 (载入历史/登出) 重建表单, 丢掉旧输入框内容
                      KeyedSubtree(key: ValueKey('ship${state.formGeneration}'), child: _ShipmentCard(state: state)),
                      KeyedSubtree(key: ValueKey('items${state.formGeneration}'), child: _ItemsCard(state: state)),
                      _PresetsCard(state: state),
                      Wrap(spacing: 10, runSpacing: 10, children: [
                        FilledButton.icon(
                          key: const ValueKey('calcBtn'),
                          style: FilledButton.styleFrom(backgroundColor: orange, padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 19)),
                          icon: const Icon(Icons.bolt, size: 22),
                          label: const Text('计算装载方案 Calculate Loading Plan', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                          onPressed: () {
                            final err = state.calculate();
                            if (err != null) {
                              state.toast(err, error: true);
                            } else if (state.result!.unfulfilled.isNotEmpty) {
                              state.toast('部分物品无法装入已选柜型，请查看结果页警示 Some items could not be placed, see warning in results', error: true);
                            } else {
                              state.toast('计算完成 Calculation complete ✓');
                            }
                          },
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 19)),
                          icon: const Icon(Icons.folder_open_outlined, size: 18),
                          label: const Text('历史记录 History'),
                          onPressed: () => showHistoryDialog(context, state),
                        ),
                      ]),
                      const SizedBox(height: 20),
                      ResultsView(state: state),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ]),
      );
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final u = state.user!;
    Widget btn(String t, VoidCallback onTap) => TextButton(
          style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.white.withValues(alpha: 0.08), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), minimumSize: Size.zero),
          onPressed: onTap,
          child: Text(t, style: const TextStyle(fontSize: 12)),
        );
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [navy, navyLight]),
        border: Border(bottom: BorderSide(color: orange, width: 3)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 16, runSpacing: 8, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: orange, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.view_in_ar, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 10),
          const Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('集装箱装载计算器', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700, height: 1.2)),
            Text('CONTAINER LOADING CALCULATOR', style: TextStyle(color: Color(0xFF9FB0C3), fontSize: 10.5, letterSpacing: 0.4)),
          ]),
        ]),
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(u.email, style: const TextStyle(color: Color(0xFF9FB0C3), fontSize: 11)),
          btn('我的资料 Profile', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(state: state)))),
          if (u.isAdmin) btn('管理后台 Admin', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminScreen(state: state)))),
          btn('登出 Logout', () => state.logout(message: '已登出 Logged out', clearDraft: true)),
        ]),
      ]),
    );
  }
}

// ---------- 货运信息 ----------
class _ShipmentCard extends StatefulWidget {
  const _ShipmentCard({required this.state});
  final AppState state;

  @override
  State<_ShipmentCard> createState() => _ShipmentCardState();
}

class _ShipmentCardState extends State<_ShipmentCard> {
  // 手机上栏位不能比画面宽
  double _w(double want) => want.clamp(0, MediaQuery.of(context).size.width - 82).toDouble();

  Widget _text(String label, String initial, void Function(String) onChanged, {double width = 240}) => SizedBox(
        width: _w(width),
        child: TextFormField(initialValue: initial, onChanged: onChanged, decoration: InputDecoration(labelText: label)),
      );

  Widget _date(String label, String value, void Function(String) onSet) => SizedBox(
        width: _w(180),
        child: InkWell(
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(context: context, initialDate: DateTime.tryParse(value) ?? now, firstDate: DateTime(now.year - 5), lastDate: DateTime(now.year + 5));
            if (picked != null) {
              String p(int n) => n.toString().padLeft(2, '0');
              setState(() => onSet('${picked.year}-${p(picked.month)}-${p(picked.day)}'));
            }
          },
          child: InputDecorator(decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.event, size: 16)), child: Text(value.isEmpty ? ' ' : value)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final s = state.shipment;
    return SectionCard(
      icon: Icons.local_shipping_outlined,
      title: '货运信息 Shipment Info',
      hint: '选填，会显示在导出的 PDF 表头 — Optional, shown in the PDF header',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 12, runSpacing: 12, children: [
          _text('客户 Customer', s.customer, (v) => s.customer = v),
          _date('预计出发日 ETD', s.etd, (v) => s.etd = v),
          _date('预计到达日 ETA', s.eta, (v) => s.eta = v),
          _text('船公司 Shipping Line', s.shippingLine, (v) => s.shippingLine = v),
          _text('备注 Remark', s.remark, (v) => s.remark = v, width: 400),
          _text('绘图 Drawn', s.drawn, (v) => s.drawn = v, width: 180),
          _text('检查 Checked', s.checked, (v) => s.checked = v, width: 180),
          _text('确认 Confirmed', s.confirmed, (v) => s.confirmed = v, width: 180),
        ]),
        const SizedBox(height: 6),
        // 配件平常不用动, 收起来让主画面短一点
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: Text('配件清单 Accessories (${s.accessories.length})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: navy)),
            children: [
              for (final a in s.accessories)
                Padding(
                  key: ObjectKey(a),
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    Expanded(child: TextFormField(initialValue: a.name, onChanged: (v) => a.name = v, decoration: const InputDecoration(hintText: '配件名称 Accessory Name'))),
                    const SizedBox(width: 8),
                    SizedBox(width: 100, child: TextFormField(initialValue: a.qty, onChanged: (v) => a.qty = v, decoration: const InputDecoration(hintText: '数量 Qty'))),
                    IconButton(tooltip: '删除 Remove', icon: const Icon(Icons.close, size: 16), onPressed: () => state.removeAccessory(a)),
                  ]),
                ),
              Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: state.addAccessory, icon: const Icon(Icons.add, size: 16), label: const Text('添加配件 Add Accessory'))),
            ],
          ),
        ),
      ]),
    );
  }
}

// ---------- 物品清单 ----------
const _colW = 92.0;

class _ItemsCard extends StatelessWidget {
  const _ItemsCard({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    Widget head(String t, {double? w}) => SizedBox(width: w, child: Text(t, style: const TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.w600)));
    return SectionCard(
      step: 1,
      title: '物品清单 Item List',
      hint: '输入总数量与每箱数量，系统自动换算箱数 — Enter total PCS & PCS/box, boxes are auto-calculated',
      trailing: Wrap(spacing: 4, children: [
        TextButton.icon(key: const ValueKey('openLibrary'), onPressed: () => showLibraryDialog(context, state), icon: const Icon(Icons.bookmarks_outlined, size: 16, color: orangeDark), label: const Text('常用物品 Library', style: TextStyle(color: orangeDark, fontSize: 12))),
        TextButton.icon(key: const ValueKey('importList'), onPressed: () => showImportDialog(context, state), icon: const Icon(Icons.content_paste, size: 16, color: orangeDark), label: const Text('从 Excel 汇入 Import', style: TextStyle(color: orangeDark, fontSize: 12))),
        TextButton.icon(key: const ValueKey('loadSample'), onPressed: state.loadSample, icon: const Icon(Icons.auto_awesome, size: 16, color: orangeDark), label: const Text('试用示例 Try Sample', style: TextStyle(color: orangeDark, fontSize: 12))),
      ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LayoutBuilder(builder: (context, box) {
          // 手机: 每样物品一张卡片, 不用左右滑表格
          if (box.maxWidth < 720) {
            return Column(children: [for (final it in state.items) _ItemRow(key: ValueKey('c${it.id}'), item: it, state: state, compact: true)]);
          }
          final minW = box.maxWidth < 960 ? 960.0 : box.maxWidth;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: minW,
              child: Column(children: [
                Row(children: [
                  const SizedBox(width: 40),
                  Expanded(child: head('物品名称 Item Name')),
                  head(' 总数量 PCS', w: _colW),
                  head(' 每箱 PCS/Box', w: _colW),
                  head(' 长 L (cm)', w: _colW),
                  head(' 宽 W (cm)', w: _colW),
                  head(' 高 H (cm)', w: _colW),
                  head(' 每箱重 KG/Box', w: _colW),
                  head(' 箱数 Boxes', w: 70),
                  const SizedBox(width: 40),
                ]),
                const SizedBox(height: 6),
                for (final it in state.items) _ItemRow(key: ValueKey(it.id), item: it, state: state),
              ]),
            ),
          );
        }),
        const SizedBox(height: 6),
        TextButton.icon(key: const ValueKey('addItem'), onPressed: state.addItem, icon: const Icon(Icons.add, size: 16), label: const Text('添加物品 Add Item')),
      ]),
    );
  }
}

class _ItemRow extends StatefulWidget {
  const _ItemRow({super.key, required this.item, required this.state, this.compact = false});
  final Item item;
  final AppState state;
  final bool compact;

  @override
  State<_ItemRow> createState() => _ItemRowState();
}

class _ItemRowState extends State<_ItemRow> {
  Widget _num(double value, void Function(double) set, String hint) => SizedBox(
        width: _colW,
        child: Padding(
          padding: const EdgeInsets.only(right: 6),
          child: TextFormField(
            initialValue: value == 0 ? '' : fmt(value),
            textAlign: TextAlign.right,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: InputDecoration(hintText: hint),
            onChanged: (v) => setState(() => set(double.tryParse(v) ?? 0)),
          ),
        ),
      );

  Widget _field(String label, double value, void Function(double) set) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: TextFormField(
            initialValue: value == 0 ? '' : fmt(value),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: InputDecoration(labelText: label),
            onChanged: (v) => setState(() => set(double.tryParse(v) ?? 0)),
          ),
        ),
      );

  Widget _card(Item it) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
        decoration: BoxDecoration(color: const Color(0xFFFAFBFD), border: Border(left: BorderSide(color: Color(it.color), width: 4)), borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          Row(children: [
            InkWell(onTap: _pickColor, child: Container(width: 26, height: 26, decoration: BoxDecoration(color: Color(it.color), borderRadius: BorderRadius.circular(6)))),
            const SizedBox(width: 8),
            Expanded(child: TextFormField(initialValue: it.name, decoration: const InputDecoration(labelText: '物品名称 Item Name'), onChanged: (v) => it.name = v)),
            IconButton(tooltip: '删除 Remove', icon: const Icon(Icons.close, size: 18), onPressed: () => widget.state.removeItem(it.id)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _field('总数量 PCS', it.totalPcs, (v) => it.totalPcs = v),
            _field('每箱 PCS/Box', it.pcsPerBox, (v) => it.pcsPerBox = v),
            _field('每箱重 KG', it.boxWeight, (v) => it.boxWeight = v),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _field('长 L cm', it.boxL, (v) => it.boxL = v),
            _field('宽 W cm', it.boxW, (v) => it.boxW = v),
            _field('高 H cm', it.boxH, (v) => it.boxH = v),
          ]),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(it.boxesNeeded > 0 ? '共 ${it.boxesNeeded} 箱 boxes' : '—', style: const TextStyle(fontSize: 12.5, color: textSecondary, fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      );

  Future<void> _pickColor() async {
    final c = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(title: const Text('选择颜色 Pick Color'), children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final col in colorPalette)
              InkWell(onTap: () => Navigator.pop(ctx, col), child: Container(width: 34, height: 34, decoration: BoxDecoration(color: Color(col), borderRadius: BorderRadius.circular(5)))),
          ]),
        ),
      ]),
    );
    if (c != null) setState(() => widget.item.color = c);
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    if (widget.compact) return _card(it);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        SizedBox(
          width: 40,
          child: Align(
            alignment: Alignment.centerLeft,
            child: InkWell(onTap: _pickColor, child: Container(width: 26, height: 26, decoration: BoxDecoration(color: Color(it.color), borderRadius: BorderRadius.circular(5), border: Border.all(color: Colors.black26, width: 2)))),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: TextFormField(initialValue: it.name, decoration: const InputDecoration(hintText: '例如: 钢管 Steel Pipe'), onChanged: (v) => it.name = v),
          ),
        ),
        _num(it.totalPcs, (v) => it.totalPcs = v, '0'),
        _num(it.pcsPerBox, (v) => it.pcsPerBox = v, '0'),
        _num(it.boxL, (v) => it.boxL = v, 'L'),
        _num(it.boxW, (v) => it.boxW = v, 'W'),
        _num(it.boxH, (v) => it.boxH = v, 'H'),
        _num(it.boxWeight, (v) => it.boxWeight = v, '选填 opt.'),
        SizedBox(width: 70, child: Text(it.boxesNeeded > 0 ? '${it.boxesNeeded} 箱' : '—', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5, color: textSecondary))),
        SizedBox(width: 40, child: IconButton(tooltip: '删除 Remove', icon: const Icon(Icons.close, size: 16), onPressed: () => widget.state.removeItem(it.id))),
      ]),
    );
  }
}

// ---------- 柜型 ----------
class _PresetsCard extends StatelessWidget {
  const _PresetsCard({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => SectionCard(
        step: 2,
        title: '选择柜型 Container Sizes',
        hint: '勾选本次可以用的柜型，系统自动挑最省的组合 — Tick allowed sizes, the cheapest mix is chosen automatically',
        child: state.presetsLoading && state.presets.isEmpty
            ? const Text('正在载入柜型预设... Loading presets...', style: TextStyle(color: textSecondary))
            : Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                for (final p in state.presets) _chip(context, p),
                OutlinedButton.icon(onPressed: () => showPresetDialog(context, state, null), icon: const Icon(Icons.add, size: 16), label: const Text('新增自定义柜型 Add Custom')),
              ]),
      );

  Widget _chip(BuildContext context, Preset p) {
    final on = p.id != null && state.activePresetIds.contains(p.id);
    return Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width - 82), // 手机上不超出画面
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      decoration: BoxDecoration(color: on ? const Color(0xFFF5F7FA) : const Color(0xFFFAFBFC), border: Border.all(color: on ? navy : borderColor, width: 1.5), borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Checkbox(value: on, activeColor: orange, onChanged: (v) => state.togglePreset(p.id!, v == true)),
        Flexible(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          Text('${fmt(p.length)}×${fmt(p.width)}×${fmt(p.height)} cm · Max ${fmt(p.maxPayload)}kg', style: const TextStyle(fontSize: 11, color: textSecondary)),
        ])),
        TextButton(onPressed: () => showPresetDialog(context, state, p), child: const Text('编辑 Edit', style: TextStyle(fontSize: 11, color: textSecondary))),
      ]),
    );
  }
}
