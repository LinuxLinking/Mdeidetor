import 'dart:convert';
import 'dart:typed_data';

/// 图片源解析工具:从 md `![alt](src)` 的 [src] 解析出可嵌入 docx 的字节。
///
/// 设计对齐 dev-doc.md 第 9.9 节(边界情况:图片尺寸 / 图片为 URL)。
///
/// Phase 5 骨架支持的 src 形态:
///   - `data:image/png;base64,....` → 内嵌 base64 解码为 bytes + ext
///   - `data:image/jpeg;base64,....`
///   - `data:image/gif;base64,....`
///   - `data:image/bmp;base64,....`
///
/// 不支持(降级):
///   - `http://` / `https://` URL → 返回 null,document.xml 输出链接文本
///   - 本地相对路径 / file:// → 返回 null,同上
///
/// 后续迭代(Phase 6+):
///   - URL 下载(需 INTERNET 权限 + Isolate)
///   - SAF URI 读取(本地图片经 SAF 选中)
class ImageSource {
  final Uint8List bytes;
  final String ext; // png / jpeg / gif / bmp

  const ImageSource({required this.bytes, required this.ext});

  /// 从 src 解析;不可嵌入时返回 null。
  static ImageSource? parse(String src) {
    if (!src.startsWith('data:')) return null;
    final comma = src.indexOf(',');
    if (comma < 0) return null;
    final header = src.substring(5, comma); // "image/png;base64"
    final parts = header.split(';');
    final mime = parts.isNotEmpty ? parts.first : '';
    final ext = _extForMime(mime);
    if (ext == null) return null;
    final isBase64 = parts.any((p) => p == 'base64');
    if (!isBase64) return null; // URL-encoded data URI 暂不支持
    final b64 = src.substring(comma + 1);
    try {
      final bytes = base64.decode(b64);
      return ImageSource(bytes: Uint8List.fromList(bytes), ext: ext);
    } catch (_) {
      return null;
    }
  }

  static String? _extForMime(String mime) {
    switch (mime) {
      case 'image/png':
        return 'png';
      case 'image/jpeg':
      case 'image/jpg':
        return 'jpeg';
      case 'image/gif':
        return 'gif';
      case 'image/bmp':
        return 'bmp';
      default:
        return null;
    }
  }
}
