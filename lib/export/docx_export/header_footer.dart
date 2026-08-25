import 'docx_options.dart';

/// 生成 `word/header1.xml` / `word/footer1.xml`(页眉页脚 part)。
///
/// 设计对齐 dev-doc.md 第 9.1 节目录结构 + Phase 5 页眉页脚(可选)。
///
/// 页眉页脚本质是"小型 document.xml",根元素为 `<w:hdr>` / `<w:ftr>`,
/// 内容为若干 `<w:p>`(段落),不含 sectPr。
///
/// 骨架版:
///   - 页眉:居中显示 [headerText](若为空则不显示段落)
///   - 页脚:居中显示 [footerText](同上)
///
/// 后续可加:页码字段(`<w:fldSimple w:instr="PAGE"/>`)、日期、作者等。
class HeaderFooterBuilder {
  /// 生成 `word/header1.xml`。
  static String header(DocxOptions options) {
    final text = options.headerText;
    final buf = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..writeln('<w:hdr xmlns:w='
          '"http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">');
    if (text != null && text.isNotEmpty) {
      buf.writeln('  <w:p><w:pPr><w:jc w:val="center"/></w:pPr>'
          '<w:r><w:rPr><w:sz w:val="18"/></w:rPr>'
          '<w:t xml:space="preserve">${_esc(text)}</w:t></w:r></w:p>');
    }
    buf.writeln('</w:hdr>');
    return buf.toString();
  }

  /// 生成 `word/footer1.xml`。
  static String footer(DocxOptions options) {
    final text = options.footerText;
    final buf = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..writeln('<w:ftr xmlns:w='
          '"http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">');
    if (text != null && text.isNotEmpty) {
      buf.writeln('  <w:p><w:pPr><w:jc w:val="center"/></w:pPr>'
          '<w:r><w:rPr><w:sz w:val="18"/></w:rPr>'
          '<w:t xml:space="preserve">${_esc(text)}</w:t></w:r></w:p>');
    }
    buf.writeln('</w:ftr>');
    return buf.toString();
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
