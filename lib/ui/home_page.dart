import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../file_io/file_service.dart';
import '../file_io/recent_files.dart';
import '../l10n/app_localizations.dart';
import '../utils/error_handler.dart';
import 'editor_page.dart';
import 'settings/settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<RecentFile>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadRecentFiles();
  }

  Future<List<RecentFile>> _loadRecentFiles() {
    return context.read<RecentFiles>().all();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _future = _loadRecentFiles());
    await _future;
  }

  Future<void> _openViaSAF() async {
    try {
      final result = await FileService.instance.openViaSAF();
      if (result == null || !mounted) return;

      await context.read<RecentFiles>().add(
        RecentFile(
          uri: result.uri,
          name: result.name,
          lastOpened: DateTime.now(),
        ),
      );

      if (!mounted) return;
      await _pushEditor(result.uri, result.name);
      await _refresh();
    } catch (e, s) {
      if (!mounted) return;
      ErrorHandler.reportToUser(context, e, stack: s);
    }
  }

  Future<void> _newDoc() async {
    final l = AppLocalizations.of(context);
    await _pushEditor(null, l.t('untitled'));
    await _refresh();
  }

  Future<void> _openRecent(RecentFile file) async {
    await context.read<RecentFiles>().add(
      RecentFile(uri: file.uri, name: file.name, lastOpened: DateTime.now()),
    );
    if (!mounted) return;
    await _pushEditor(file.uri, file.name);
    await _refresh();
  }

  Future<void> _removeRecent(RecentFile file) async {
    await context.read<RecentFiles>().remove(file.uri);
    await _refresh();
  }

  Future<void> _pushEditor(Uri? uri, String name) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditorPage(initialUri: uri, initialName: name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('app_title')),
        actions: [
          IconButton(
            tooltip: l.t('new_doc'),
            icon: const Icon(Icons.note_add),
            onPressed: _newDoc,
          ),
          IconButton(
            tooltip: l.t('open'),
            icon: const Icon(Icons.folder_open),
            onPressed: _openViaSAF,
          ),
          IconButton(
            tooltip: l.t('settings'),
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder<List<RecentFile>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _CenteredState(
                  icon: Icons.error_outline,
                  title: l.t('load_failed'),
                  body: snapshot.error.toString(),
                );
              }

              final files = snapshot.data ?? const [];
              if (files.isEmpty) {
                return _EmptyRecentState(onNew: _newDoc, onOpen: _openViaSAF);
              }

              return ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: files.length + 1,
                separatorBuilder: (_, index) => index == 0
                    ? const SizedBox.shrink()
                    : const Divider(height: 1),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Text(
                        l.t('recent_files'),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  }

                  final file = files[index - 1];
                  return ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      l.format('last_opened', {'time': _fmt(file.lastOpened)}),
                    ),
                    trailing: IconButton(
                      tooltip: l.t('remove_recent'),
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => _removeRecent(file),
                    ),
                    onTap: () => _openRecent(file),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  String _fmt(DateTime time) {
    String pad(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${pad(time.month)}-${pad(time.day)} '
        '${pad(time.hour)}:${pad(time.minute)}';
  }
}

class _EmptyRecentState extends StatelessWidget {
  const _EmptyRecentState({required this.onNew, required this.onOpen});

  final VoidCallback onNew;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 96),
        _CenteredState(
          icon: Icons.description_outlined,
          title: l.t('no_recent_title'),
          body: l.t('no_recent_body'),
        ),
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: onNew,
              icon: const Icon(Icons.note_add),
              label: Text(l.t('new_doc')),
            ),
            OutlinedButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.folder_open),
              label: Text(l.t('open')),
            ),
          ],
        ),
      ],
    );
  }
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: colorScheme.primary),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
