import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../md_ast/ast.dart';
import 'content_types.dart' as ct;
import 'docx_options.dart';
import 'document_xml.dart';
import 'header_footer.dart';
import 'media.dart';
import 'numbering_xml.dart';
import 'rels.dart';
import 'styles_xml.dart' as st;

/// DOCX 生成器入口:AST → .docx bytes。
///
/// 设计对齐 dev-doc.md 第 9.7 节。
///
/// 流程:
///   1. [DocumentXmlBuilder] 遍历 AST 生成 `word/document.xml`
///      (期间通过 [MediaCollector] / [RelsCollector] 收集图片 / 超链接关系)
///   2. [StylesXmlBuilder] 生成 `word/styles.xml`
///   3. [NumberingXmlBuilder] 生成 `word/numbering.xml`
///   4. [ContentTypesXmlBuilder] 生成 `[Content_Types].xml`(按图片扩展名动态加 Default)
///   5. [TopLevelRelsBuilder] 生成 `_rels/.rels`
///   6. [DocumentRelsBuilder] 生成 `word/_rels/document.xml.rels`
///   7. 所有 part 收集为 `Map<String, Uint8List>`,经 [ZipEncoder] 打包
///
/// 调用:
/// ```dart
/// final ast = Parser().parse(md);
/// final bytes = DocxGenerator(DocxOptions.defaultOptions()).generate(ast);
/// ```
class DocxGenerator {
  final DocxOptions options;

  DocxGenerator(this.options);

  /// 主入口:AST → .docx bytes。
  Uint8List generate(Document ast) {
    final mediaCollector = MediaCollector();
    final relsCollector = RelsCollector();

    // 1. document.xml(含 sectPr 页面设置;若 includeToc 在顶部插 TOC;
    //    若 includeHeaderFooter 在 sectPr 注册 header/footer rId)
    final documentXml = DocumentXmlBuilder(options, mediaCollector, relsCollector)
        .build(ast);

    // 2. styles.xml + numbering.xml
    final stylesXml = st.StylesXmlBuilder(options).build();
    final numberingXml = NumberingXmlBuilder().build();

    // 3. content_types.xml(基于 mediaCollector + 是否含 header/footer)
    final contentTypesXml = ct.ContentTypesXmlBuilder(
      mediaCollector,
      includeHeaderFooter: options.includeHeaderFooter,
    ).build();

    // 4. .rels
    final topLevelRels = TopLevelRelsBuilder().build();
    final docRels = DocumentRelsBuilder(relsCollector).build();

    // 5. 组装 parts
    final parts = <String, Uint8List>{
      '[Content_Types].xml': Uint8List.fromList(utf8.encode(contentTypesXml)),
      '_rels/.rels': Uint8List.fromList(utf8.encode(topLevelRels)),
      'word/document.xml': Uint8List.fromList(utf8.encode(documentXml)),
      'word/styles.xml': Uint8List.fromList(utf8.encode(stylesXml)),
      'word/numbering.xml': Uint8List.fromList(utf8.encode(numberingXml)),
      'word/_rels/document.xml.rels': Uint8List.fromList(utf8.encode(docRels)),
    };
    // 图片资源
    for (final e in mediaCollector.entries) {
      parts['word/media/${e.filename}'] = e.bytes;
    }
    // 可选 header / footer
    if (options.includeHeaderFooter) {
      parts['word/header1.xml'] =
          Uint8List.fromList(utf8.encode(HeaderFooterBuilder.header(options)));
      parts['word/footer1.xml'] =
          Uint8List.fromList(utf8.encode(HeaderFooterBuilder.footer(options)));
    }

    return _zip(parts);
  }

  /// 把 parts 打包为 ZIP(.docx 容器)。
  Uint8List _zip(Map<String, Uint8List> parts) {
    final archive = Archive();
    parts.forEach((path, bytes) {
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    });
    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw StateError('ZIP 编码失败');
    }
    return Uint8List.fromList(zipBytes);
  }
}
