/// 绘图指令 Draw commands
///
/// 视图 (2D 剖面、等轴测 3D) 都先产生一串与平台无关的绘图指令, 再由两个后端各自重播:
///   · FlutterDrawPainter  → 画面 (CustomPainter)
///   · PdfDrawPainter      → PDF (矢量, 清晰且体积很小, 不需要截图)
/// 颜色一律是 ARGB 整数 (含透明度)。
library;

class Pt {
  const Pt(this.x, this.y);
  final double x, y;
}

sealed class Cmd {
  const Cmd();
}

/// 多边形 (含矩形): 可填色、可描边
class Poly extends Cmd {
  const Poly(this.pts, {this.fill, this.stroke, this.strokeWidth = 1});
  final List<Pt> pts;
  final int? fill, stroke;
  final double strokeWidth;
}

class Line extends Cmd {
  const Line(this.a, this.b, {required this.color, this.width = 1});
  final Pt a, b;
  final int color;
  final double width;
}

enum TextAlign2 { left, center, right }

class Txt extends Cmd {
  const Txt(this.text, this.x, this.y,
      {this.size = 10, this.color = 0xFF1B2A3A, this.align = TextAlign2.left, this.bold = false, this.halo = false, this.vertical = false, this.mono = false});

  /// 文字基准线位置 (x, y)。halo: 先描一圈白边再写字 (深浅底色都看得清); vertical: 逆时针旋转 90° (高度标注)
  final String text;
  final double x, y, size;
  final int color;
  final TextAlign2 align;
  final bool bold, halo, vertical, mono;
}

/// 圆角小徽章 (白底 + 物品色边框 + 数字)
class Badge extends Cmd {
  const Badge(this.cx, this.cy, this.text, this.fontSize, this.borderColor);
  final double cx, cy, fontSize;
  final String text;
  final int borderColor;
}

class DrawList {
  DrawList(this.width, this.height);
  final double width, height;
  final List<Cmd> cmds = [];

  void rect(double x, double y, double w, double h, {int? fill, int? stroke, double strokeWidth = 1}) {
    cmds.add(Poly([Pt(x, y), Pt(x + w, y), Pt(x + w, y + h), Pt(x, y + h)], fill: fill, stroke: stroke, strokeWidth: strokeWidth));
  }
}

int withAlpha(int argb, double alpha) => ((alpha.clamp(0, 1) * 255).round() << 24) | (argb & 0xFFFFFF);

/// 依亮度系数调整颜色 (>1 变亮, <1 变暗), 保持原透明度
int shade(int argb, double f) {
  int ch(int v) => (v * f).round().clamp(0, 255);
  final a = (argb >> 24) & 0xFF;
  return (a << 24) | (ch((argb >> 16) & 0xFF) << 16) | (ch((argb >> 8) & 0xFF) << 8) | ch(argb & 0xFF);
}
