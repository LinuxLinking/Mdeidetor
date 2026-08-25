import '../../md_ast/ast.dart';
import 'docx_options.dart';
import 'image_source.dart';
import 'media.dart';
import 'rels.dart';
import 'toc.dart';

/// 生成 `word/document.xml`:遍历 AST 输出 OOXML 段落 + 行内元素。
///
/// 设计对齐 dev-doc.md 第 9.3 节映射表。
///
/// 节点映射:
///   - 块级:Heading / Paragraph / BulletList / OrderedList / CodeBlock /
///           BlockQuote / Table / ThematicBreak / Image(降级)
///   - 行内:Text / Emphasis / Strong / Code / Link / HardBreak /
///           SoftBreak(省略) / Math(降级)
class DocumentXmlBuilder {
  final DocxOptions options;
  final MediaCollector mediaCollector;
  final RelsCollector relsCollector;

  DocumentXmlBuilder(this.options, this.mediaCollector, this.relsCollector);

  /// 主入口:Document AST → word/document.xml 完整字符串。
  ///
  /// 若 [DocxOptions.includeToc] 为 true,在 body 顶部插入 TOC 字段段落。
  /// 若 [DocxOptions.includeHeaderFooter] 为 true,在 sectPr 内引用
  /// header1.xml / footer1.xml(其 rId 由 [RelsCollector] 注册)。
  String build(Document ast) {
    final body = StringBuffer();
    if (options.includeToc) {
      body.write(TocBuilder.buildParagraph());
    }
    for (final child in ast.children) {
      body.write(_block(child, ilvl: 0));
    }
    final sectPr = StringBuffer()
      ..writeln('<w:sectPr>')
      ..writeln('<w:pgSz w:w="11906" w:h="16838"/>') // A4 纵向 twip
      ..writeln('<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>');
    if (options.includeHeaderFooter) {
      final headerRId = relsCollector.register(
        target: 'header1.xml',
        type: 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/header',
      );
      final footerRId = relsCollector.register(
        target: 'footer1.xml',
        type: 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer',
      );
      sectPr.writeln('<w:headerReference w:type="default" r:id="$headerRId"/>');
      sectPr.writeln('<w:footerReference w:type="default" r:id="$footerRId"/>');
    }
    sectPr.writeln('</w:sectPr>');
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
        '<w:body>$body$sectPr'
        '</w:body></w:document>';
  }

  // ─── 块级节点 ──────────────────────────────────────────────

  String _block(MdNode node, {required int ilvl}) {
    switch (node) {
      case Heading(:final level, :final children):
        return '<w:p><w:pPr><w:pStyle w:val="Heading$level"/></w:pPr>'
            '${_inlines(children)}</w:p>';
      case Paragraph(:final children):
        return '<w:p>${_inlines(children)}</w:p>';
      case BulletList(:final items):
        return items.map((i) => _listItem(i, numId: 1, ilvl: ilvl)).join();
      case OrderedList(:final items):
        // 首版忽略 start(>1 时),由 numbering.xml 自增
        return items.map((i) => _listItem(i, numId: 2, ilvl: ilvl)).join();
      case ListItem():
        // 不应直接遇到 ListItem(被 BulletList/OrderedList 处理);防御性兜底
        return '';
      case CodeBlock(:final language, :final code):
        return _codeBlock(language, code);
      case BlockQuote(:final children):
        // 块引用:把内部块级节点加 Quote 样式后输出
        final buf = StringBuffer();
        for (final c in children) {
          // 仅段落 + 标题加 Quote 样式,其他原样输出
          if (c is Paragraph) {
            buf.write('<w:p><w:pPr><w:pStyle w:val="Quote"/></w:pPr>'
                '${_inlines(c.children)}</w:p>');
          } else if (c is Heading) {
            buf.write('<w:p><w:pPr><w:pStyle w:val="Quote"/></w:pPr>'
                '${_inlines(c.children)}</w:p>');
          } else {
            buf.write(_block(c, ilvl: 0));
          }
        }
        return buf.toString();
      case Table(:final rows, :final alignments):
        return _table(rows, alignments);
      case ThematicBreak():
        return '<w:p><w:pPr><w:pBdr>'
            '<w:bottom w:val="single" w:sz="6" w:space="1" w:color="auto"/>'
            '</w:pBdr></w:pPr></w:p>';
      case Image(:final src, :final alt):
        return _imageParagraph(src, alt);
      case TaskList(:final items):
        // 任务列表:复选框 + 文本,继承 ListParagraph 缩进
        return items.map((i) => _taskItem(i)).join();
      case TaskListItem():
        // 兜底:不应直接遇到(被 TaskList 处理)
        return '';
      case Document():
        return ''; // 不应直接遇到
    }
  }

  /// 生成图片段落(`<w:p>...<w:drawing>...</w:drawing></w:p>`)。
  ///
  /// 设计对齐 dev-doc.md 第 9.3 节 Image 行 + 第 9.9 节。
  ///
  /// 流程:
  ///   1. [ImageSource.parse] 解析 src(data URI base64)
  ///   2. 成功:[MediaCollector.register] 注册 media → filename;
  ///      [RelsCollector.register] 注册 image relationship → rId;
  ///      输出 `<w:drawing><wp:inline>...<a:blip r:embed="rId"/>...</wp:inline></w:drawing>`
  ///   3. 失败(URL / 本地路径):降级为"[alt](src)"链接文本段落
  String _imageParagraph(String src, String? alt) {
    final source = ImageSource.parse(src);
    if (source == null) {
      // 降级:图片不可嵌入,输出链接文本
      final altText = alt ?? '';
      return '<w:p><w:pPr><w:jc w:val="center"/></w:pPr>'
          '<w:r><w:rPr><w:i/><w:color w:val="666666"/></w:rPr>'
          '<w:t xml:space="preserve">[图片: ${_esc(altText)}] (${_esc(src)})</w:t>'
          '</w:r></w:p>';
    }
    final filename = mediaCollector.register(src, source.bytes, ext: source.ext);
    final rId = relsCollector.register(
      target: 'media/$filename',
      type: 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/image',
    );
    // 默认尺寸 200×150 pt(骨架版,未读图片真实宽高)
    // 1 pt = 12700 EMU(English Metric Unit)
    const cx = 200 * 12700; // 2540000
    const cy = 150 * 12700; // 1905000
    return '<w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r>'
        '<w:drawing>'
        '<wp:inline distT="0" distB="0" distL="0" distR="0">'
        '<wp:extent cx="$cx" cy="$cy"/>'
        '<wp:effectExtent l="0" t="0" r="0" b="0"/>'
        '<wp:docPr id="0" name="Picture"/>'
        '<wp:cNvGraphicFramePr>'
        '<a:graphicFrameLocks noChangeAspect="1"/>'
        '</wp:cNvGraphicFramePr>'
        '<a:graphic>'
        '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:nvPicPr>'
        '<pic:cNvPr id="0" name=""/>'
        '<pic:cNvPicPr/>'
        '</pic:nvPicPr>'
        '<pic:blipFill>'
        '<a:blip r:embed="$rId"/>'
        '<a:stretch><a:fillRect/></a:stretch>'
        '</pic:blipFill>'
        '<pic:spPr>'
        '<a:xfrm>'
        '<a:off x="0" y="0"/>'
        '<a:ext cx="$cx" cy="$cy"/>'
        '</a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom>'
        '</pic:spPr>'
        '</pic:pic>'
        '</a:graphicData>'
        '</a:graphic>'
        '</wp:inline>'
        '</w:drawing></w:r></w:p>';
  }

  /// 任务列表项:复选框符号 + 文本段落。
  ///
  /// 复选框使用 Unicode 字符 ☑(U+2611) / ☐(U+2610) 简化骨架版,
  /// 后续可改为 OOXML `<w:checkBox>` SDT 控件(更原生但复杂)。
  String _taskItem(TaskListItem item) {
    final mark = item.checked ? '\u2611' : '\u2610';
    final buf = StringBuffer();
    for (final child in item.children) {
      if (child is Paragraph) {
        buf.write('<w:p><w:pPr><w:pStyle w:val="ListParagraph"/></w:pPr>'
            '<w:r><w:t xml:space="preserve">${_esc(mark)} </w:t></w:r>'
            '${_inlines(child.children)}</w:p>');
      } else {
        buf.write(_block(child, ilvl: 0));
      }
    }
    return buf.toString();
  }

  String _listItem(ListItem item, {required int numId, required int ilvl}) {
    final buf = StringBuffer();
    for (final child in item.children) {
      if (child is BulletList) {
        // 嵌套无序列表:numId=1, ilvl+1
        buf.write(_block(child, ilvl: ilvl + 1));
      } else if (child is OrderedList) {
        buf.write(_block(child, ilvl: ilvl + 1));
      } else if (child is Paragraph) {
        buf.write('<w:p><w:pPr><w:pStyle w:val="ListParagraph"/>'
            '<w:numPr><w:ilvl w:val="$ilvl"/><w:numId w:val="$numId"/></w:numPr>'
            '</w:pPr>${_inlines(child.children)}</w:p>');
      } else {
        buf.write(_block(child, ilvl: ilvl));
      }
    }
    return buf.toString();
  }

  String _codeBlock(String? language, String code) {
    // 首版忽略 language,统一 SourceCode 样式 + 灰色底纹
    final lines = code.split('\n');
    final buf = StringBuffer();
    for (final line in lines) {
      buf.write('<w:p><w:pPr><w:pStyle w:val="SourceCode"/>'
          '<w:shd w:val="clear" w:color="auto" w:fill="F5F5F5"/>'
          '</w:pPr>'
          '<w:r><w:rPr><w:rFonts w:ascii="${options.monoFont}" '
          'w:hAnsi="${options.monoFont}" w:cs="${options.monoFont}"/></w:rPr>'
          '<w:t xml:space="preserve">${_esc(line)}</w:t></w:r></w:p>');
    }
    return buf.toString();
  }

  String _table(List<List<List<Inline>>> rows, List<int> alignments) {
    if (rows.isEmpty) return '';
    final cols = rows.first.length;
    final buf = StringBuffer()
      ..writeln('<w:tbl>')
      ..writeln('  <w:tblPr>')
      ..writeln('    <w:tblW w:w="0" w:type="auto"/>')
      ..writeln('    <w:tblBorders>'
          '<w:top w:val="single" w:sz="4" w:color="auto"/>'
          '<w:left w:val="single" w:sz="4" w:color="auto"/>'
          '<w:bottom w:val="single" w:sz="4" w:color="auto"/>'
          '<w:right w:val="single" w:sz="4" w:color="auto"/>'
          '<w:insideH w:val="single" w:sz="4" w:color="auto"/>'
          '<w:insideV w:val="single" w:sz="4" w:color="auto"/>'
          '</w:tblBorders>')
      ..writeln('  </w:tblPr>')
      ..writeln('  <w:tblGrid>');
    for (var c = 0; c < cols; c++) {
      buf.writeln('    <w:gridCol w:w="${(9000 ~/ cols)}"/>');
    }
    buf.writeln('  </w:tblGrid>');
    for (var r = 0; r < rows.length; r++) {
      buf.writeln('  <w:tr>');
      for (var c = 0; c < rows[r].length; c++) {
        final isHeader = r == 0;
        final align = c < alignments.length ? alignments[c] : -1;
        final jc = align == 0 ? 'center' : (align == 1 ? 'right' : 'left');
        buf.writeln('    <w:tc>'
            '<w:tcPr><w:tcW w:w="${(9000 ~/ cols)}" w:type="dxa"/>'
            '<w:jc w:val="$jc"/></w:tcPr>'
            '<w:p><w:pPr><w:jc w:val="$jc"/>'
            '${isHeader ? '<w:pStyle w:val="Heading6"/>' : ''}'
            '</w:pPr>${_inlines(rows[r][c])}</w:p>'
            '</w:tc>');
      }
      buf.writeln('  </w:tr>');
    }
    buf.writeln('</w:tbl>');
    // 表后空段(Word 表格规则)
    buf.writeln('<w:p/>');
    return buf.toString();
  }

  // ─── 行内节点 ──────────────────────────────────────────────

  String _inlines(List<Inline> inlines) {
    final buf = StringBuffer();
    for (final i in inlines) {
      buf.write(_inline(i));
    }
    return buf.toString();
  }

  String _inline(Inline node) {
    switch (node) {
      case Text(:final text):
        return '<w:r><w:t xml:space="preserve">${_esc(text)}</w:t></w:r>';
      case Emphasis(:final children):
        return '<w:r><w:rPr><w:i/></w:rPr>${_inlinesAsRuns(children)}</w:r>';
      case Strong(:final children):
        return '<w:r><w:rPr><w:b/></w:rPr>${_inlinesAsRuns(children)}</w:r>';
      case Code(:final code):
        return '<w:r><w:rPr>'
            '<w:rFonts w:ascii="${options.monoFont}" w:hAnsi="${options.monoFont}" w:cs="${options.monoFont}"/>'
            '<w:shd w:val="clear" w:color="auto" w:fill="F0F0F0"/>'
            '</w:rPr><w:t xml:space="preserve">${_esc(code)}</w:t></w:r>';
      case Link(:final href, :final children):
        final rId = relsCollector.register(
          target: href,
          type: 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink',
          targetMode: 'External',
        );
        return '<w:hyperlink r:id="$rId">'
            '<w:r><w:rPr><w:rStyle w:val="Hyperlink"/></w:rPr>'
            '${_inlinesAsRuns(children)}</w:r></w:hyperlink>';
      case HardBreak():
        return '<w:r><w:br/></w:r>';
      case SoftBreak():
        // 软换行首版省略(等同不换)
        return '';
      case Math(:final tex):
        // Phase 4 降级:数学公式以等宽字体显示 TeX 源码
        return '<w:r><w:rPr>'
            '<w:rFonts w:ascii="${options.monoFont}" w:hAnsi="${options.monoFont}"/>'
            '</w:rPr><w:t xml:space="preserve">${_esc(tex)}</w:t></w:r>';
      case ImageInline():
        // 行内图片在块级层已提升为 Image,这里兜底
        return '';
    }
  }

  /// 把行内节点递归输出为 `<w:r>` 串(不带 hyperlink 包裹,用于嵌套强调等)。
  String _inlinesAsRuns(List<Inline> inlines) {
    final buf = StringBuffer();
    for (final i in inlines) {
      switch (i) {
        case Text(:final text):
          buf.write('<w:t xml:space="preserve">${_esc(text)}</w:t>');
        case Emphasis(:final children):
          // 嵌套斜体:在外层 rPr 已有 i,这里只输出文本
          buf.write(_inlinesAsRuns(children));
        case Strong(:final children):
          // 嵌套粗体:为简洁,直接输出文本(不嵌 r 标签)
          buf.write(_inlinesAsRuns(children));
        case Code(:final code):
          buf.write('<w:t xml:space="preserve">${_esc(code)}</w:t>');
        case HardBreak():
          buf.write('<w:br/>');
        case SoftBreak():
          break;
        case Math(:final tex):
          buf.write('<w:t xml:space="preserve">${_esc(tex)}</w:t>');
        case Link(:final href, :final children):
          // 嵌套链接:首版降级为纯文本 + href 注释
          buf.write('${_inlinesAsRuns(children)}(${_esc(href)})');
        case ImageInline(:final alt):
          buf.write('<w:t>[${_esc(alt ?? '')}]</w:t>');
      }
    }
    return buf.toString();
  }

  // ─── 工具 ──────────────────────────────────────────────────

  /// XML 文本节点转义。
  String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
