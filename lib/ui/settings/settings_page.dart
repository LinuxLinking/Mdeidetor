import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import 'theme_controller.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final themeController = context.watch<ThemeController>();

    return Scaffold(
      appBar: AppBar(title: Text(l.t('settings'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _SectionHeader(l.t('appearance')),
            _FullWidthSegmentedButton<ThemeModePreference>(
              selected: themeController.mode,
              onSelectionChanged: themeController.setMode,
              segments: [
                ButtonSegment(
                  value: ThemeModePreference.system,
                  icon: const Icon(Icons.brightness_auto),
                  label: Text(l.t('theme_system')),
                ),
                ButtonSegment(
                  value: ThemeModePreference.light,
                  icon: const Icon(Icons.light_mode),
                  label: Text(l.t('theme_light')),
                ),
                ButtonSegment(
                  value: ThemeModePreference.dark,
                  icon: const Icon(Icons.dark_mode),
                  label: Text(l.t('theme_dark')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l.t('theme_system_desc'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            _SectionHeader(l.t('editor_theme')),
            DropdownButtonFormField<EditorThemePreference>(
              initialValue: themeController.editorTheme,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.palette_outlined),
                labelText: l.t('render_theme'),
              ),
              items: [
                DropdownMenuItem(
                  value: EditorThemePreference.githubLight,
                  child: Text(l.t('github_light')),
                ),
                DropdownMenuItem(
                  value: EditorThemePreference.githubDark,
                  child: Text(l.t('github_dark')),
                ),
                DropdownMenuItem(
                  value: EditorThemePreference.vue,
                  child: Text(l.t('vue_theme')),
                ),
              ],
              onChanged: (value) {
                if (value != null) themeController.setEditorTheme(value);
              },
            ),
            const SizedBox(height: 8),
            Text(
              l.t('editor_theme_desc'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            _SectionHeader(l.t('font')),
            _FullWidthSegmentedButton<TextScalePreference>(
              selected: themeController.scale,
              onSelectionChanged: themeController.setScale,
              segments: [
                ButtonSegment(
                  value: TextScalePreference.small,
                  label: Text(l.t('text_scale_small')),
                ),
                ButtonSegment(
                  value: TextScalePreference.standard,
                  label: Text(l.t('text_scale_standard')),
                ),
                ButtonSegment(
                  value: TextScalePreference.large,
                  label: Text(l.t('text_scale_large')),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _SectionHeader(l.t('about')),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.info_outline),
              title: const Text('Mdeditor'),
              subtitle: Text(l.t('about_subtitle')),
            ),
          ],
        ),
      ),
    );
  }
}

class _FullWidthSegmentedButton<T> extends StatelessWidget {
  const _FullWidthSegmentedButton({
    required this.selected,
    required this.onSelectionChanged,
    required this.segments,
  });

  final T selected;
  final ValueChanged<T> onSelectionChanged;
  final List<ButtonSegment<T>> segments;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<T>(
        showSelectedIcon: false,
        selected: {selected},
        segments: segments,
        onSelectionChanged: (values) => onSelectionChanged(values.single),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
