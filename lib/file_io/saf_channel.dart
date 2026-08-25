import 'package:flutter/services.dart';

/// SAF (Storage Access Framework) Platform Channel 的 Dart 侧封装。
///
/// 对应原生 [android/app/src/main/kotlin/com/mdeditor/app/SafChannel.kt],
/// channel name = `mdeditor/saf`,提供:
///   - `openDocument(mime)`:发起 `ACTION_OPEN_DOCUMENT`,返回 `content://` URI
///     (Kotlin 侧已 `takePersistableUriPermission`,应用重启后仍可访问)
///   - `createDocument(suggestedName, mime)`:发起 `ACTION_CREATE_DOCUMENT`(另存为)
///   - `readUri(uri)`:经 `ContentResolver` 读取文本
///   - `writeUri(uri, bytes)`:以 `"wt"` 截断模式写入字节
///   - `queryName(uri)`:查 `OpenableColumns.DISPLAY_NAME`
///
/// 历史教训:file_picker 在 Android 上会把文件复制到 app cache 后返回缓存路径,
/// 不保留原始 content:// URI,导致"保存回原位置"会写到缓存副本而非用户原始选择的位置。
/// 因此本项目**不使用 file_picker**,改用本 channel。
class SafChannel {
  static const MethodChannel _ch = MethodChannel('mdeditor/saf');

  /// 通过 SAF 打开文件。返回选中的 `content://` URI;用户取消返回 null。
  static Future<Uri?> openDocument({required String mime}) async {
    final s = await _ch.invokeMethod<String>('openDocument', {'mime': mime});
    return s == null ? null : Uri.parse(s);
  }

  /// 通过 SAF 让用户选择另存为的目标位置。返回选中的 URI;用户取消返回 null。
  static Future<Uri?> createDocument({
    required String suggestedName,
    required String mime,
  }) async {
    final s = await _ch.invokeMethod<String>('createDocument', {
      'suggestedName': suggestedName,
      'mime': mime,
    });
    return s == null ? null : Uri.parse(s);
  }

  /// 读取 `content://` URI 文本。失败抛 [PlatformException]。
  static Future<String?> readUri(Uri uri) =>
      _ch.invokeMethod<String>('readUri', {'uri': uri.toString()});

  /// 以 `"wt"`(截断)模式写入字节到 `content://` URI。
  static Future<void> writeUri(Uri uri, Uint8List bytes) =>
      _ch.invokeMethod<void>('writeUri', {
        'uri': uri.toString(),
        'bytes': bytes,
      });

  /// 查询 URI 对应文件的显示名(`OpenableColumns.DISPLAY_NAME`)。
  static Future<String?> queryName(Uri uri) =>
      _ch.invokeMethod<String>('queryName', {'uri': uri.toString()});
}

/// 便捷别名:封装 [SafChannel.queryName] 的常见用法。
class SafColumn {
  /// 返回 URI 的显示名;查询失败回退到 'unknown.md'。
  static Future<String> name(Uri uri) async =>
      (await SafChannel.queryName(uri)) ?? 'unknown.md';
}
