// ignore_for_file: avoid_relative_lib_imports

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/export/docx_export/docx_isolate.dart';
import '../lib/export/docx_export/docx_options.dart';

/// Phase 5 收尾:验证 isolate 入口 [runDocxIsolate] 在 isolate 内正确生成 docx。
///
/// `compute` 在测试环境跑在主 isolate 上(无 rootBundle 等),但函数本身
/// 应能完整执行 md → docx bytes 的转换。
void main() {
  group('runDocxIsolate', () {
    test('空 md 在 isolate 中生成 docx bytes 含 6 必需 parts', () async {
      final bytes = await runDocxIsolate('', DocxOptions.defaultOptions());
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

    test('含 TOC + 页眉页脚的 options 在 isolate 中正确生效', () async {
      const md = '# 标题\n\n正文。';
      final bytes = await runDocxIsolate(
        md,
        const DocxOptions(
          includeToc: true,
          includeHeaderFooter: true,
          headerText: '页眉',
          footerText: '页脚',
        ),
      );
      expect(bytes, isNotEmpty);
      final archive = ZipDecoder().decodeBytes(bytes);
      final names = archive.files.map((f) => f.name).toSet();
      expect(names, contains('word/header1.xml'));
      expect(names, contains('word/footer1.xml'));
    });
  });
}
