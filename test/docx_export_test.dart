// ignore_for_file: avoid_relative_lib_imports

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/export/docx_export/docx_generator.dart';
import '../lib/export/docx_export/docx_options.dart';
import '../lib/md_ast/parser.dart';

/// Phase 4 / Phase 5 DOCX 导出测试:验证 ZIP 结构 + 关键 OOXML 节点存在。
///
/// 不验证 Word 真能打开(需手动),只验证 ZIP 解析能拿到必需 parts,
/// 且 document.xml 含 Heading/SourceCode/ListParagraph 等样式引用。
void main() {
  group('DocxGenerator Phase 4 基础', () {
    final generator = DocxGenerator(DocxOptions.defaultOptions());

    test('空 md 仍可生成 docx(含 6 个必需 parts)', () {
      final bytes = generator.generate(Parser().parse(''));
      expect(bytes, isNotEmpty);
      final archive = ZipDecoder().decodeBytes(bytes);
      final names = archive.files.map((f) => f.name).toSet();
      expect(names, contains('[Content_Types].xml'));
      expect(names, contains('_rels/.rels'));
      expect(names, contains('word/document.xml'));
      expect(names, contains('word/styles.xml'));
      expect(names, contains('word/numbering.xml'));
      expect(names, contains('word/_rels/document.xml.rels'));
    });

    test('简单 md(标题 + 段落 + 代码块 + 列表)生成含关键样式引用', () {
      const md = '''# 标题一

这是正文,含 **粗体** 和 *斜体*。

- 项目一
- 项目二

1. 第一项
2. 第二项

```dart
void main() => print('hi');
```
''';
      final bytes = generator.generate(Parser().parse(md));
      final archive = ZipDecoder().decodeBytes(bytes);
      final docFile = archive.files.firstWhere((f) => f.name == 'word/document.xml');
      final docXml = utf8.decode(docFile.content as List<int>);

      // 标题样式
      expect(docXml, contains('Heading1'));
      // 代码块样式
      expect(docXml, contains('SourceCode'));
      expect(docXml, contains("Consolas"));
      // 列表样式
      expect(docXml, contains('ListParagraph'));
      expect(docXml, contains('numId w:val="1"')); // bullet
      expect(docXml, contains('numId w:val="2"')); // decimal
      // 粗体 / 斜体
      expect(docXml, contains('<w:b/>'));
      expect(docXml, contains('<w:i/>'));
      // 转义检查:大于号 / 小于号应被转义
      expect(docXml, isNot(contains('<script')));
    });

    test('含特殊字符 <, >, & 的文本被正确 XML 转义', () {
      const md = '文本包含 <标签> & 符号';
      final bytes = generator.generate(Parser().parse(md));
      final archive = ZipDecoder().decodeBytes(bytes);
      final docFile = archive.files.firstWhere((f) => f.name == 'word/document.xml');
      final docXml = utf8.decode(docFile.content as List<int>);

      // 文本中 `<` `>` `&` 应转义,而非破坏 XML 结构
      expect(docXml, contains('&lt;标签&gt;'));
      expect(docXml, contains('&amp;'));
    });
  });

  // ─── Phase 5:图片 / TOC / 页眉页脚 / 任务列表 ──────────────

  group('Phase 5 图片嵌入', () {
    test('base64 data URI 图片生成 media + rels + drawing', () {
      // 1×1 透明 PNG 的 base64
      const pngB64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAVjI5'
          'JgAAAAASUVORK5CYII=';
      final md = '![测试图片](data:image/png;base64,$pngB64)';
      final bytes = DocxGenerator(DocxOptions.defaultOptions())
          .generate(Parser().parse(md));
      final archive = ZipDecoder().decodeBytes(bytes);
      final names = archive.files.map((f) => f.name).toSet();
      // 1. media 文件存在
      expect(names, contains('word/media/image1.png'));
      // 2. document.xml 含 drawing + blip + r:embed
      final docXml = utf8.decode(
        archive.files.firstWhere((f) => f.name == 'word/document.xml').content
            as List<int>,
      );
      expect(docXml, contains('<w:drawing>'));
      expect(docXml, contains('<a:blip'));
      expect(docXml, contains('r:embed="rId'));
      // 3. document.xml.rels 含 image 关系
      final relsXml = utf8.decode(
        archive.files
            .firstWhere((f) => f.name == 'word/_rels/document.xml.rels')
            .content as List<int>,
      );
      expect(relsXml, contains('media/image1.png'));
      expect(relsXml,
          contains('/relationships/image'));
      // 4. content_types 含 png Default
      final ctXml = utf8.decode(
        archive.files.firstWhere((f) => f.name == '[Content_Types].xml').content
            as List<int>,
      );
      expect(ctXml, contains('Extension="png"'));
    });

    test('URL 图片降级为链接文本(不下载)', () {
      const md = '![远程图](https://example.com/a.png)';
      final bytes = DocxGenerator(DocxOptions.defaultOptions())
          .generate(Parser().parse(md));
      final archive = ZipDecoder().decodeBytes(bytes);
      // 不应有 media 文件
      final hasMedia =
          archive.files.any((f) => f.name.startsWith('word/media/'));
      expect(hasMedia, isFalse);
      final docXml = utf8.decode(
        archive.files.firstWhere((f) => f.name == 'word/document.xml').content
            as List<int>,
      );
      expect(docXml, contains('[图片: 远程图]'));
      expect(docXml, contains('https://example.com/a.png'));
    });
  });

  group('Phase 5 TOC 目录', () {
    test('includeToc=true 时 document.xml 含 TOC 字段', () {
      const md = '# 标题\n\n正文。';
      final bytes = DocxGenerator(const DocxOptions(includeToc: true))
          .generate(Parser().parse(md));
      final archive = ZipDecoder().decodeBytes(bytes);
      final docXml = utf8.decode(
        archive.files.firstWhere((f) => f.name == 'word/document.xml').content
            as List<int>,
      );
      // TOC 字段
      expect(docXml, contains('TOC '));
      expect(docXml, contains('fldChar w:fldCharType="begin"'));
      expect(docXml, contains('fldChar w:fldCharType="end"'));
      expect(docXml, contains('更新域'));
    });

    test('includeToc=false(默认)时 document.xml 不含 TOC 字段', () {
      const md = '# 标题\n\n正文。';
      final bytes = DocxGenerator(DocxOptions.defaultOptions())
          .generate(Parser().parse(md));
      final archive = ZipDecoder().decodeBytes(bytes);
      final docXml = utf8.decode(
        archive.files.firstWhere((f) => f.name == 'word/document.xml').content
            as List<int>,
      );
      expect(docXml, isNot(contains('fldChar w:fldCharType="begin"')));
    });
  });

  group('Phase 5 页眉页脚', () {
    test('includeHeaderFooter=true 生成 header1/footer1 parts + sectPr 引用', () {
      const md = '# 标题\n\n正文。';
      final bytes = DocxGenerator(const DocxOptions(
        includeHeaderFooter: true,
        headerText: '我的页眉',
        footerText: '我的页脚',
      )).generate(Parser().parse(md));
      final archive = ZipDecoder().decodeBytes(bytes);
      final names = archive.files.map((f) => f.name).toSet();
      // 1. parts 存在
      expect(names, contains('word/header1.xml'));
      expect(names, contains('word/footer1.xml'));
      // 2. content_types 含 Override
      final ctXml = utf8.decode(
        archive.files.firstWhere((f) => f.name == '[Content_Types].xml').content
            as List<int>,
      );
      expect(ctXml, contains('PartName="/word/header1.xml"'));
      expect(ctXml, contains('PartName="/word/footer1.xml"'));
      // 3. document.xml sectPr 含 headerReference / footerReference
      final docXml = utf8.decode(
        archive.files.firstWhere((f) => f.name == 'word/document.xml').content
            as List<int>,
      );
      expect(docXml, contains('<w:headerReference'));
      expect(docXml, contains('<w:footerReference'));
      // 4. document.xml.rels 含 header/footer 关系
      final relsXml = utf8.decode(
        archive.files
            .firstWhere((f) => f.name == 'word/_rels/document.xml.rels')
            .content as List<int>,
      );
      expect(relsXml, contains('header1.xml'));
      expect(relsXml, contains('footer1.xml'));
      expect(relsXml, contains('/relationships/header'));
      expect(relsXml, contains('/relationships/footer'));
      // 5. header1.xml 含文本
      final hdrXml = utf8.decode(
        archive.files.firstWhere((f) => f.name == 'word/header1.xml').content
            as List<int>,
      );
      expect(hdrXml, contains('我的页眉'));
      expect(hdrXml, contains('<w:hdr'));
      // 6. footer1.xml 含文本
      final ftrXml = utf8.decode(
        archive.files.firstWhere((f) => f.name == 'word/footer1.xml').content
            as List<int>,
      );
      expect(ftrXml, contains('我的页脚'));
      expect(ftrXml, contains('<w:ftr'));
    });
  });

  group('Phase 5 任务列表', () {
    test('GFM 任务列表转复选框 + 文本段落', () {
      const md = '''- [x] 已完成
- [ ] 待办
''';
      final bytes = DocxGenerator(DocxOptions.defaultOptions())
          .generate(Parser().parse(md));
      final archive = ZipDecoder().decodeBytes(bytes);
      final docXml = utf8.decode(
        archive.files.firstWhere((f) => f.name == 'word/document.xml').content
            as List<int>,
      );
      // 含 ☑(U+2611) 和 ☐(U+2610)
      expect(docXml, contains('\u2611'));
      expect(docXml, contains('\u2610'));
      // 含原文本
      expect(docXml, contains('已完成'));
      expect(docXml, contains('待办'));
      // 含 ListParagraph 样式
      expect(docXml, contains('ListParagraph'));
    });
  });

  // 辅助:archive.files 在 archive 3.x 返回 List<ArchiveFile>
  // 注意 content 字段是 dynamic(List<int>),用 utf8.decode 解码为字符串
  test('DocxOptions.defaultOptions() 提供中文字体', () {
    final opts = DocxOptions.defaultOptions();
    expect(opts.asciiFont, 'Calibri');
    expect(opts.eastAsiaFont, '宋体');
    expect(opts.monoFont, 'Consolas');
    expect(opts.defaultSize, 22);
  });
}
