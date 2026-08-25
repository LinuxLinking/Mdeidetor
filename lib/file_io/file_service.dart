import 'dart:convert';
import 'dart:typed_data';

import 'saf_channel.dart';

/// `FileService.openViaSAF` 的返回值。
class FileOpenResult {
  final Uri uri;
  final String content;
  final String name;
  FileOpenResult({
    required this.uri,
    required this.content,
    required this.name,
  });
}

/// 文件 I/O 服务:统一封装 SAF 打开/保存/读写。
///
/// 设计原则:所有持久化都走 SAF (Storage Access Framework),
/// 拿到原生 `content://` URI 并 `takePersistableUriPermission`,
/// 而不是复制到 app cache(参见 [SafChannel] 的历史教训)。
class FileService {
  /// 单例:全局只一个 FileService,便于 UI 层调用。
  FileService._();
  static final FileService instance = FileService._();

  /// 通过 SAF 打开 .md 文件。
  ///
  /// 流程:
  ///   1. `SafChannel.openDocument` 发起 `ACTION_OPEN_DOCUMENT`
  ///      (Kotlin 侧已 `takePersistableUriPermission`)
  ///   2. 经 `ContentResolver` 读取文本
  ///   3. 查 `DISPLAY_NAME`
  /// 用户取消(返回 null URI)时返回 null。
  Future<FileOpenResult?> openViaSAF() async {
    final uri = await SafChannel.openDocument(mime: 'text/markdown');
    if (uri == null) return null; // 用户取消

    final content = await readUri(uri);
    final name = await SafColumn.name(uri);
    return FileOpenResult(uri: uri, content: content, name: name);
  }

  /// 通过 SAF 让用户选择另存为的目标位置,返回选中的 URI。
  /// 字节写入由调用方在拿到 URI 后调用 [writeUri],便于 UI 反馈两步进度。
  Future<Uri?> pickSaveLocation({
    required String suggestedName,
    String mime = 'text/markdown',
  }) async {
    return SafChannel.createDocument(
      suggestedName: suggestedName,
      mime: mime,
    );
  }

  /// 读取 `content://` URI 文本。失败抛 [Exception]。
  Future<String> readUri(Uri uri) async {
    final text = await SafChannel.readUri(uri);
    if (text == null) throw Exception('读取失败: $uri');
    return text;
  }

  /// 写入 `content://` URI("wt" 截断模式)。
  Future<void> writeUri(Uri uri, Uint8List bytes) async {
    await SafChannel.writeUri(uri, bytes);
  }

  /// 写入文本(便捷重载,内部转 UTF-8 字节)。
  ///
  /// Phase 6 修复:之前用 `text.codeUnits` 是 UTF-16 code units,
  /// 中文等非 ASCII 字符会被错误编码(每码元 1 字节),
  /// 在 Android 上读回时显示乱码。改用 [utf8.encode] 正确编码。
  Future<void> writeText(Uri uri, String text) async {
    await writeUri(uri, Uint8List.fromList(utf8.encode(text)));
  }
}
