import 'package:flutter/material.dart';

/// 错误类别,用于做差异化提示。
///
/// 设计对齐 dev-doc.md Phase 6 第 1725 行"错误处理(URI 失效、文件读写
/// 失败、内存不足)"。
enum ErrorKind {
  /// URI 失效(权限丢失、文件被删、外部存储卸载)
  uriRevoked,

  /// 文件读写失败(I/O 异常、磁盘满)
  ioFailure,

  /// 内存不足(大文件 + isolate 序列化失败)
  outOfMemory,

  /// 用户取消(SAF 返回 null)
  userCancelled,

  /// 未知错误
  unknown,
}

/// 全局错误处理工具。
///
/// 提供两层:
///   1. [report] / [reportToUser]:Zone 内任意位置调用,把异常转换为
///      用户可读消息(中文)+ SnackBar 反馈
///   2. [classify]:把原始异常按类型映射到具体错误类别(URI 失效/读写
///      失败/内存不足/未知)
///
/// 用法:
/// ```dart
/// try { ... } catch (e, s) {
///   ErrorHandler.reportToUser(context, e, stack: s);
/// }
/// ```
class ErrorHandler {
  /// 把异常分类。
  static ErrorKind classify(Object error) {
    final s = error.toString().toLowerCase();
    if (s.contains('permission') ||
        s.contains('revoked') ||
        s.contains('uri') && s.contains('not')) {
      return ErrorKind.uriRevoked;
    }
    if (s.contains('outofmemory') ||
        s.contains('stack overflow') ||
        s.contains('isolate') && s.contains('spawn')) {
      return ErrorKind.outOfMemory;
    }
    if (s.contains('io') || s.contains('read') || s.contains('write')) {
      return ErrorKind.ioFailure;
    }
    return ErrorKind.unknown;
  }

  /// 中文提示文案,用于 SnackBar。
  static String messageFor(ErrorKind kind) {
    switch (kind) {
      case ErrorKind.uriRevoked:
        return '文件访问权限已失效,请重新打开';
      case ErrorKind.ioFailure:
        return '文件读写失败,请检查存储空间或权限';
      case ErrorKind.outOfMemory:
        return '内存不足,请尝试减小文件或关闭其他应用';
      case ErrorKind.userCancelled:
        return '已取消';
      case ErrorKind.unknown:
        return '发生未知错误';
    }
  }

  /// 静默上报(debugPrint)。后续可接 Crashlytics / Sentry。
  static void report(Object error, StackTrace? stack) {
    debugPrint('ErrorHandler.report: $error');
    if (stack != null) debugPrint('$stack');
  }

  /// 上报 + 给用户 SnackBar 反馈。
  ///
  /// 用法:
  /// ```dart
  /// try { await fs.writeUri(uri, bytes); }
  /// catch (e, s) {
  ///   if (!mounted) return;
  ///   ErrorHandler.reportToUser(context, e, stack: s);
  /// }
  /// ```
  static void reportToUser(
    BuildContext context,
    Object error, {
    StackTrace? stack,
  }) {
    report(error, stack);
    final kind = classify(error);
    final msg = messageFor(kind);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$msg: $error'),
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
