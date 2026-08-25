import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'file_io/intent_channel.dart';
import 'file_io/recent_files.dart';
import 'ui/settings/theme_controller.dart';
import 'ui/editor_page.dart';

final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

/// 入口:启动时如有外部 intent (`ACTION_VIEW`) 拉起的 .md 文件 URI,
/// 直接路由到 EditorPage;否则进 HomePage。
///
/// Phase 1:打开 .md(SAF) → 显示文本(待 Milkdown 接入) → 编辑 → 保存回原 URI
/// Phase 2:外部 intent-filter 接收 .md(从文件管理器"打开方式"选 Mdeditor)
/// Phase 6:主题持久化 + 全局错误捕获 runZonedGuarded
///
/// 设计参见 docs/dev-doc.md 第 5.7 / 7.2 / 7.7 节,实施阶段见第 12 节。
void main() async {
  await _runGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    final recentFiles = RecentFiles(prefs);
    final themeController = ThemeController(prefs);
    final initialUri = await IntentChannel.getInitialUri();

    runApp(
      AppProviders(
        recentFiles: recentFiles,
        themeController: themeController,
        child: MdeditorApp(
          initialUri: initialUri,
          navigatorKey: _navigatorKey,
        ),
      ),
    );
    IntentChannel.openedUris.listen(
      _openIncomingDocument,
      onError: (Object error, StackTrace stack) {
        debugPrint('Failed to receive external document intent: $error\n$stack');
      },
    );
  });
}

/// Routes files delivered while the app is already open to a new editor page.
/// Existing editor pages stay in the stack, so their unsaved-change protection
/// still runs when the user returns to them.
void _openIncomingDocument(Uri uri) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => EditorPage(initialUri: uri, initialName: 'document.md'),
      ),
    );
  });
}

/// 全局错误捕获包装:同步 + 异步错误兜底。
///
/// 设计对齐 dev-doc.md Phase 6 第 1725 行"错误处理(URI 失效、文件读写失败、
/// 内存不足)"。
///
/// - 同步 main 抛出会被 zone 捕获
/// - 异步 Future 错误会被 `onError` 捕获(避免"未捕获异步错误"红屏)
/// - FlutterError.onError 走默认行为(渲染错误仍上送给 Flutter 框架)
Future<void> _runGuarded(Future<void> Function() body) async {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    // 后续可接入 Crashlytics / Sentry
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };
  await runZonedGuarded(
    () async {
      await body();
    },
    (error, stack) {
      // Zone 内未捕获的异步错误
      debugPrint('Zone error: $error\n$stack');
    },
  );
}
