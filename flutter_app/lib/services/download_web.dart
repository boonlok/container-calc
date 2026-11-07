import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

String _blobUrl(Uint8List bytes) {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: 'application/pdf'));
  return web.URL.createObjectURL(blob);
}

void downloadPdf(Uint8List bytes, String filename) {
  final url = _blobUrl(bytes);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  web.document.body?.append(a);
  a.click();
  a.remove();
  Timer(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
}

void openPdfInNewTab(Uint8List bytes) {
  web.window.open(_blobUrl(bytes), '_blank');
}

Future<Uint8List?> pickImageBytes() {
  final done = Completer<Uint8List?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = 'image/*';
  input.onchange = ((web.Event _) {
    final file = input.files?.item(0);
    if (file == null) {
      done.complete(null);
      return;
    }
    file.arrayBuffer().toDart.then((buf) => done.complete(buf.toDart.asUint8List()), onError: (_) => done.complete(null));
  }).toJS;
  input.click();
  return done.future;
}

/// 装柜时屏幕不要自动熄灭 (浏览器不支援就算了)
void keepScreenOn() {
  try {
    web.window.navigator.wakeLock.request('screen').toDart.then((_) {}, onError: (_) {});
  } catch (_) {/* 不支援 */}
}

Future<bool> copyToClipboard(String text) async {
  try {
    await web.window.navigator.clipboard.writeText(text).toDart;
    return true;
  } catch (_) {
    return false;
  }
}

Future<Uint8List?> pickTextFile() {
  final done = Completer<Uint8List?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.csv,.txt,.tsv,text/csv,text/plain';
  input.onchange = ((web.Event _) {
    final file = input.files?.item(0);
    if (file == null) {
      done.complete(null);
      return;
    }
    file.arrayBuffer().toDart.then((buf) => done.complete(buf.toDart.asUint8List()), onError: (_) => done.complete(null));
  }).toJS;
  input.click();
  return done.future;
}

/// 页面被隐藏 (切到别的分页、关掉、重新整理) 时呼叫: 用来自动保存草稿
void onPageHide(void Function() callback) {
  web.document.addEventListener('visibilitychange', ((web.Event _) {
    if (web.document.visibilityState == 'hidden') callback();
  }).toJS);
  web.window.addEventListener('pagehide', ((web.Event _) => callback()).toJS);
}
