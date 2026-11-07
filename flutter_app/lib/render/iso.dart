/// 等轴测 3D 视图 (纯 Dart 自绘, 不依赖 WebGL)
///
/// 坐标与网页版 (Three.js) 相同: X = 柜长 (柜门在 -X 端), Y = 高度, Z = 柜宽。
/// 正交投影 + 画家算法; 每个物品区块只画「摄影机看得到的外壳面」(而不是每个箱子 6 面),
/// 所以几万个箱子也只有几百~几千个多边形, 可以拖曳旋转时即时重绘。
/// 输出是平台无关的 DrawList, 画面和 PDF 共用 (PDF 里是矢量图)。
library;

import 'dart:math' as math;

import '../core/models.dart';
import 'draw.dart';
import 'notes.dart';

class Vec3 {
  const Vec3(this.x, this.y, this.z);
  final double x, y, z;
  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double k) => Vec3(x * k, y * k, z * k);
  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;
  Vec3 cross(Vec3 o) => Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(dot(this));
  Vec3 get unit {
    final l = length;
    return l == 0 ? this : Vec3(x / l, y / l, z / l);
  }
}

/// 摄影机: 只用「从目标指向摄影机的方向」(eye) 决定角度, 另有缩放与平移 (拖曳/滚轮用)
class IsoCamera {
  IsoCamera(Vec3 dir, {this.zoom = 1, this.panX = 0, this.panY = 0}) : eye = dir.unit;

  /// 依 yaw (绕 Y 轴) 与 pitch (仰角) 建立
  factory IsoCamera.fromAngles(double yaw, double pitch, {double zoom = 1}) {
    final cp = math.cos(pitch);
    return IsoCamera(Vec3(cp * math.sin(yaw), math.sin(pitch), cp * math.cos(yaw)), zoom: zoom);
  }

  final Vec3 eye;
  final double zoom, panX, panY;

  double get yaw => math.atan2(eye.x, eye.z);
  double get pitch => math.asin(eye.y.clamp(-1.0, 1.0));

  /// 网页版预设的默认斜视角 (从柜底侧斜上方看)
  static IsoCamera defaultFor(ContainerResult c) {
    final d = math.sqrt(c.L * c.L + c.W * c.W + c.H * c.H);
    return IsoCamera(Vec3(d * 0.5, d * 0.42 - c.H / 2, d * 0.68));
  }

  IsoCamera copyWith({Vec3? dir, double? zoom, double? panX, double? panY}) =>
      IsoCamera(dir ?? eye, zoom: zoom ?? this.zoom, panX: panX ?? this.panX, panY: panY ?? this.panY);
}

/// 屏幕座标基底: e = 朝向摄影机, right = 画面右方, up = 画面上方 (正对顶视时改用 -Z 当「上」避免退化)
class _Basis {
  _Basis._(this.e, this.right, this.up);
  factory _Basis(Vec3 e) {
    final ref = e.y.abs() > 0.98 ? const Vec3(0, 0, -1) : const Vec3(0, 1, 0);
    final r = ref.cross(e).unit;
    return _Basis._(e, r, e.cross(r).unit);
  }
  final Vec3 e, right, up;
}

class _Face {
  _Face(this.pts, this.depth, this.fill, this.stroke);
  final List<Pt> pts;
  final double depth;
  final int fill;
  final int? stroke;
}

class _Block {
  _Block(this.alloc, this.index, this.x0, this.z0);
  final Allocation alloc;
  final int index;
  final double x0, z0; // 区块起点 (世界坐标)
}

const _light = Vec3(0.35, 0.85, 0.4);

// 6 个面: 法线 + 4 个角 (相对方块原点的 0/1 系数, 依序绕一圈)
const _faceDefs = <(Vec3, List<(int, int, int)>)>[
  (Vec3(1, 0, 0), [(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)]),
  (Vec3(-1, 0, 0), [(0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0)]),
  (Vec3(0, 1, 0), [(0, 1, 0), (0, 1, 1), (1, 1, 1), (1, 1, 0)]),
  (Vec3(0, -1, 0), [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)]),
  (Vec3(0, 0, 1), [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)]),
  (Vec3(0, 0, -1), [(0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0)]),
];

/// 该货柜里最多可见多边形数 (测试/性能评估用)
int lastPolygonCount = 0;

/// 装柜进度视图: 已装的箱子呈灰色, 正在装的这一列用物品颜色高亮, 还没装的不画 (货柜是从柜底往柜门装的)
class LoadView {
  const LoadView(this.allocIndex, this.column);
  final int allocIndex, column;

  // 0 = 还没装, 1 = 已装, 2 = 正在装
  int stateOf(int alloc, int col) {
    if (alloc > allocIndex) return 1;
    if (alloc < allocIndex) return 0;
    if (col > column) return 1;
    return col == column ? 2 : 0;
  }
}

int _muted(int argb) {
  // 往浅灰混合: 已装好的货退到背景, 视线集中在正在装的那一列
  int mix(int v, int g) => (v * 0.3 + g * 0.7).round();
  return 0xFF000000 | (mix((argb >> 16) & 0xFF, 0xB8) << 16) | (mix((argb >> 8) & 0xFF, 0xC2) << 8) | mix(argb & 0xFF, 0xCC);
}

/// 工人站在柜门往里看的视角
IsoCamera doorCamera(ContainerResult c) => IsoCamera(const Vec3(-0.75, 0.5, 0.5));

/// focus: 只高亮某个区块 (其余淡化, 混装柜的「各物品区块特写」用); labels: 是否画角落数字; load: 装柜进度
DrawList renderIso(
  ContainerResult c,
  IsoCamera cam, {
  double w = 840,
  double h = 600,
  int? focus,
  bool labels = true,
  bool background = true,
  LoadView? load,
  double xShift = 0, // 把所有货物沿柜长往柜底方向平移 (cm)
}) {
  final out = DrawList(w, h);
  if (background) out.rect(0, 0, w, h, fill: 0xFFF5F7FA);
  final bs = _Basis(cam.eye);
  final L = c.L, W = c.W, H = c.H;

  // ---- 取景: 把要显示的点集合 (整柜 8 角, 或被聚焦区块的 8 角) 投影后缩放到画面内 ----
  final fitPts = <Vec3>[];
  void addBox(double x0, double y0, double z0, double x1, double y1, double z1) {
    for (final x in [x0, x1]) {
      for (final y in [y0, y1]) {
        for (final z in [z0, z1]) {
          fitPts.add(Vec3(x, y, z));
        }
      }
    }
  }

  if (focus != null && focus >= 0 && focus < c.allocations.length) {
    final a = c.allocations[focus];
    final sx = -L / 2 + a.startLength;
    addBox(sx, 0, -a.blockWidth / 2, sx + a.lengthUsed, a.blockHeight, a.blockWidth / 2);
  } else {
    addBox(-L / 2, 0, -W / 2, L / 2, H, W / 2);
  }
  var minX = double.infinity, maxX = -double.infinity, minY = double.infinity, maxY = -double.infinity;
  for (final p in fitPts) {
    final sx = p.dot(bs.right), sy = p.dot(bs.up);
    minX = math.min(minX, sx);
    maxX = math.max(maxX, sx);
    minY = math.min(minY, sy);
    maxY = math.max(maxY, sy);
  }
  final pad = 0.9;
  final spanX = math.max(maxX - minX, 1e-6), spanY = math.max(maxY - minY, 1e-6);
  final scale = math.min(w * pad / spanX, h * pad / spanY) * cam.zoom;
  final cx = w / 2 + cam.panX - (minX + maxX) / 2 * scale;
  final cy = h / 2 + cam.panY + (minY + maxY) / 2 * scale;
  Pt proj(Vec3 p) => Pt(cx + p.dot(bs.right) * scale, cy - p.dot(bs.up) * scale);
  double depthOf(Vec3 p) => p.dot(bs.e);

  // ---- 地板与货柜边框 (后方的边先画, 前方的边最后画) ----
  out.cmds.add(Poly([proj(Vec3(-L / 2, 0, -W / 2)), proj(Vec3(L / 2, 0, -W / 2)), proj(Vec3(L / 2, 0, W / 2)), proj(Vec3(-L / 2, 0, W / 2))],
      fill: 0x99DBDFE6));
  final corners = <Vec3>[
    for (final x in [-L / 2, L / 2]) for (final y in [0.0, H]) for (final z in [-W / 2, W / 2]) Vec3(x, y, z),
  ];
  final edges = <(int, int)>[];
  for (var i = 0; i < 8; i++) {
    for (var j = i + 1; j < 8; j++) {
      final diff = (i ^ j);
      if (diff == 1 || diff == 2 || diff == 4) edges.add((i, j));
    }
  }
  final centerDepth = 0.0;
  final back = <Cmd>[], front = <Cmd>[];
  for (final (i, j) in edges) {
    final mid = (corners[i] + corners[j]) * 0.5;
    final isFront = depthOf(mid) > centerDepth;
    (isFront ? front : back).add(Line(proj(corners[i]), proj(corners[j]), color: isFront ? 0xFF1B2A3A : 0x661B2A3A, width: 1));
  }
  out.cmds.addAll(back);

  // ---- 物品区块 (由远到近) ----
  final blocks = <_Block>[];
  for (var i = 0; i < c.allocations.length; i++) {
    final a = c.allocations[i];
    blocks.add(_Block(a, i, -L / 2 + a.startLength + xShift, -a.blockWidth / 2));
  }
  double blockDepth(_Block b) {
    final a = b.alloc;
    return depthOf(Vec3(b.x0 + a.lengthUsed / 2, a.blockHeight / 2, 0));
  }

  blocks.sort((p, q) => blockDepth(p).compareTo(blockDepth(q)));
  var polyCount = 0;
  for (final b in blocks) {
    final faded = focus != null && b.index != focus;
    final faces = _shellFaces(b, bs, proj, depthOf, faded, load);
    faces.sort((p, q) => p.depth.compareTo(q.depth));
    for (final f in faces) {
      out.cmds.add(Poly(f.pts, fill: f.fill, stroke: f.stroke, strokeWidth: 0.6));
    }
    polyCount += faces.length;
  }
  lastPolygonCount = polyCount;

  out.cmds.addAll(front);

  // ---- 角落数字: 区块顶部 = 直排层数, 远端 = 深度列数, 近端 = 横排数 ----
  if (labels) {
    for (final b in blocks) {
      if (focus != null && b.index != focus) continue;
      final a = b.alloc;
      final ls = a.boxH * 0.4 < 14 ? 14.0 : (a.boxH * 0.4 > 32 ? 32.0 : a.boxH * 0.4);
      final bw = a.blockWidth, bh = a.blockHeight, depth = a.depthUnit;
      final fs = math.max(10.0, math.min(14.0, scale * ls * 0.9));
      out.cmds.add(Badge(proj(Vec3(b.x0 + depth * 0.5, bh + ls * 0.6, b.z0 + bw / 2)).x, proj(Vec3(b.x0 + depth * 0.5, bh + ls * 0.6, b.z0 + bw / 2)).y, '${a.vertical}', fs, a.color));
      final pc = proj(Vec3(b.x0 + a.columns * depth - depth * 0.5, bh * 0.5, b.z0 + bw + ls * 0.7));
      out.cmds.add(Badge(pc.x, pc.y, '${a.columns}', fs, a.color));
      final ph = proj(Vec3(b.x0 + depth * 0.5, bh * 0.5, b.z0 - ls * 0.7));
      out.cmds.add(Badge(ph.x, ph.y, '${a.horizontal}', fs, a.color));
    }
  }
  return out;
}

List<_Face> _shellFaces(_Block b, _Basis bs, Pt Function(Vec3) proj, double Function(Vec3) depthOf, bool faded, LoadView? load) {
  final a = b.alloc;
  final C = a.columns, V = a.vertical, hCount = a.horizontal;
  final count = math.min(a.boxesPlaced, a.fullGrid);
  final dx = a.depthUnit, dy = a.boxH, dz = a.widthUnit;

  // 只处理摄影机看得到的方向
  final dirs = <int>[];
  for (var i = 0; i < _faceDefs.length; i++) {
    if (_faceDefs[i].$1.dot(bs.e) > 1e-6) dirs.add(i);
  }
  bool occupied(int c, int v, int h) {
    if (c < 0 || v < 0 || h < 0 || c >= C || v >= V || h >= hCount) return false;
    if (load != null && load.stateOf(b.index, c) == 0) return false;
    return c * (V * hCount) + v * hCount + h < count;
  }

  final faces = <_Face>[];
  final base = faded ? withAlpha(a.color, 0.08) : a.color;
  for (var c = 0; c < C; c++) {
    final st = load?.stateOf(b.index, c);
    if (st == 0) continue;
    final cellBase = st == 1 ? _muted(a.color) : base;
    final edge = st == 2 ? 0xCC000000 : (faded ? null : 0x40000000);
    for (var v = 0; v < V; v++) {
      for (var h = 0; h < hCount; h++) {
        final idx = c * (V * hCount) + v * hCount + h;
        if (idx >= count) break;
        for (final di in dirs) {
          final n = _faceDefs[di].$1;
          if (occupied(c + n.x.toInt(), v + n.y.toInt(), h + n.z.toInt())) continue; // 被邻箱挡住的面不画
          final ox = b.x0 + c * dx, oy = v * dy, oz = b.z0 + h * dz;
          final pts = <Pt>[];
          var dsum = 0.0;
          for (final (kx, ky, kz) in _faceDefs[di].$2) {
            final p = Vec3(ox + kx * dx, oy + ky * dy, oz + kz * dz);
            pts.add(proj(p));
            dsum += depthOf(p);
          }
          final lit = (0.62 + 0.38 * math.max(0.0, n.dot(_light.unit))).toDouble();
          faces.add(_Face(pts, dsum / 4, shade(cellBase, lit), edge));
        }
      }
    }
  }
  return faces;
}

/// 视角合集的角度定义 (与网页版 6 个固定视角相同)
class ViewPointDef {
  const ViewPointDef(this.label, this.dir);
  final String label;
  final Vec3 dir;
}

List<ViewPointDef> overviewViewpoints(ContainerResult c) {
  final d = math.sqrt(c.L * c.L + c.W * c.W + c.H * c.H);
  final cy = c.H / 2;
  Vec3 v(double x, double y, double z) => Vec3(x, y - cy, z);
  return [
    ViewPointDef('View Point-1 · 门侧左前等角 Door-Left', v(-d * 0.5, d * 0.42, d * 0.68)),
    ViewPointDef('View Point-2 · 门侧右前等角 Door-Right', v(-d * 0.5, d * 0.42, -d * 0.68)),
    ViewPointDef('View Point-3 · 顶视 Top-Down', v(0.01, d * 0.98, 0.01)),
    ViewPointDef('View Point-4 · 柜门正视 Door-End', v(-d * 0.95, d * 0.22, 0.01)),
    ViewPointDef('View Point-5 · 柜底正视 Far-End', v(d * 0.95, d * 0.22, 0.01)),
    ViewPointDef('View Point-6 · 右侧视 Right Side', v(0.01, d * 0.22, d * 0.95)),
  ];
}

/// 混装柜某个区块的 3 个特写角度
List<ViewPointDef> closeupViewpoints(ContainerResult c, int idx) {
  final a = c.allocations[idx];
  final blockDiag = math.sqrt(a.lengthUsed * a.lengthUsed + a.blockWidth * a.blockWidth + a.blockHeight * a.blockHeight);
  final dist = math.max(blockDiag * 1.35, 60.0);
  final head = 'Section ${idx + 1} · ${a.name}';
  return [
    ViewPointDef('$head · 门侧斜视 Door-side', Vec3(-dist * 0.6, dist * 0.5, dist * 0.65)),
    ViewPointDef('$head · 顶视 Top plan', Vec3(0.01, dist * 1.05, 0.01)),
    ViewPointDef('$head · 右侧剖视 Side', Vec3(0, 0, dist * 1.05)),
  ];
}

const closeupAngleLabels = ['门侧斜视 Door-side', '顶视 Top plan', '右侧视 Side'];

String sectionTitle(SectionInfo i) =>
    'Section ${i.section} · ${i.name}   —   ${fmt(i.pcsPerBox)} PCS/box · ${i.boxes} boxes · ${fmt(i.pcs)} PCS · H${i.horizontal}xV${i.vertical}xDepth${i.columns}';
