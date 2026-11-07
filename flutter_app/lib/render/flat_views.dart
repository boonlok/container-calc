/// 2D 视图: 正面 / 背面 (Front/Back) 与侧视图 (Right View)
///
/// 移植自 Viewer3D.html 的 drawFlatView / drawRightView, 版面常数、文字与颜色都相同。
library;

import '../core/models.dart';
import 'draw.dart';
import 'notes.dart';

const int _bg = 0xFFF5F7FA, _navy = 0xFF1B2A3A, _gray = 0xFF64748B, _muted = 0xFF94A3B8;

String _clip(String s, int n) => s.length > n ? '${s.substring(0, n - 1)}…' : s;

DrawList _empty(double w, double h) {
  final d = DrawList(w, h);
  d.cmds.add(Txt('无数据 No data', w / 2, h / 2, size: 12, color: _muted, align: TextAlign2.center));
  return d;
}

/// 小圆角数字徽章 (2D 版「角落数字」, 与 3D 模型上的贴牌呼应)
Badge _badge(double cx, double cy, String text, double fontSize, int color) => Badge(cx, cy, text, fontSize, color);

DrawList drawFlatView(ContainerResult c, List<StackLayer> layers, {double w = 460, double h = 300}) {
  if (layers.isEmpty) return _empty(w, h);
  final d = DrawList(w, h);
  final contW = c.W, contH = c.H;
  const padTop = 22.0, padBottom = 16.0, padSide = 46.0;
  final availW = w - padSide * 2, availH = h - padTop - padBottom;
  final scale = availW / contW < availH / contH ? availW / contW : availH / contH;
  final drawW = contW * scale, drawH = contH * scale;
  final offsetX = (w - drawW) / 2, offsetY = padTop;

  d.rect(offsetX, offsetY, drawW, drawH, fill: _bg);

  for (final layer in layers) {
    final gridW = layer.widthUnit * scale, gridH = layer.boxH * scale;
    final blockWidth = layer.horizontal * layer.widthUnit * scale;
    final blockHeight = layer.vertical * layer.boxH * scale;
    final gridStartX = offsetX + (drawW - blockWidth) / 2;
    final blockTopY = offsetY + drawH - layer.yOffset * scale - blockHeight;

    for (var v = 0; v < layer.vertical; v++) {
      for (var hh = 0; hh < layer.horizontal; hh++) {
        final x = gridStartX + hh * gridW;
        final y = blockTopY + (layer.vertical - 1 - v) * gridH;
        d.rect(x + 1, y + 1, (gridW - 2).clamp(0, double.infinity), (gridH - 2).clamp(0, double.infinity),
            fill: withAlpha(layer.color, 0.88));
        d.rect(x.roundToDouble() + 0.5, y.roundToDouble() + 0.5, gridW, gridH, stroke: 0x38000000, strokeWidth: 1);
      }
    }
    d.rect(gridStartX, blockTopY, blockWidth, blockHeight, stroke: 0x8C000000, strokeWidth: 1.5);

    final labelName = _clip(layer.name, 14);
    if (blockWidth >= 54 && blockHeight >= 34) {
      final cx = gridStartX + blockWidth / 2, cy = blockTopY + blockHeight / 2;
      final nameFont = (blockHeight / 5).floor().clamp(9, 15).toDouble();
      final pcsFont = (blockHeight / 7).floor().clamp(8, 12).toDouble();
      d.cmds.add(Txt(labelName, cx, cy - pcsFont * 0.7 + nameFont * 0.35,
          size: nameFont, bold: true, align: TextAlign2.center, halo: true));
      d.cmds.add(Txt('${fmt(layer.pcsPerBox)} PCS/箱', cx, cy + nameFont * 0.6 + pcsFont * 0.35,
          size: pcsFont, bold: true, align: TextAlign2.center, halo: true, mono: true));
    }
  }

  d.rect(offsetX, offsetY, drawW, drawH, stroke: _navy, strokeWidth: 2);
  d.cmds.add(Txt('${fmt(contH)} cm', offsetX - 10, offsetY + drawH / 2, size: 10, color: _gray, align: TextAlign2.center, vertical: true, mono: true));
  d.cmds.add(Txt('${fmt(contW)} cm', w / 2, offsetY - 8, size: 10, color: _gray, align: TextAlign2.center, mono: true));

  final tiny = layers.where((l) => l.horizontal * l.widthUnit * scale < 54 || l.vertical * l.boxH * scale < 34).toList();
  if (tiny.isNotEmpty) {
    var lx = 4.0;
    final ly = h - 6;
    for (final l in tiny.take(4)) {
      final label = '${_clip(l.name, 12)} (${fmt(l.pcsPerBox)}pcs/箱)';
      d.rect(lx, ly - 8, 8, 8, fill: l.color);
      d.cmds.add(Txt(label, lx + 11, ly, size: 10, color: _gray));
      lx += label.length * 5.6 + 25; // 粗略宽度 (画布上没有量测文字的函式)
    }
  }
  return d;
}

/// 侧视图: 沿「柜门→柜底」深度轴看过去的剖面, X = 长度, Y = 高度 (直接用真实资料, 不需要堆叠近似)
DrawList drawRightView(ContainerResult c, {double w = 460, double h = 300}) {
  if (c.allocations.isEmpty) return _empty(w, h);
  final d = DrawList(w, h);
  final contL = c.L, contH = c.H;
  const padTop = 22.0, padBottom = 16.0, padSide = 40.0;
  final availW = w - padSide * 2, availH = h - padTop - padBottom;
  final scale = availW / contL < availH / contH ? availW / contL : availH / contH;
  final drawW = contL * scale, drawH = contH * scale;
  final offsetX = (w - drawW) / 2, offsetY = padTop;

  d.rect(offsetX, offsetY, drawW, drawH, fill: _bg);

  for (final a in c.allocations) {
    final blockX = offsetX + a.startLength * scale;
    final blockW = a.lengthUsed * scale;
    final blockH = a.vertical * a.boxH * scale;
    final blockY = offsetY + drawH - blockH;
    final colW = blockW / a.columns, rowH = a.boxH * scale;

    for (var col = 0; col < a.columns; col++) {
      for (var row = 0; row < a.vertical; row++) {
        final x = blockX + col * colW;
        final y = blockY + (a.vertical - 1 - row) * rowH;
        d.rect(x + 1, y + 1, (colW - 2).clamp(0, double.infinity), (rowH - 2).clamp(0, double.infinity), fill: withAlpha(a.color, 0.88));
        d.rect(x.roundToDouble() + 0.5, y.roundToDouble() + 0.5, colW, rowH, stroke: 0x33000000, strokeWidth: 1);
      }
    }
    d.rect(blockX, blockY, blockW, blockH, stroke: 0x8C000000, strokeWidth: 1.5);

    final cornerFont = (blockH / 4).floor().clamp(9, 15).toDouble();
    if (blockH >= 16) d.cmds.add(_badge(blockX + blockW / 2, blockY - 9, '${a.vertical}', cornerFont, a.color));
    if (blockW >= 16) d.cmds.add(_badge(blockX + blockW - 12, blockY + blockH - 10, '${a.columns}', cornerFont, a.color));
  }

  d.rect(offsetX, offsetY, drawW, drawH, stroke: _navy, strokeWidth: 2);
  d.cmds.add(Txt('${fmt(contH)} cm', offsetX - 8, offsetY + drawH / 2, size: 10, color: _gray, align: TextAlign2.center, vertical: true, mono: true));
  d.cmds.add(Txt('${fmt(contL)} cm', w / 2, offsetY - 8, size: 10, color: _gray, align: TextAlign2.center, mono: true));
  return d;
}
