/// PDF 导出: A3 横向, 版面沿用网页版 (Export.html)
///
/// 每个货柜: ① 样本式第一页 (公司表头 / Shipping Information / Shipping Item / Accessory / Sign-off / 4 个视图)
///           ② 装柜顺序与工人注意事项  ③ 6 角度视角总览  ④ 混装柜才有的各物品区块特写 (每区块 3 角度 + 注意事项)
/// 多货柜时最前面再加一页总览。视图全部是矢量 (不是截图), 中文用字体子集嵌入, 所以文字可选取、体积很小。
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:vector_math/vector_math_64.dart' show Matrix4;

import '../core/models.dart';
import '../render/draw.dart' as dr;
import '../render/flat_views.dart';
import '../render/iso.dart';
import '../render/notes.dart';

const _mm = PdfPageFormat.mm;
final _navy = PdfColor.fromInt(0xFF1B2A3A);
final _gray = PdfColor.fromInt(0xFF64748B);
final _muted = PdfColor.fromInt(0xFF94A3B8);
final _noteColor = PdfColor.fromInt(0xFF334155);
final _red = PdfColor.fromInt(0xFFC0392B);
final _labelBg = PdfColor.fromInt(0xFFF5F7FA);
final _gridLine = PdfColor.fromInt(0xFFBBC2CC);

/// 本份 PDF 的中文字体: Helvetica 没有的字元 (如 ×) 用它补上
late pw.Font _cjk;

/// 字型里常有多个码位共用同一字形 (如 · 与 •)。pdf 套件的子集写入器遇到第二个共用字形的码位时
/// 会塞错字形 (• 印成「子」), 所以送进 PDF 前先把共用字形的码位统一成最小的那个。
Map<int, int> _canon = const {};

String _n(String s) => String.fromCharCodes(s.runes.map((r) => _canon[r] ?? r));

pw.Text _txt(String s, {pw.TextStyle? style, pw.TextAlign? textAlign}) => pw.Text(_n(s), style: style, textAlign: textAlign);

Map<int, int> _buildCanon(ByteData font) {
  final map = TtfParser(font).charToGlyphIndexMap;
  final firstByGlyph = <int, int>{};
  final out = <int, int>{};
  for (final rune in map.keys.toList()..sort()) {
    final g = map[rune]!;
    if (g == 0) continue;
    final first = firstByGlyph[g];
    if (first == null) {
      firstByGlyph[g] = rune;
    } else {
      out[rune] = first;
    }
  }
  return out;
}

const _circled = ['①', '②', '③', '④', '⑤', '⑥', '⑦', '⑧', '⑨'];

String _commas(num v) {
  final s = fmt(v);
  final parts = s.split('.');
  final out = parts[0].replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
  return parts.length > 1 ? '$out.${parts[1]}' : out;
}

String _dateAscii(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  String p(int n) => n.toString().padLeft(2, '0');
  return '${months[d.month - 1]} ${p(d.day)}, ${d.year}  ${p(d.hour)}:${p(d.minute)}';
}

/// 把 DrawList 以矢量画进 PDF, 依可用空间等比缩放 (靠左上)
class DrawWidget extends pw.Widget {
  DrawWidget(this.list);
  final dr.DrawList list;
  double _k = 1;

  @override
  void layout(pw.Context context, pw.BoxConstraints constraints, {bool parentUsesSize = false}) {
    final maxW = constraints.hasBoundedWidth ? constraints.maxWidth : list.width;
    final maxH = constraints.hasBoundedHeight ? constraints.maxHeight : list.height;
    _k = math.min(maxW / list.width, maxH / list.height);
    box = PdfRect(0, 0, list.width * _k, list.height * _k);
  }

  @override
  void paint(pw.Context context) {
    super.paint(context);
    final c = context.canvas;
    final font = pw.Theme.of(context).defaultTextStyle.font!.getFont(context);
    final b = box!;
    double px(double x) => b.left + x * _k;
    double py(double y) => b.bottom + b.height - y * _k;

    c.saveContext();
    c.drawBox(b);
    c.clipPath();

    var alpha = -1;
    int? lastFill, lastStroke;
    void setAlpha(int a) {
      if (a == alpha) return;
      alpha = a;
      c.setGraphicState(PdfGraphicState(fillOpacity: a / 255, strokeOpacity: a / 255));
    }

    void fillColor(int argb) {
      setAlpha((argb >> 24) & 0xFF);
      final rgb = argb & 0xFFFFFF;
      if (rgb != lastFill) {
        lastFill = rgb;
        c.setFillColor(PdfColor.fromInt(0xFF000000 | rgb));
      }
    }

    void strokeColor(int argb, double w) {
      setAlpha((argb >> 24) & 0xFF);
      final rgb = argb & 0xFFFFFF;
      if (rgb != lastStroke) {
        lastStroke = rgb;
        c.setStrokeColor(PdfColor.fromInt(0xFF000000 | rgb));
      }
      c.setLineWidth(w * _k);
    }

    void path(List<dr.Pt> pts) {
      c.moveTo(px(pts.first.x), py(pts.first.y));
      for (var i = 1; i < pts.length; i++) {
        c.lineTo(px(pts[i].x), py(pts[i].y));
      }
      c.closePath();
    }

    for (final cmd in list.cmds) {
      switch (cmd) {
        case dr.Poly():
          if (cmd.fill != null) {
            fillColor(cmd.fill!);
            path(cmd.pts);
            c.fillPath();
          }
          if (cmd.stroke != null) {
            strokeColor(cmd.stroke!, cmd.strokeWidth);
            path(cmd.pts);
            c.strokePath();
          }
        case dr.Line():
          strokeColor(cmd.color, cmd.width);
          c.moveTo(px(cmd.a.x), py(cmd.a.y));
          c.lineTo(px(cmd.b.x), py(cmd.b.y));
          c.strokePath();
        case dr.Txt():
          final size = cmd.size * _k;
          final text = _n(cmd.text);
          final w = font.stringMetrics(text).width * size;
          final dx = cmd.align == dr.TextAlign2.center ? -w / 2 : (cmd.align == dr.TextAlign2.right ? -w : 0.0);
          c.saveContext();
          if (cmd.vertical) {
            final m = Matrix4.identity()
              ..translateByDouble(px(cmd.x), py(cmd.y), 0, 1)
              ..rotateZ(math.pi / 2);
            c.setTransform(m);
          }
          final x = cmd.vertical ? dx : px(cmd.x) + dx;
          final y = cmd.vertical ? 0.0 : py(cmd.y);
          if (cmd.halo) {
            c.saveContext(); // 文字描边模式会留在图形状态里, 必须包起来还原, 否则后面的字都变成只描边
            strokeColor(0xD9FFFFFF, 2);
            c.drawString(font, size, text, x, y, mode: PdfTextRenderingMode.stroke);
            c.restoreContext();
            alpha = -1;
            lastFill = null;
            lastStroke = null;
          }
          fillColor(cmd.color);
          c.drawString(font, size, text, x, y);
          if (cmd.bold) c.drawString(font, size, text, x + 0.25 * _k, y);
          c.restoreContext();
          // restoreContext 还原了颜色/透明度: 清掉缓存避免漏设
          alpha = -1;
          lastFill = null;
          lastStroke = null;
        case dr.Badge():
          final size = cmd.fontSize * _k;
          final tw = font.stringMetrics(cmd.text).width * size;
          final w = tw + 8 * _k, h = size + 6 * _k;
          final x0 = px(cmd.cx) - w / 2, y0 = py(cmd.cy) - h / 2;
          fillColor(0xEBFFFFFF);
          c.drawRRect(x0, y0, w, h, 4 * _k, 4 * _k);
          c.fillPath();
          strokeColor(0xFF000000 | (cmd.borderColor & 0xFFFFFF), 1.5);
          c.drawRRect(x0, y0, w, h, 4 * _k, 4 * _k);
          c.strokePath();
          fillColor(0xFF1B2A3A);
          c.drawString(font, size, cmd.text, px(cmd.cx) - tw / 2, py(cmd.cy) - size * 0.35);
      }
    }
    c.restoreContext();
  }
}

/// 只嵌 Regular: 粗体用「错开一点再写一次」模拟 (与网页版相同)
pw.Widget _bold(String s, double size, {PdfColor? color, double strike = 0.3}) {
  final st = pw.TextStyle(fontSize: size, color: color ?? _navy);
  return pw.Stack(children: [
    _txt(s, style: st),
    pw.Transform.translate(offset: PdfPoint(strike, 0), child: _txt(s, style: st)),
  ]);
}

pw.Widget _swatch(int color, double size) => pw.Container(width: size, height: size, color: PdfColor.fromInt(0xFF000000 | (color & 0xFFFFFF)));

/// 通用表格: 表头 Helvetica 粗体白字深底, 内容用中文字体 (自动折行, 不会溢出到隔壁栏)
pw.Widget _table({
  List<String>? head,
  required List<List<String>> rows,
  required Map<int, pw.TableColumnWidth> widths,
  double fontSize = 8,
  double pad = 1.6 * _mm,
  pw.Alignment align = pw.Alignment.centerLeft,
  Set<int> leftCols = const {},
  Set<int> labelCols = const {},
  double? minRowHeight,
}) {
  final headStyle = pw.TextStyle(font: pw.Font.helveticaBold(), fontFallback: [_cjk], fontSize: fontSize, color: PdfColors.white);
  pw.Widget cell(String t, {bool header = false, int col = 0}) {
    final label = labelCols.contains(col);
    return pw.Container(
      color: header ? _navy : (label ? _labelBg : null),
      padding: pw.EdgeInsets.all(pad),
      constraints: (!header && minRowHeight != null) ? pw.BoxConstraints(minHeight: minRowHeight) : null,
      alignment: leftCols.contains(col) ? pw.Alignment.centerLeft : align,
      child: _txt(t,
          textAlign: leftCols.contains(col) || align == pw.Alignment.centerLeft ? pw.TextAlign.left : pw.TextAlign.center,
          style: header
              ? headStyle
              : (label ? pw.TextStyle(font: pw.Font.helveticaBold(), fontFallback: [_cjk], fontSize: fontSize, color: _navy) : pw.TextStyle(fontSize: fontSize, color: _navy))),
    );
  }

  return pw.Table(
    border: pw.TableBorder.all(color: _gridLine, width: 0.5),
    columnWidths: widths,
    children: [
      if (head != null) pw.TableRow(verticalAlignment: pw.TableCellVerticalAlignment.full, children: [for (var i = 0; i < head.length; i++) cell(head[i], header: true, col: i)]),
      for (final r in rows) pw.TableRow(verticalAlignment: pw.TableCellVerticalAlignment.full, children: [for (var i = 0; i < r.length; i++) cell(r[i], col: i)]),
    ],
  );
}

pw.Widget _companyHeader(UserProfile? u, pw.ImageProvider? logo, DateTime now) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        if (logo != null) ...[
          pw.Container(constraints: const pw.BoxConstraints(maxWidth: 30 * _mm, maxHeight: 16 * _mm), child: pw.Image(logo, fit: pw.BoxFit.contain)),
          pw.SizedBox(width: 6 * _mm),
        ],
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            _bold((u?.companyName.isNotEmpty ?? false) ? u!.companyName : '(未设定公司名称 Company name not set)', 15),
            if (u?.companyAddress.isNotEmpty ?? false) ...[
              pw.SizedBox(height: 1.5 * _mm),
              _txt(u!.companyAddress, style: pw.TextStyle(fontSize: 9, color: _gray)),
            ],
          ]),
        ),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          _txt(_dateAscii(now), style: pw.TextStyle(fontSize: 8, color: _muted)),
          _txt('Prepared by: ${u?.email ?? ''}', style: pw.TextStyle(fontSize: 8, color: _muted)),
        ]),
      ]),
      pw.SizedBox(height: 3 * _mm),
      pw.Container(height: 0.6 * _mm, color: _navy),
      pw.SizedBox(height: 3 * _mm),
      pw.Center(child: _bold('集装箱装载方案 CONTAINER LOADING METHOD', 13)),
      pw.SizedBox(height: 4 * _mm),
    ]);

pw.Widget _miniHeader(UserProfile? u, String title, DateTime now) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Row(children: [
        pw.Expanded(flex: 2, child: _bold(u?.companyName ?? '', 10)),
        pw.Expanded(flex: 6, child: pw.Center(child: _bold(title, 11))),
        pw.Expanded(flex: 2, child: pw.Align(alignment: pw.Alignment.centerRight, child: _txt(_dateAscii(now), style: pw.TextStyle(fontSize: 8, color: _muted)))),
      ]),
      pw.SizedBox(height: 1.5 * _mm),
      pw.Container(height: 0.4 * _mm, color: _navy),
      pw.SizedBox(height: 4 * _mm),
    ]);

pw.Widget _firstPage(ContainerResult c, int idx, ShipmentInfo s, UserProfile? u, pw.ImageProvider? logo, DateTime now) {
  const gap = 6 * _mm;
  final shown = c.allocations.take(_circled.length).toList();
  final acc = s.accessories.where((a) => a.name.isNotEmpty).toList();

  final info = _table(
    rows: [
      ['Customer', s.customer.isEmpty ? '-' : s.customer],
      ['ETD', s.etd.isEmpty ? '-' : s.etd],
      ['ETA', s.eta.isEmpty ? '-' : s.eta],
      ['Shipping Line', s.shippingLine.isEmpty ? '-' : s.shippingLine],
      ['Container Size', c.containerType],
      ['Remark', s.remark.isEmpty ? '-' : s.remark],
    ],
    widths: const {0: pw.FlexColumnWidth(4), 1: pw.FlexColumnWidth(6)},
    labelCols: const {0},
  );
  final items = pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
    _table(
      head: const ['No.', 'Part Name', 'Qty', 'Carton Qty\n(Case)', 'Box Size (1Box)\nL×W×H (mm)'],
      rows: [
        for (var i = 0; i < shown.length; i++)
          [
            _circled[i], shown[i].name, _commas(shown[i].pcsPlaced), _commas(shown[i].boxesPlaced),
            '${(shown[i].boxL * 10).round()}×${(shown[i].boxW * 10).round()}×${(shown[i].boxH * 10).round()}',
          ],
      ],
      widths: const {0: pw.FlexColumnWidth(9), 1: pw.FlexColumnWidth(33), 2: pw.FlexColumnWidth(14), 3: pw.FlexColumnWidth(18), 4: pw.FlexColumnWidth(26)},
      fontSize: 7.5,
      align: pw.Alignment.center,
      leftCols: const {1},
    ),
    if (c.allocations.length > _circled.length)
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 1 * _mm),
        child: _txt('+ ${c.allocations.length - _circled.length} more items (see allocation table on next page)', style: pw.TextStyle(fontSize: 7, color: _muted)),
      ),
  ]);
  final right = pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
    _bold('ACCESSORY', 8.5),
    pw.SizedBox(height: 1 * _mm),
    _table(
      head: const ['Accessory', 'Qty'],
      rows: acc.isEmpty ? const [['-', '-']] : [for (final a in acc) [a.name, a.qty.isEmpty ? '-' : a.qty]],
      widths: const {0: pw.FlexColumnWidth(7), 1: pw.FlexColumnWidth(3)},
      fontSize: 7.5,
    ),
    pw.SizedBox(height: 3 * _mm),
    _bold('SIGN-OFF', 8.5),
    pw.SizedBox(height: 1 * _mm),
    _table(
      head: const ['DRAWN', 'CHECKED', 'CONFIRMED'],
      rows: [[s.drawn, s.checked, s.confirmed]],
      widths: const {0: pw.FlexColumnWidth(), 1: pw.FlexColumnWidth(), 2: pw.FlexColumnWidth()},
      align: pw.Alignment.center,
      minRowHeight: 12 * _mm,
    ),
  ]);

  final front = buildStackedLayers(c, true), back = buildStackedLayers(c, false);
  pw.Widget legendRow(int color, String t, double fs) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 1.4 * _mm),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Padding(padding: const pw.EdgeInsets.only(top: 0.5 * _mm, right: 1.5 * _mm), child: _swatch(color, 2.8 * _mm)),
          pw.Expanded(child: _txt(t, style: pw.TextStyle(fontSize: fs, color: _navy))),
        ]),
      );

  return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
    _companyHeader(u, logo, now),
    pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.SizedBox(width: 84 * _mm, child: info),
      pw.SizedBox(width: gap),
      pw.Expanded(child: items),
      pw.SizedBox(width: gap),
      pw.SizedBox(width: 110 * _mm, child: right),
    ]),
    pw.SizedBox(height: 3 * _mm),
    pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
      _bold('UNIT #${idx + 1}  ·  ${c.containerType}', 11),
      pw.SizedBox(width: 10 * _mm),
      pw.Expanded(
        child: _txt(
          'Dims: ${fmt(c.L)}x${fmt(c.W)}x${fmt(c.H)} cm   |   Volume Util: ${(c.utilization * 100).toStringAsFixed(1)}%   |   Weight: ${_commas(c.totalWeightUsed)} / ${_commas(c.maxPayload)} kg   |   Door end = left of Right View',
          style: pw.TextStyle(fontSize: 8.5, color: _gray),
        ),
      ),
    ]),
    pw.SizedBox(height: 2 * _mm),
    // 两排视图占满剩余高度, 表格再长也不会把视图挤出页面
    pw.Expanded(
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Expanded(
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(flex: 210, child: DrawWidget(renderIso(c, IsoCamera.defaultFor(c), w: 860, h: 320))),
            pw.SizedBox(width: gap),
            pw.Expanded(flex: 120, child: DrawWidget(drawRightView(c))),
            pw.SizedBox(width: gap),
            pw.Expanded(
              flex: 50,
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                for (var i = 0; i < c.allocations.length && i < _circled.length; i++)
                  legendRow(c.allocations[i].color, '${_circled[i]} ${c.allocations[i].name}  ${fmt(c.allocations[i].startLength)}-${fmt(c.allocations[i].endLength)} cm', 7.5),
              ]),
            ),
          ]),
        ),
        pw.SizedBox(height: 3 * _mm),
        pw.Row(children: [
          pw.Expanded(flex: 120, child: _txt('FRONT (door end)', style: pw.TextStyle(fontSize: 7, color: _gray))),
          pw.SizedBox(width: gap),
          pw.Expanded(flex: 120, child: _txt('BACK (far end)', style: pw.TextStyle(fontSize: 7, color: _gray))),
          pw.SizedBox(width: gap),
          pw.Expanded(flex: 140, child: pw.SizedBox()),
        ]),
        pw.Expanded(
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(flex: 120, child: DrawWidget(drawFlatView(c, front))),
            pw.SizedBox(width: gap),
            pw.Expanded(flex: 120, child: DrawWidget(drawFlatView(c, back))),
            pw.SizedBox(width: gap),
            pw.Expanded(
              flex: 140,
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                _bold('FRONT VIEW', 8),
                pw.SizedBox(height: 1 * _mm),
                for (final l in front) legendRow(l.color, '${l.name}  (${fmt(l.pcsPerBox)} PCS/box, H${l.horizontal}×V${l.vertical})', 7.5),
                pw.SizedBox(height: 1 * _mm),
                _bold('BACK VIEW', 8),
                pw.SizedBox(height: 1 * _mm),
                for (final l in back) legendRow(l.color, '${l.name}  (${fmt(l.pcsPerBox)} PCS/box, H${l.horizontal}×V${l.vertical})', 7.5),
              ]),
            ),
          ]),
        ),
      ]),
    ),
  ]);
}

List<pw.Widget> _notesPage(ContainerResult c) {
  final out = <pw.Widget>[
    _table(
      head: const ['Sec.', 'Item', 'PCS/Box', 'Boxes', 'PCS', 'Layout H x V x Depth', 'Orientation', 'From Door (cm)', 'Height (cm)', 'Weight (kg)'],
      rows: [
        for (var i = 0; i < c.allocations.length; i++)
          () {
            final a = c.allocations[i];
            final d = describeAllocation(a, c, i);
            return [
              i < _circled.length ? _circled[i] : '${i + 1}', a.name, fmt(d.pcsPerBox), '${a.boxesPlaced}', _commas(a.pcsPlaced),
              '${a.horizontal} x ${a.vertical} x ${a.columns}', a.rotated ? '横放旋转90° Rotated' : '正放 Standard',
              '${fmt(d.startLength)} - ${fmt(d.endLength)}', fmt(d.blockHeight), d.weightKg > 0 ? fmt(d.weightKg) : '-',
            ];
          }(),
      ],
      widths: const {
        0: pw.FlexColumnWidth(4), 1: pw.FlexColumnWidth(20), 2: pw.FlexColumnWidth(6), 3: pw.FlexColumnWidth(6), 4: pw.FlexColumnWidth(7),
        5: pw.FlexColumnWidth(12), 6: pw.FlexColumnWidth(13), 7: pw.FlexColumnWidth(11), 8: pw.FlexColumnWidth(8), 9: pw.FlexColumnWidth(8),
      },
    ),
    pw.SizedBox(height: 6 * _mm),
  ];
  for (var i = 0; i < c.allocations.length; i++) {
    final a = c.allocations[i];
    final d = describeAllocation(a, c, i);
    out.add(pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4 * _mm),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Row(children: [
          _swatch(a.color, 4 * _mm),
          pw.SizedBox(width: 2 * _mm),
          _bold('Section ${i + 1} · ${a.name}   (${fmt(d.pcsPerBox)} PCS/box · ${d.boxDims} cm · ${a.horizontal}x${a.vertical}x${a.columns})', 9.5),
        ]),
        pw.SizedBox(height: 1.5 * _mm),
        for (final n in d.notes)
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 4 * _mm, bottom: 0.8 * _mm),
            child: _txt('• $n', style: pw.TextStyle(fontSize: 8.5, color: _noteColor)),
          ),
      ]),
    ));
  }
  return out;
}

pw.Widget _thumb(dr.DrawList list, double w, double h, {PdfColor? border, double borderW = 0.85}) => pw.Container(
      width: w,
      height: h,
      decoration: pw.BoxDecoration(border: pw.Border.all(color: border ?? _navy, width: borderW)),
      child: DrawWidget(list),
    );

pw.Widget _overviewPage(ContainerResult c, double usableW) {
  const gapV = 6 * _mm;
  final thumbW = (usableW - gapV * 2) / 3, thumbH = thumbW / (840 / 600);
  final vps = overviewViewpoints(c);
  pw.Widget cell(ViewPointDef vp) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        _thumb(renderIso(c, IsoCamera(vp.dir)), thumbW, thumbH),
        pw.SizedBox(height: 1.5 * _mm),
        pw.SizedBox(width: thumbW, child: _bold(vp.label, 8.5)),
      ]);
  pw.Widget row(int from) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [for (var i = from; i < from + 3 && i < vps.length; i++) cell(vps[i])]);
  return pw.Column(children: [row(0), pw.SizedBox(height: 6 * _mm), row(3)]);
}

List<pw.Widget> _closeupBlocks(ContainerResult c, double usableW) {
  final thumbW = (usableW - 12 * _mm) / 3, thumbH = thumbW / (840 / 600);
  final out = <pw.Widget>[];
  for (var i = 0; i < c.allocations.length; i++) {
    final info = describeAllocation(c.allocations[i], c, i);
    final vps = closeupViewpoints(c, i);
    final col = PdfColor.fromInt(0xFF000000 | (info.color & 0xFFFFFF));
    final half = (info.notes.length + 1) ~/ 2;
    pw.Widget notes(Iterable<String> ns) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          for (final n in ns)
            pw.Padding(padding: const pw.EdgeInsets.only(bottom: 0.8 * _mm), child: _txt('• $n', style: pw.TextStyle(fontSize: 8, color: _noteColor))),
        ]);
    out.add(pw.Inseparable(child: pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5 * _mm),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Row(children: [
          _swatch(info.color, 4 * _mm),
          pw.SizedBox(width: 2 * _mm),
          pw.Expanded(
            child: _bold(
                'Section ${info.section} · ${info.name}   —   ${fmt(info.pcsPerBox)} PCS/box · ${info.boxes} boxes · ${_commas(info.pcs)} PCS · H${info.horizontal}xV${info.vertical}xDepth${info.columns} · ${fmt(info.startLength)}-${fmt(info.endLength)} cm from door${info.weightKg > 0 ? ' · ${fmt(info.weightKg)} kg' : ''}',
                9.5),
          ),
        ]),
        pw.SizedBox(height: 1.5 * _mm),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          for (var k = 0; k < vps.length; k++)
            pw.Stack(children: [
              _thumb(renderIso(c, IsoCamera(vps[k].dir), focus: i), thumbW, thumbH, border: col, borderW: 1.7),
              pw.Positioned(left: 1.5 * _mm, bottom: 1.5 * _mm, child: _bold(closeupAngleLabels[k], 8)),
            ]),
        ]),
        pw.SizedBox(height: 2 * _mm),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(child: notes(info.notes.take(half))),
          pw.SizedBox(width: 4 * _mm),
          pw.Expanded(child: notes(info.notes.skip(half))),
        ]),
      ]),
    )));
  }
  return out;
}

pw.Widget _summaryPage(PackResult r, List<Item> items, UserProfile? u, pw.ImageProvider? logo, DateTime now) {
  final types = <String, int>{};
  for (final c in r.containers) {
    types[c.containerType] = (types[c.containerType] ?? 0) + 1;
  }
  return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
    _companyHeader(u, logo, now),
    _table(
      rows: [
        ['Total Containers', '${r.containers.length}'],
        ['Container Mix', types.entries.map((e) => '${e.value}x ${e.key}').join('  +  ')],
        ['Avg. Utilization', '${(r.avgUtilization * 100).toStringAsFixed(1)}%'],
      ],
      widths: const {0: pw.FlexColumnWidth(2), 1: pw.FlexColumnWidth(8)},
      labelCols: const {0},
      fontSize: 10,
    ),
    pw.SizedBox(height: 8 * _mm),
    _txt('Full Item List (All Containers)', style: pw.TextStyle(font: pw.Font.helveticaBold(), fontSize: 11, color: _navy)),
    pw.SizedBox(height: 2 * _mm),
    _table(
      head: const ['Item', 'Total PCS', 'PCS/Box', 'Box L x W x H (cm)', 'Boxes Needed'],
      rows: [
        for (final it in items)
          [it.name, _commas(it.totalPcs), fmt(it.pcsPerBox), '${fmt(it.boxL)}x${fmt(it.boxW)}x${fmt(it.boxH)}', _commas(it.boxesNeeded)],
      ],
      widths: const {0: pw.FlexColumnWidth(4), 1: pw.FlexColumnWidth(1.5), 2: pw.FlexColumnWidth(1.5), 3: pw.FlexColumnWidth(2), 4: pw.FlexColumnWidth(1.5)},
      fontSize: 10,
    ),
    if (r.unfulfilled.isNotEmpty) ...[
      pw.SizedBox(height: 6 * _mm),
      _txt('Warning: some items could not be placed in the selected containers: ${r.unfulfilled.map((i) => '${i.name} (${i.boxesRemaining} boxes)').join(', ')}',
          style: pw.TextStyle(fontSize: 9, color: _red)),
    ],
  ]);
}

/// 产生 PDF 位元组。fontBytes 省略时从 App 资源载入 (测试时可直接传入)
Future<Uint8List> buildPdf({
  required PackResult result,
  required ShipmentInfo shipment,
  required UserProfile? user,
  List<Item> itemsFallback = const [],
  Uint8List? fontBytes,
  DateTime? now,
}) async {
  final bytes = fontBytes ?? (await rootBundle.load('assets/fonts/NotoSansSC-subset.ttf')).buffer.asUint8List();
  final ttf = pw.Font.ttf(ByteData.sublistView(bytes)); // pdf 套件只会嵌入实际用到的字形
  _cjk = ttf;
  _canon = _buildCanon(ByteData.sublistView(bytes));
  final theme = pw.ThemeData.withFont(base: ttf, bold: ttf, italic: ttf, boldItalic: ttf);
  final format = PdfPageFormat.a3.landscape;
  final pageTheme = pw.PageTheme(pageFormat: format, margin: const pw.EdgeInsets.all(14 * _mm), theme: theme);
  final usableW = format.width - 28 * _mm;
  final at = now ?? DateTime.now();

  pw.ImageProvider? logo;
  final lu = user?.logoDataUrl ?? '';
  if (lu.isNotEmpty) {
    try {
      logo = pw.MemoryImage(base64Decode(lu.split(',').last));
    } catch (_) {/* 损坏的 Logo 直接略过 */}
  }

  final doc = pw.Document(compress: true, title: 'Container Loading Plan', creator: 'Container Loading Calculator');

  if (result.containers.length > 1) {
    final items = result.items.isNotEmpty ? result.items : itemsFallback;
    doc.addPage(pw.Page(pageTheme: pageTheme, build: (_) => _summaryPage(result, items, user, logo, at)));
  }

  for (var idx = 0; idx < result.containers.length; idx++) {
    final c = result.containers[idx];
    await Future<void>.delayed(Duration.zero); // 让出主线程, 页面不会看起来卡死
    doc.addPage(pw.Page(pageTheme: pageTheme, build: (_) => _firstPage(c, idx, shipment, user, logo, at)));
    doc.addPage(pw.MultiPage(
      pageTheme: pageTheme,
      header: (_) => _miniHeader(user, 'UNIT #${idx + 1} · ${c.containerType} · Loading Sequence & Worker Notes 装柜顺序与注意事项', at),
      build: (_) => _notesPage(c),
    ));
    doc.addPage(pw.Page(
      pageTheme: pageTheme,
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        _miniHeader(user, 'UNIT #${idx + 1} · View Points 视角总览', at),
        _overviewPage(c, usableW),
      ]),
    ));
    if (c.allocations.length > 1) {
      doc.addPage(pw.MultiPage(
        pageTheme: pageTheme,
        header: (_) => _miniHeader(user, 'UNIT #${idx + 1} · Per-Item Close-Ups 各物品区块特写', at),
        build: (_) => _closeupBlocks(c, usableW),
      ));
    }
  }
  return doc.save();
}
