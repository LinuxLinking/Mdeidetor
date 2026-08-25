import 'dart:typed_data';

import 'docx_options.dart';

/// 图片资源收集器:在 [DocumentXmlBuilder] 遍历 AST 时收集图片字节,
/// 在 [DocxGenerator] 生成阶段统一输出到 `word/media/`。
///
/// 设计参见 dev-doc.md 第 9.7 节 `MediaCollector`。
///
/// 去重:首版按 [src] 字符串去重(同一 URL 复用同一 rId)。
/// 后续可改为按内容哈希去重(见 dev-doc 第 9.9 节)。
class MediaCollector {
  final Map<String, MediaEntry> _bySrc = {};
  final List<MediaEntry> _entries = [];

  List<MediaEntry> get entries => List.unmodifiable(_entries);

  /// 注册一张图片,返回其在 `word/media/` 内的文件名(`imageN.png` 等)。
  /// 同一 [src] 复用同一文件名(去重)。
  String register(String src, Uint8List bytes, {String ext = 'png'}) {
    final existing = _bySrc[src];
    if (existing != null) return existing.filename;
    final n = _entries.length + 1;
    final filename = 'image$n.$ext';
    final entry = MediaEntry(
      filename: filename,
      mimeType: _mimeForExt(ext),
      bytes: bytes,
    );
    _bySrc[src] = entry;
    _entries.add(entry);
    return filename;
  }

  /// 按 src 查询已注册的文件名(未注册返回 null)。
  String? filenameFor(String src) => _bySrc[src]?.filename;

  String _mimeForExt(String ext) {
    switch (ext.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'bmp':
        return 'image/bmp';
      default:
        return 'application/octet-stream';
    }
  }
}
