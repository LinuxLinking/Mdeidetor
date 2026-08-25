import 'package:markdown/markdown.dart' as md;

import 'ast.dart';
export 'ast.dart' show ImageInline;

/// Markdown 解析器:基于 `markdown` 包,把 md 文本转为本项目 AST。
///
/// 设计参见 dev-doc.md 第 7.3 节。
///
/// 用 `ExtensionSet.gitHubFlavored` 已包含:
///   - 表格(TableSyntax)、删除线(StrikethroughSyntax)、围栏代码块(FencedCodeBlockSyntax)
///   - 自动链接、强调等
///   - Phase 5:GFM 任务列表(UnorderedListWithCheckboxSyntax)——
///     markdown 7.x 已在 gitHubFlavored 集成,把 `- [x]` / `- [ ]` 渲染为
///     `<li class="task-list-item"><input type="checkbox" [checked]/>...`,
///     此处 [_convertBlock] ul 分支判断 class 转 [TaskList]。
///
/// `encodeHtml: false` —— 我们自己处理 XML 转义,不让 markdown 包先转,
/// 否则 DOCX 内的 `<` `>` `&` 会变成 `&lt;` `&gt;` `&amp;` 后再被 DOCX 二次转义。
class Parser {
  Document parse(String text) {
    final doc = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      blockSyntaxes: const [],
      inlineSyntaxes: const [],
      encodeHtml: false,
    );
    final nodes = doc.parse(text); // List<md.Node> —— md 包的块级 AST
    return Document(_convertBlocks(nodes));
  }

  // ─── 块级转换 ───────────────────────────────────────────────

  List<MdNode> _convertBlocks(List<md.Node> nodes) {
    final result = <MdNode>[];
    for (final n in nodes) {
      final converted = _convertBlock(n);
      if (converted != null) result.add(converted);
    }
    return result;
  }

  MdNode? _convertBlock(md.Node node) {
    if (node is! md.Element) {
      // md.Text 在块级层(罕见,通常是空白)忽略
      return null;
    }
    switch (node.tag) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        final level = int.parse(node.tag.substring(1));
        return Heading(level, _convertInlines(node.children));
      case 'p':
        // 段落内可能是图片
        final inlines = _convertInlines(node.children);
        if (inlines.length == 1 && inlines.first is ImageInline) {
          final img = inlines.first as ImageInline;
          return Image(img.src, img.alt, img.title);
        }
        return Paragraph(inlines);
      case 'ul':
        // Phase 5:若 ul 含至少一个 li.task-list-item,转为 [TaskList]
        if (_isTaskList(node)) {
          return TaskList(_convertTaskItems(node.children));
        }
        return BulletList(_convertListItems(node.children));
      case 'ol':
        final startAttr = node.attributes['start'];
        final start = startAttr == null ? 1 : (int.tryParse(startAttr) ?? 1);
        return OrderedList(start, _convertListItems(node.children));
      case 'blockquote':
        return BlockQuote(_convertBlocks(node.children ?? const []));
      case 'hr':
        return ThematicBreak();
      case 'pre':
        // 围栏代码块:markdown 包渲染为 <pre><code class="language-xxx">...</code></pre>
        final codeEl = (node.children?.isNotEmpty ?? false)
            ? node.children!.first
            : null;
        if (codeEl is md.Element && codeEl.tag == 'code') {
          final code = _collectText(codeEl.children);
          final cls = codeEl.attributes['class'] ?? '';
          final lang = cls.startsWith('language-') ? cls.substring(9) : null;
          return CodeBlock(lang, code);
        }
        return CodeBlock(null, _collectText(node.children));
      case 'table':
        return _convertTable(node);
      default:
        // 未识别块级节点:降级为段落(取全部文本)
        return Paragraph([Text(_collectText(node.children))]);
    }
  }

  List<ListItem> _convertListItems(List<md.Node>? children) {
    if (children == null) return const [];
    final items = <ListItem>[];
    for (final c in children) {
      if (c is md.Element && c.tag == 'li') {
        // li 内部可能是段落 + 嵌套列表,作为块级处理
        final blocks = <MdNode>[];
        for (final inner in c.children ?? const <md.Node>[]) {
          if (inner is md.Element && (inner.tag == 'ul' || inner.tag == 'ol')) {
            // 嵌套列表
            final nested = _convertBlock(inner);
            if (nested != null) blocks.add(nested);
          } else if (inner is md.Element && inner.tag == 'p') {
            blocks.add(Paragraph(_convertInlines(inner.children)));
          } else {
            // 行内内容包成段落
            blocks.add(Paragraph(_convertInlines([inner])));
          }
        }
        items.add(ListItem(blocks));
      }
    }
    return items;
  }

  /// 判断 ul 是否为 GFM 任务列表(至少一个 li 含 class="task-list-item")。
  bool _isTaskList(md.Element ul) {
    for (final c in ul.children ?? const <md.Node>[]) {
      if (c is md.Element &&
          c.tag == 'li' &&
          (c.attributes['class'] ?? '').contains('task-list-item')) {
        return true;
      }
    }
    return false;
  }

  /// 把任务列表 li 序列转为 [TaskListItem] 列表。
  ///
  /// markdown 包渲染 `- [x] 内容` 为:
  /// `<li class="task-list-item"><input type="checkbox" checked disabled/>内容</li>`
  /// 此处:
  ///   1. 扫 li.children 找 input 元素 → checked 标记
  ///   2. 跳过 input,把剩余 inline 收为段落
  List<TaskListItem> _convertTaskItems(List<md.Node>? children) {
    if (children == null) return const [];
    final items = <TaskListItem>[];
    for (final c in children) {
      if (c is! md.Element || c.tag != 'li') continue;
      var checked = false;
      final inlines = <md.Node>[];
      for (final inner in c.children ?? const <md.Node>[]) {
        if (inner is md.Element && inner.tag == 'input') {
          // checkbox input:有 checked 属性即视为已勾选
          if (inner.attributes.containsKey('checked')) checked = true;
          continue;
        }
        inlines.add(inner);
      }
      final blocks = <MdNode>[];
      if (inlines.isNotEmpty) {
        blocks.add(Paragraph(_convertInlines(inlines)));
      }
      items.add(TaskListItem(checked, blocks));
    }
    return items;
  }

  Table _convertTable(md.Element tableEl) {
    final rows = <List<List<Inline>>>[];
    final alignments = <int>[];
    for (final row in tableEl.children ?? const <md.Node>[]) {
      if (row is! md.Element) continue;
      if (row.tag != 'tr') continue;
      final cells = <List<Inline>>[];
      for (final cell in row.children ?? const <md.Node>[]) {
        if (cell is md.Element && (cell.tag == 'th' || cell.tag == 'td')) {
          cells.add(_convertInlines(cell.children));
        }
      }
      if (cells.isNotEmpty) rows.add(cells);
    }
    // 对齐信息:markdown 包暂存在 _alignments 不可访问,首版默认全左对齐
    if (rows.isNotEmpty) {
      alignments.addAll(List.filled(rows.first.length, -1));
    }
    return Table(rows, alignments);
  }

  // ─── 行内转换 ───────────────────────────────────────────────

  List<Inline> _convertInlines(List<md.Node>? nodes) {
    if (nodes == null) return const [];
    final result = <Inline>[];
    for (final n in nodes) {
      final converted = _convertInline(n);
      if (converted != null) result.add(converted);
    }
    return result;
  }

  Inline? _convertInline(md.Node node) {
    if (node is md.Text) {
      return Text(node.text);
    }
    if (node is! md.Element) return null;
    switch (node.tag) {
      case 'strong':
        return Strong(_convertInlines(node.children));
      case 'em':
        return Emphasis(_convertInlines(node.children));
      case 'code':
        return Code(_collectText(node.children));
      case 'a':
        final href = node.attributes['href'] ?? '';
        return Link(href, _convertInlines(node.children));
      case 'img':
        // markdown 包把图片放在 <p> 内作为 <img>
        final src = node.attributes['src'] ?? '';
        final alt = node.attributes['alt'];
        final title = node.attributes['title'];
        return ImageInline(src, alt, title);
      case 'br':
        return HardBreak();
      default:
        return Text(_collectText(node.children));
    }
  }

  String _collectText(List<md.Node>? nodes) {
    if (nodes == null) return '';
    final buf = StringBuffer();
    for (final n in nodes) {
      if (n is md.Text) {
        buf.write(n.text);
      } else if (n is md.Element) {
        buf.write(_collectText(n.children));
      }
    }
    return buf.toString();
  }
}
