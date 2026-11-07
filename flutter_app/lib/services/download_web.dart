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
