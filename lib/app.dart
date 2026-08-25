import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'file_io/recent_files.dart';
import 'l10n/app_localizations.dart';
import 'ui/editor_page.dart';
import 'ui/home_page.dart';
import 'ui/settings/theme_controller.dart';

class MdeditorApp extends StatelessWidget {
  const MdeditorApp({super.key, this.initialUri, this.navigatorKey});

  final Uri? initialUri;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) {
    final themeController = context.watch<ThemeController>();
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Mdeditor',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: themeController.flutterMode,
      localizationsDelegates: AppLocalizations.delegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(themeController.scale.value),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: initialUri == null
          ? const HomePage()
          : EditorPage(initialUri: initialUri, initialName: 'document.md'),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: Colors.teal,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      listTileTheme: const ListTileThemeData(minLeadingWidth: 24),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class AppProviders extends StatelessWidget {
  const AppProviders({
    super.key,
    required this.recentFiles,
    required this.themeController,
    required this.child,
  });

  final RecentFiles recentFiles;
  final ThemeController themeController;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<RecentFiles>.value(value: recentFiles),
        ChangeNotifierProvider<ThemeController>.value(value: themeController),
      ],
      child: child,
    );
  }
}
