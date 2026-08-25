/// Markdown AST 节点定义(供 DOCX 导出用)。
///
/// 设计参见 dev-doc.md 第 7.3 节。
/// 采用 sealed class + 子类:让 switch 表达式穷尽性检查,
/// docx_export 遍历 AST 时编译器能提示未处理节点。
///
/// 节点分为两类:
///   - [MdNode](块级):Document / Heading / Paragraph / List / CodeBlock / ...
///   - [Inline](行内):Text / Emphasis / Strong / Code / Link / ...
library;

/// 块级 AST 节点。
sealed class MdNode {}

class Document extends MdNode {
  final List<MdNode> children;
  Document(this.children);
}

class Heading extends MdNode {
  final int level; // 1~6
  final List<Inline> children;
  Heading(this.level, this.children);
}

class Paragraph extends MdNode {
  final List<Inline> children;
  Paragraph(this.children);
}

class BulletList extends MdNode {
  final List<ListItem> items;
  BulletList(this.items);
}

class OrderedList extends MdNode {
  final int start; // 起始编号(默认 1)
  final List<ListItem> items;
  OrderedList(this.start, this.items);
}

class ListItem extends MdNode {
  final List<MdNode> children; // 可含嵌套列表/段落
  ListItem(this.children);
}

class CodeBlock extends MdNode {
  final String? language;
  final String code;
  CodeBlock(this.language, this.code);
}

class BlockQuote extends MdNode {
  final List<MdNode> children;
  BlockQuote(this.children);
}

class Table extends MdNode {
  final List<List<List<Inline>>> rows; // rows[0] 为表头
  final List<int> alignments; // -1 左 / 0 中 / 1 右,长度=列数
  Table(this.rows, this.alignments);
}

class ThematicBreak extends MdNode {}

class Image extends MdNode {
  final String src;
  final String? alt;
  final String? title;
  Image(this.src, this.alt, this.title);
}

/// GFM 任务列表(- [x] / - [ ])。
///
/// 设计对齐 dev-doc.md Phase 5 任务列表(checked/unchecked 样式)。
/// 与 [BulletList] 区分:在 [DocumentXmlBuilder] 中映射为复选框 + 文本段落。
class TaskList extends MdNode {
  final List<TaskListItem> items;
  TaskList(this.items);
}

/// 任务列表项:含 [checked] 标记 + 块级子节点(通常是单个段落)。
class TaskListItem extends MdNode {
  final bool checked;
  final List<MdNode> children;
  TaskListItem(this.checked, this.children);
}

/// 行内 AST 节点。
sealed class Inline {}

class Text extends Inline {
  final String text;
  Text(this.text);
}

class Emphasis extends Inline {
  final List<Inline> children;
  Emphasis(this.children);
}

class Strong extends Inline {
  final List<Inline> children;
  Strong(this.children);
}

class Code extends Inline {
  final String code;
  Code(this.code);
}

class Link extends Inline {
  final String href;
  final List<Inline> children;
  Link(this.href, this.children);
}

class SoftBreak extends Inline {}

class HardBreak extends Inline {}

class Math extends Inline {
  final String tex;
  Math(this.tex);
}

/// 行内图片节点(由 [Parser] 在段落内识别 <img> 时产生;
/// [Parser._convertBlock] 的 'p' 分支会把它提升为块级 [Image])。
/// 也在 [DocumentXmlBuilder] 兜底分支中使用。
class ImageInline extends Inline {
  final String src;
  final String? alt;
  final String? title;
  ImageInline(this.src, this.alt, this.title);
}
