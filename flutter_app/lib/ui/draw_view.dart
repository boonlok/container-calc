/// 把 DrawList 画到 Flutter 画布上
library;

import 'package:flutter/material.dart';

import '../render/draw.dart' as d;

class DrawListPainter extends CustomPainter {
  DrawListPainter(this.list);
  final d.DrawList list;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / list.width;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(k, k);
    final fill = Paint()..style = PaintingStyle.fill..isAntiAlias = true;
    final stroke = Paint()..style = PaintingStyle.stroke..isAntiAlias = true;
    for (final c in list.cmds) {
      switch (c) {
        case d.Poly():
          final path = Path()..moveTo(c.pts.first.x, c.pts.first.y);
          for (var i = 1; i < c.pts.length; i++) {
            path.lineTo(c.pts[i].x, c.pts[i].y);
          }
          path.close();
          if (c.fill != null) canvas.drawPath(path, fill..color = Color(c.fill!));
          if (c.stroke != null) canvas.drawPath(path, stroke..color = Color(c.stroke!)..strokeWidth = c.strokeWidth);
        case d.Line():
          canvas.drawLine(Offset(c.a.x, c.a.y), Offset(c.b.x, c.b.y), stroke..color = Color(c.color)..strokeWidth = c.width);
        case d.Txt():
          _text(canvas, c);
        case d.Badge():
          _badge(canvas, c, fill, stroke);
      }
    }
    canvas.restore();
  }

  TextPainter _tp(String t, double size, Color color, {bool bold = false, Paint? fg}) => TextPainter(
        text: TextSpan(
            text: t,
            style: fg != null
                ? TextStyle(fontFamily: 'NotoSansSC', fontSize: size, fontWeight: bold ? FontWeight.w700 : FontWeight.w400, foreground: fg)
                : TextStyle(fontFamily: 'NotoSansSC', fontSize: size, fontWeight: bold ? FontWeight.w700 : FontWeight.w400, color: color)),
        textDirection: TextDirection.ltr,
      )..layout();

  void _text(Canvas canvas, d.Txt t) {
    final tp = _tp(t.text, t.size, Color(t.color), bold: t.bold);
    double dx(double w) => t.align == d.TextAlign2.center ? -w / 2 : (t.align == d.TextAlign2.right ? -w : 0);
    final base = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    canvas.save();
    canvas.translate(t.x, t.y);
    if (t.vertical) canvas.rotate(-1.5707963);
    final o = Offset(dx(tp.width), -base);
    if (t.halo) {
      final halo = Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = const Color(0xD9FFFFFF);
      _tp(t.text, t.size, Colors.white, bold: t.bold, fg: halo).paint(canvas, o);
    }
    tp.paint(canvas, o);
    canvas.restore();
  }

  void _badge(Canvas canvas, d.Badge b, Paint fill, Paint stroke) {
    final tp = _tp(b.text, b.fontSize, const Color(0xFF1B2A3A), bold: true);
    final w = tp.width + 8, h = b.fontSize + 6;
    final r = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(b.cx, b.cy), width: w, height: h), const Radius.circular(4));
    canvas.drawRRect(r, fill..color = const Color(0xEBFFFFFF));
    canvas.drawRRect(r, stroke..color = Color(b.borderColor)..strokeWidth = 1.5);
    tp.paint(canvas, Offset(b.cx - tp.width / 2, b.cy - tp.height / 2));
  }

  @override
  bool shouldRepaint(DrawListPainter oldDelegate) => !identical(oldDelegate.list, list);
}

/// 依 DrawList 比例占满宽度的静态视图
class DrawView extends StatelessWidget {
  const DrawView(this.list, {super.key});
  final d.DrawList list;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: AspectRatio(
          aspectRatio: list.width / list.height,
          child: CustomPaint(painter: DrawListPainter(list), size: Size.infinite),
        ),
      );
}
