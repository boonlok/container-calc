/// 可拖曳旋转、滚轮缩放的 3D 视图。只有在互动时才重新产生画面 (平时不耗 CPU/GPU)。
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/models.dart';
import '../render/iso.dart';
import 'draw_view.dart';
import 'theme.dart';

class IsoView extends StatefulWidget {
  const IsoView(this.container, {super.key, this.height = 320});
  final ContainerResult container;
  final double height;

  @override
  State<IsoView> createState() => _IsoViewState();
}

class _IsoViewState extends State<IsoView> {
  late double yaw, pitch;
  double zoom = 1;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(IsoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.container, widget.container)) _reset();
  }

  void _reset() {
    final c = IsoCamera.defaultFor(widget.container);
    yaw = c.yaw;
    pitch = c.pitch;
    zoom = 1;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth, h = widget.height;
        final list = renderIso(widget.container, IsoCamera.fromAngles(yaw, pitch, zoom: zoom), w: w, h: h);
        return Listener(
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) {
              GestureBinding.instance.pointerSignalResolver.register(e, (_) {
                setState(() => zoom = (zoom * (e.scrollDelta.dy > 0 ? 0.9 : 1.1)).clamp(0.3, 8.0));
              });
            }
          },
          child: GestureDetector(
            onPanUpdate: (d) => setState(() {
              yaw -= d.delta.dx * 0.01;
              pitch = (pitch + d.delta.dy * 0.01).clamp(-0.05, math.pi / 2 - 0.02);
            }),
            onDoubleTap: () => setState(_reset),
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Stack(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(width: w, height: h, child: CustomPaint(painter: DrawListPainter(list))),
                ),
                Positioned(
                  right: 8,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(3)),
                    child: const Text('拖曳旋转 · 滚轮缩放 · 双击还原 Drag / Scroll / Double-click', style: TextStyle(fontSize: 10, color: textSecondary)),
                  ),
                ),
              ]),
            ),
          ),
        );
      });
}
