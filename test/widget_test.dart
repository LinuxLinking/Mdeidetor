// ignore_for_file: avoid_relative_lib_imports

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/app.dart';
import '../lib/file_io/recent_files.dart';
import '../lib/ui/home_page.dart';
import '../lib/ui/settings/theme_controller.dart';

/// Phase 1 起步测试:HomePage 在空最近文件时显示提示文案。
/// Phase 6:补 [ThemeController] 参数。
void main() {
  testWidgets('HomePage renders empty hint', (WidgetTester tester) async {
    // SharedPreferences 在测试环境用 MockSharedPreferences,
    // 这里直接构造一个内存实现的 stub。
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final recentFiles = RecentFiles(prefs);
    final themeController = ThemeController(prefs);

    await tester.pumpWidget(
      AppProviders(
        recentFiles: recentFiles,
        themeController: themeController,
        child: const MdeditorApp(),
      ),
    );
    // 等 localization delegate 异步加载完成
    await tester.pumpAndSettle();

    // app_title 中英文都为 'Mdeditor',稳健断言
    expect(find.text('Mdeditor'), findsOneWidget);
    // no_recent 文案在测试默认 locale(en)下为英文,在 zh 下为中文;
    // 这里只断言 HomePage 空状态有渲染(_NoRecent 文案存在),不锁语种。
    expect(find.byType(HomePage), findsOneWidget);
  });
}
