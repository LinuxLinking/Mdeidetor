import 'media.dart';

/// 生成 `[Content_Types].xml`:声明 docx 内各 part 的 MIME 类型。
///
/// 设计参见 dev-doc.md 第 9.1 / 9.7 节。
///
/// 必含:
///   - Default: rels / xml
///   - Override: /word/document.xml、/word/styles.xml、/word/numbering.xml
/// 含图片时按扩展名加 Default: png / jpeg / gif / bmp
/// 含页眉页脚时加 Override: /word/header1.xml、/word/footer1.xml
class ContentTypesXmlBuilder {
  final MediaCollector mediaCollector;
  final bool includeHeaderFooter;

  ContentTypesXmlBuilder(
    this.mediaCollector, {
    this.includeHeaderFooter = false,
  });

  String build() {
    final buf = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..writeln('<Types xmlns='
          '"http://schemas.openxmlformats.org/package/2006/content-types">')
      ..writeln('  <Default Extension="rels" '
          'ContentType="application/vnd.openxmlformats-package.relationships+xml"/>')
      ..writeln('  <Default Extension="xml" '
          'ContentType="application/xml"/>');

    // 图片扩展名(去重)
    final exts = <String>{};
    for (final e in mediaCollector.entries) {
      final dot = e.filename.lastIndexOf('.');
      if (dot >= 0) exts.add(e.filename.substring(dot + 1).toLowerCase());
    }
    for (final ext in exts) {
      final mime = _mimeForExt(ext);
      buf.writeln('  <Default Extension="$ext" ContentType="$mime"/>');
    }

    buf.writeln('  <Override PartName="/word/document.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>');
    buf.writeln('  <Override PartName="/word/styles.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>');
    buf.writeln('  <Override PartName="/word/numbering.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>');
    if (includeHeaderFooter) {
      buf.writeln('  <Override PartName="/word/header1.xml" '
          'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>');
      buf.writeln('  <Override PartName="/word/footer1.xml" '
          'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>');
    }
    buf.writeln('</Types>');
    return buf.toString();
  }

  String _mimeForExt(String ext) {
    switch (ext) {
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
