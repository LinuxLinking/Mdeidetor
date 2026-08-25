/// TOC(目录)字段生成器。
///
/// 设计对齐 dev-doc.md 第 9.6 节。
///
/// Word 打开时会提示"更新域",点确认后自动从 Heading1-3 生成目录。
/// 这是 OOXML 标准做法,无需手动遍历 AST。
class TocBuilder {
  /// 返回 TOC 字段段落 XML(`<w:p>...</w:p>`),插入到 document.xml 顶部。
  ///
  /// `\o "1-3"` 表示使用 Heading1-3 作为目录条目;`\h` 超链接;`\z` 隐藏页码
  /// 在 Web 视图;`\u` 使用大纲级别。
  static String buildParagraph({String caption = '目录'}) {
    return '<w:p>'
        '<w:r><w:t xml:space="preserve">${_esc(caption)}</w:t></w:r>'
        '</w:p>'
        '<w:p>'
        '<w:r><w:fldChar w:fldCharType="begin"/></w:r>'
        '<w:r><w:instrText xml:space="preserve">TOC \\o "1-3" \\h \\z \\u</w:instrText></w:r>'
        '<w:r><w:fldChar w:fldCharType="separate"/></w:r>'
        '<w:r><w:t xml:space="preserve">右键 → 更新域 以生成目录</w:t></w:r>'
        '<w:r><w:fldChar w:fldCharType="end"/></w:r>'
        '</w:p>';
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
