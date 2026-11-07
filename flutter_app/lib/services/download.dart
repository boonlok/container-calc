/// 浏览器相关操作 (下载 PDF、开新分页、选择图片)。非网页环境 (测试) 用 stub。
library;

export 'download_stub.dart' if (dart.library.js_interop) 'download_web.dart';
