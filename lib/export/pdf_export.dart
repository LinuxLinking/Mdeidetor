import 'package:flutter/services.dart';

/// PDF 导出器:通过 Android `PrintManager` 把 HTML 发到系统打印对话框。
///
/// 设计参见 dev-doc.md 第 7.5 节(Dart 侧)+ 第 10 节(Kotlin 侧)。
///
/// 流程:
///   1. EditorPage 调用 `_editor.getHTML()` 取渲染后的 HTML 片段
///   2. [printHtml] 把片段包裹为完整 HTML 文档 + 注入打印 CSS
///   3. MethodChannel(`mdeditor/print`)传给 Kotlin 侧 `PrintChannel.printHtml`
///   4. Kotlin 创建离线 WebView,`loadDataWithBaseURL` 加载 HTML,
///      `onPageFinished` 时调 `createPrintDocumentAdapter(jobName)`
///      交给 `PrintManager.print`(A4 / 300dpi / 无边距)
///   5. 系统弹出打印对话框,用户选"保存为 PDF"或打印机
class PdfExporter {
  static const MethodChannel _channel = MethodChannel('mdeditor/print');

  /// 调用系统打印对话框。
  ///
  /// [htmlFragment] 是渲染后的 HTML 片段(如 `<h1>...</h1><p>...</p>`),
  /// 本方法内部会包裹为完整 HTML 文档并注入打印 CSS。
  /// [jobName] 是打印任务名 / 默认 PDF 文件名。
  static Future<void> printHtml(
    String htmlFragment, {
    String jobName = 'Mdeditor Document',
  }) async {
    final fullHtml = _wrapHtml(htmlFragment, jobName);
    await _channel.invokeMethod('printHtml', {
      'html': fullHtml,
      'jobName': jobName,
    });
  }

  /// 把 HTML 片段包裹为完整 HTML 文档 + 注入打印 CSS。
  ///
  /// 打印 CSS 参见 dev-doc.md 第 10.4 节:页面边距、表格边框、代码块背景、
  /// 标题不分页、代码/表格不被页内打断。
  static String _wrapHtml(String fragment, String title) {
    return '''<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${_escape(title)}</title>
  <style>$_printCss</style>
</head>
<body>
$fragment
</body>
</html>''';
  }

  /// HTML 转义(用于 title 等)。
  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  /// 打印专用 CSS(dev-doc.md 第 10.4 节)。
  static const String _printCss = r'''
@media print {
  body {
    font-family: -apple-system, "Segoe UI", "Microsoft YaHei", sans-serif;
    margin: 24pt;
    color: #1a1a1a;
    line-height: 1.6;
  }
  pre, code {
    font-family: "JetBrains Mono", "Cascadia Code", Consolas, monospace;
    background: #f5f5f5;
  }
  pre {
    padding: 8pt;
    border-radius: 4pt;
    overflow-x: auto;
  }
  code {
    padding: 1pt 3pt;
    border-radius: 2pt;
  }
  table {
    border-collapse: collapse;
    width: 100%;
  }
  th, td {
    border: 1px solid #ccc;
    padding: 4pt 8pt;
    text-align: left;
  }
  h1, h2, h3, h4, h5, h6 {
    page-break-after: avoid;
    margin-top: 16pt;
  }
  pre, table, figure, blockquote {
    page-break-inside: avoid;
  }
  img {
    max-width: 100%;
    page-break-inside: avoid;
  }
  a {
    color: #0366d6;
    text-decoration: none;
  }
  blockquote {
    border-left: 3pt solid #ccc;
    margin: 0;
    padding-left: 12pt;
    color: #555;
  }
}
''';
}
