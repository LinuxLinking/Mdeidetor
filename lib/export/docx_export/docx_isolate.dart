import 'package:flutter/foundation.dart';

import '../../md_ast/parser.dart';
import 'docx_generator.dart';
import 'docx_options.dart';

/// Isolate 导出任务参数。
///
/// `compute` 只接受单参数 + 单返回值,所以把 [md] + [options] 打包为 record。
/// 所有字段必须 isolate 可序列化(String / int / bool / Uint8List 均安全)。
typedef DocxJob = ({String md, DocxOptions options});

/// 在 isolate 中执行 md → .docx bytes 的顶层函数。
///
/// 设计参见 dev-doc.md 第 9.8 节。
///
/// 调用:
/// ```dart
/// final bytes = await compute(
///   generateDocxIsolate,
///   (md: md, options: options),
/// );
/// ```
///
/// 注意:[Parser] 与 [DocxGenerator] 实例本身不在 isolate 主线程,
/// 在 isolate 内重新构造,避免跨 isolate 共享可变状态。
Uint8List generateDocxIsolate(DocxJob job) {
  final ast = Parser().parse(job.md);
  return DocxGenerator(job.options).generate(ast);
}

/// UI 侧便利封装:把 md + options 丢进 [compute] 执行。
///
/// 用法:
/// ```dart
/// final bytes = await runDocxIsolate(md, options);
/// ```
Future<Uint8List> runDocxIsolate(String md, DocxOptions options) {
  return compute(generateDocxIsolate, (md: md, options: options));
}
