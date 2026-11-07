/// 把货柜计划交给工人: 二维码 / 链接
library;

import 'package:barcode/barcode.dart';
import 'package:flutter/material.dart';

import '../core/models.dart';
import '../services/download.dart';
import '../services/share_link.dart';
import '../state/app_state.dart';
import 'theme.dart';

/// 二维码容量上限 (低纠错、字节模式); 超过就只给链接
const qrMaxChars = 2800;

class QrView extends StatelessWidget {
  const QrView(this.data, {super.key, this.size = 240});
  final String data;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _QrPainter(data)),
      );
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.data);
  final String data;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF000000)
      ..isAntiAlias = false;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    // 每个模块对齐到整数像素: 小数像素会把边缘画糊, 相机就扫不出来了
    final bars = Barcode.qrCode(errorCorrectLevel: BarcodeQRCorrectionLevel.low)
        .make(data, width: 1000, height: 1000)
        .whereType<BarcodeBar>()
        .where((b) => b.black)
        .toList();
    if (bars.isEmpty) return;
    final module = bars.map((b) => b.height < b.width ? b.height : b.width).reduce((a, b) => a < b ? a : b);
    final count = (1000 / module).round();
    final px = (size.width / count).floorToDouble();
    final off = ((size.width - px * count) / 2).floorToDouble();
    for (final b in bars) {
      canvas.drawRect(
        Rect.fromLTWH(off + (b.left / module).round() * px, off + (b.top / module).round() * px, (b.width / module).round() * px, (b.height / module).round() * px),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_QrPainter oldDelegate) => oldDelegate.data != data;
}

Future<void> showWorkerShareDialog(BuildContext context, AppState state, ContainerResult c, int unit, int total) {
  final link = workerLink(Uri.base, c, unit, total);
  final canQr = link.length <= qrMaxChars;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('交给工人：货柜 $unit Give to workers: Unit $unit', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 340,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (canQr)
            Container(
              key: const ValueKey('workerQr'),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(12)),
              child: QrView(link, size: 300),
            )
          else
            const Text('这个货柜的物品太多，放不进二维码，请用下面的链接。 Too many items for a QR code, please share the link.', style: TextStyle(color: redErr, fontSize: 13)),
          const SizedBox(height: 12),
          const Text('工人用手机相机扫码就能照着装，不用登入。进度保存在工人自己的手机上，不会同步给别人。\nWorkers scan with a phone camera, no login. Progress stays on that phone and is not shared.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: textSecondary, height: 1.5)),
          const SizedBox(height: 6),
          const Text('链接里有柜型和物品名称，但没有客户和公司资料。 The link contains item names, not customer details.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: textSecondary)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭 Close')),
        FilledButton.icon(
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('复制链接 Copy Link'),
          onPressed: () async {
            final ok = await copyToClipboard(link);
            state.toast(ok ? '链接已复制 Link copied ✓' : '无法复制，请改用二维码 Could not copy, please use the QR code', error: !ok);
          },
        ),
      ],
    ),
  );
}
