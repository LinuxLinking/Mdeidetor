import 'dart:typed_data';

/// DOCX 生成选项。
///
/// 设计参见 dev-doc.md 第 9.7 节 `DocxOptions`。
class DocxOptions {
  /// 西文字体(默认 Calibri)。
  final String asciiFont;

  /// 东亚字体(默认宋体,中文渲染关键)。
  final String eastAsiaFont;

  /// 等宽字体(代码块 / 行内 code)。
  final String monoFont;

  /// 默认正文字号(半磅,22 = 11pt)。
  final int defaultSize;

  /// 是否包含页眉页脚。
  final bool includeHeaderFooter;

  /// 页眉文本(仅 [includeHeaderFooter] 为 true 时生效)。
  final String? headerText;

  /// 页脚文本(同上)。
  final String? footerText;

  /// 是否包含 TOC(目录)字段。
  final bool includeToc;

  const DocxOptions({
    this.asciiFont = 'Calibri',
    this.eastAsiaFont = '宋体',
    this.monoFont = 'Consolas',
    this.defaultSize = 22,
    this.includeHeaderFooter = false,
    this.headerText,
    this.footerText,
    this.includeToc = false,
  });

  /// 默认配置:中文宋体 + 西文 Calibri + 代码 Consolas。
  factory DocxOptions.defaultOptions() => const DocxOptions();
}

/// 图片资源条目(对应 `word/media/imageN.*`)。
class MediaEntry {
  final String filename; // image1.png
  final String mimeType; // image/png
  final Uint8List bytes;

  const MediaEntry({
    required this.filename,
    required this.mimeType,
    required this.bytes,
  });
}
