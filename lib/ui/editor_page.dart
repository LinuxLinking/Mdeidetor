import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../editor/editor_controller.dart';
import '../export/docx_export/docx_isolate.dart';
import '../export/docx_export/docx_options.dart';
import '../file_io/file_service.dart';
import '../file_io/recent_files.dart';
import '../file_io/saf_channel.dart';
import '../l10n/app_localizations.dart';
import '../native/native_render_channel.dart';
import '../utils/error_handler.dart';
import 'docx_export_dialog.dart';
import 'settings/theme_controller.dart';

enum _EditorCommand { exportPdf, exportDocx, exportHtml, saveAs }

class EditorPage extends StatefulWidget {
  const EditorPage({super.key, this.initialUri, required this.initialName});

  final Uri? initialUri;
  final String initialName;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  static const _autoSaveInterval = Duration(seconds: 30);

  late final EditorController _editor;
  late final WebViewController _wvc;
  late Uri? _uri;
  late String _name;

  Timer? _autoSaveTimer;
  String? _loadError;
  bool _allowPop = false;
  EditorThemePreference? _appliedTheme;

  @override
  void initState() {
    super.initState();
    _editor = EditorController();
    _uri = widget.initialUri;
    _name = widget.initialName;
    _wvc = WebViewController();
    _editor
      ..bindWebView(_wvc)
      ..addListener(_onEditorChanged);
    _wvc.loadFlutterAsset('assets/web/index.html');
    _loadInitial();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = context.watch<ThemeController>().editorTheme;
    if (theme == _appliedTheme) return;
    _appliedTheme = theme;
    unawaited(
      _editor.setNativeTheme(context.read<ThemeController>().nativeTheme),
    );
  }

  void _onEditorChanged() {
    if (!mounted || !_editor.isDirty) return;
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(_autoSaveInterval, _autoSave);
  }

  Future<void> _loadInitial() async {
    if (_uri == null) {
      _editor.pendingInitialContent = '';
      return;
    }

    try {
      final text = await FileService.instance.readUri(_uri!);
      final realName = await _displayNameFor(
        _uri!,
        fallback: widget.initialName,
      );
      _editor.pendingInitialContent = text;
      // 文件读取与 WebView 初始化是并行的；如果 WebView 已经 ready，
      // 需要显式回填内容，否则初始化时拿到的空字符串会一直留在编辑器里。
      if (_editor.isReady) {
        await _editor.loadContent(text);
      }
      if (!mounted) return;
      setState(() => _name = realName);
    } catch (e, s) {
      _loadError = e.toString();
      if (!mounted) return;
      ErrorHandler.reportToUser(context, e, stack: s);
      setState(() {});
    }
  }

  Future<String> _displayNameFor(Uri uri, {required String fallback}) async {
    try {
      final name = await SafColumn.name(uri);
      return name.isEmpty ? fallback : name;
    } catch (e) {
      debugPrint('queryName failed, using fallback name: $e');
      return fallback;
    }
  }

  Future<void> _autoSave() async {
    final uri = _uri;
    if (uri == null || !_editor.isDirty || !_editor.isReady) return;

    try {
      final md = await _editor.getContent();
      await FileService.instance.writeText(uri, md);
      _editor.markSaved();
      debugPrint('Autosaved: $_name');
    } catch (e, s) {
      ErrorHandler.report(e, s);
    }
  }

  Future<void> _save() async {
    final uri = _uri;
    if (uri == null) {
      await _saveAs();
      return;
    }

    try {
      final md = await _editor.getContent();
      await FileService.instance.writeText(uri, md);
      _editor.markSaved();
      if (!mounted) return;
      _showMessage(
        AppLocalizations.of(context).format('saved_file', {'name': _name}),
      );
    } catch (e, s) {
      if (!mounted) return;
      ErrorHandler.report(e, s);
      _showMessage('${AppLocalizations.of(context).t('save_failed')}: $e');
    }
  }

  Future<void> _saveAs() async {
    final l = AppLocalizations.of(context);
    final uri = await FileService.instance.pickSaveLocation(
      suggestedName: _markdownFileName(_name),
      mime: 'text/markdown',
    );
    if (uri == null) return;

    try {
      final md = await _editor.getContent();
      await FileService.instance.writeText(uri, md);
      final name = await _displayNameFor(
        uri,
        fallback: _markdownFileName(_name),
      );
      if (!mounted) return;
      setState(() {
        _uri = uri;
        _name = name;
      });
      _editor.markSaved();
      await _rememberRecent(uri, name);
      if (!mounted) return;
      _showMessage(l.format('saved_as_file', {'name': name}));
    } catch (e, s) {
      if (!mounted) return;
      ErrorHandler.report(e, s);
      _showMessage('${l.t('save_as_failed')}: $e');
    }
  }

  Future<void> _open() async {
    if (!await _confirmDiscardChangesIfNeeded()) return;

    try {
      final result = await FileService.instance.openViaSAF();
      if (result == null || !mounted) return;

      setState(() {
        _uri = result.uri;
        _name = result.name;
        _loadError = null;
      });
      await _editor.loadContent(result.content);
      await _rememberRecent(result.uri, result.name);
    } catch (e, s) {
      if (!mounted) return;
      ErrorHandler.reportToUser(context, e, stack: s);
    }
  }

  Future<void> _exportPdf() async {
    final l = AppLocalizations.of(context);
    if (!_ensureEditorReady(l)) return;
    final nativeTheme = context.read<ThemeController>().nativeTheme;
    try {
      final markdown = await _editor.getContent();
      if (markdown.isEmpty) {
        if (!mounted) return;
        _showMessage(l.t('content_empty'));
        return;
      }
      final suggestedName = _exportFileName(_name, '.pdf');
      final target = await FileService.instance.pickSaveLocation(
        suggestedName: suggestedName,
        mime: 'application/pdf',
      );
      if (target == null) return;
      final path = await NativeRenderChannel.exportPdf(
        markdown: markdown,
        fileName: suggestedName,
        theme: nativeTheme,
      );
      if (!mounted) return;
      if (path == null) {
        _showMessage(l.t('pdf_export_failed'));
        return;
      }
      await FileService.instance.writeUri(
        target,
        await File(path).readAsBytes(),
      );
      if (!mounted) return;
      _showMessage(l.format('pdf_exported', {'name': suggestedName}));
    } catch (e, s) {
      if (!mounted) return;
      ErrorHandler.report(e, s);
      _showMessage('${l.t('pdf_export_failed')}: $e');
    }
  }

  Future<void> _exportDocx() async {
    final l = AppLocalizations.of(context);
    if (!_ensureEditorReady(l)) return;

    final md = await _editor.getContent();
    if (md.isEmpty) {
      if (!mounted) return;
      _showMessage(l.t('content_empty'));
      return;
    }

    if (!mounted) return;
    final options = await showDialog<DocxOptions>(
      context: context,
      builder: (_) => const DocxExportDialog(),
    );
    if (options == null || !mounted) return;

    final suggestedName = _exportFileName(_name, '.docx');
    final uri = await FileService.instance.pickSaveLocation(
      suggestedName: suggestedName,
      mime:
          'application/vnd.openxmlformats-officedocument'
          '.wordprocessingml.document',
    );
    if (uri == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l.t('generating_docx'))));

    Uint8List bytes;
    try {
      bytes = await runDocxIsolate(md, options);
    } catch (e, s) {
      if (!mounted) return;
      ErrorHandler.report(e, s);
      _showMessage('${l.t('docx_generate_failed')}: $e');
      return;
    }
    if (!mounted) return;

    try {
      await FileService.instance.writeUri(uri, bytes);
      final exportedName = await _displayNameFor(uri, fallback: suggestedName);
      if (!mounted) return;
      _showMessage(l.format('docx_exported', {'name': exportedName}));
    } catch (e, s) {
      if (!mounted) return;
      ErrorHandler.report(e, s);
      _showMessage('${l.t('write_failed')}: $e');
    }
  }

  Future<void> _exportHtml() async {
    final l = AppLocalizations.of(context);
    if (!_ensureEditorReady(l)) return;
    final nativeTheme = context.read<ThemeController>().nativeTheme;
    final markdown = await _editor.getContent();
    final suggestedName = _exportFileName(_name, '.html');
    final target = await FileService.instance.pickSaveLocation(
      suggestedName: suggestedName,
      mime: 'text/html',
    );
    if (target == null) return;
    final path = await NativeRenderChannel.exportHtml(
      markdown: markdown,
      fileName: suggestedName,
      theme: nativeTheme,
    );
    if (!mounted) return;
    if (path == null) {
      _showMessage(l.t('html_export_failed'));
      return;
    }
    try {
      await FileService.instance.writeUri(
        target,
        await File(path).readAsBytes(),
      );
      if (!mounted) return;
      _showMessage(l.format('html_exported', {'name': suggestedName}));
    } catch (error, stack) {
      ErrorHandler.report(error, stack);
      if (mounted) _showMessage('${l.t('html_export_failed')}: $error');
    }
  }

  Future<void> _insertLink() async {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController(text: 'https://');
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.t('insert_link')),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(labelText: l.t('link_url')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(l.t('confirm')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (url == null || url.isEmpty) return;
    await _editor.formatSelection('createLink', url);
  }

  bool _ensureEditorReady(AppLocalizations l) {
    if (_editor.isReady) return true;
    _showMessage(l.t('editor_not_ready'));
    return false;
  }

  Future<void> _rememberRecent(Uri uri, String name) {
    return context.read<RecentFiles>().add(
      RecentFile(uri: uri, name: name, lastOpened: DateTime.now()),
    );
  }

  Future<bool> _confirmDiscardChangesIfNeeded() async {
    if (!_editor.isDirty) return true;
    final l = AppLocalizations.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.t('discard_changes_title')),
        content: Text(l.t('discard_changes_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.t('discard_changes')),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  Future<void> _handlePopBlocked() async {
    final shouldPop = await _confirmDiscardChangesIfNeeded();
    if (!mounted || !shouldPop) return;
    setState(() => _allowPop = true);
    Navigator.of(context).pop();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _markdownFileName(String name) {
    return name.toLowerCase().endsWith('.md') ? name : '$name.md';
  }

  String _exportFileName(String name, String extension) {
    final lowerName = name.toLowerCase();
    final baseName = lowerName.endsWith('.md')
        ? name.substring(0, name.length - 3)
        : name;
    return '$baseName$extension';
  }

  void _runCommand(_EditorCommand command) {
    switch (command) {
      case _EditorCommand.exportPdf:
        unawaited(_exportPdf());
        break;
      case _EditorCommand.exportDocx:
        unawaited(_exportDocx());
        break;
      case _EditorCommand.exportHtml:
        unawaited(_exportHtml());
        break;
      case _EditorCommand.saveAs:
        unawaited(_saveAs());
        break;
    }
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _editor
      ..removeListener(_onEditorChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: _editor,
      builder: (context, _) {
        final dirty = _editor.isDirty;
        return PopScope<void>(
          canPop: !dirty || _allowPop,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            unawaited(_handlePopBlocked());
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(
                _name + (dirty ? ' *' : ''),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              actions: [
                IconButton(
                  tooltip: l.t('open'),
                  icon: const Icon(Icons.folder_open),
                  onPressed: _open,
                ),
                IconButton(
                  tooltip: l.t('save'),
                  icon: const Icon(Icons.save),
                  onPressed: _save,
                ),
                PopupMenuButton<_EditorCommand>(
                  tooltip: l.t('more'),
                  onSelected: _runCommand,
                  itemBuilder: (context) => [
                    _menuItem(
                      _EditorCommand.exportPdf,
                      Icons.picture_as_pdf,
                      l.t('export_pdf'),
                    ),
                    _menuItem(
                      _EditorCommand.exportDocx,
                      Icons.description,
                      l.t('export_docx'),
                    ),
                    _menuItem(
                      _EditorCommand.exportHtml,
                      Icons.html,
                      l.t('export_html'),
                    ),
                    _menuItem(
                      _EditorCommand.saveAs,
                      Icons.save_as,
                      l.t('save_as'),
                    ),
                  ],
                ),
              ],
            ),
            body: _loadError == null
                ? LayoutBuilder(
                    builder: (context, constraints) => Stack(
                      children: [
                        Positioned.fill(child: WebViewWidget(controller: _wvc)),
                        Positioned.fill(
                          child: Overlay(
                            initialEntries: [
                              OverlayEntry(
                                builder: (_) => _editor.selection == null
                                    ? const SizedBox.shrink()
                                    : _SelectionToolbar(
                                        selection: _editor.selection!,
                                        maxWidth: constraints.maxWidth,
                                        maxHeight: constraints.maxHeight,
                                        boldTooltip: l.t('format_bold'),
                                        italicTooltip: l.t('format_italic'),
                                        linkTooltip: l.t('insert_link'),
                                        onBold: () =>
                                            _editor.formatSelection('bold'),
                                        onItalic: () =>
                                            _editor.formatSelection('italic'),
                                        onQuote: () => _editor.formatSelection(
                                          'formatBlock',
                                          'blockquote',
                                        ),
                                        onLink: _insertLink,
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                : _LoadError(message: _loadError!),
            bottomNavigationBar: MediaQuery.viewInsetsOf(context).bottom > 0
                ? _MarkdownSymbolBar(onPressed: _editor.insertTextAtCursor)
                : null,
          ),
        );
      },
    );
  }

  PopupMenuItem<_EditorCommand> _menuItem(
    _EditorCommand command,
    IconData icon,
    String label,
  ) {
    return PopupMenuItem(
      value: command,
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Flexible(child: Text(label)),
        ],
      ),
    );
  }
}

class _SelectionToolbar extends StatelessWidget {
  const _SelectionToolbar({
    required this.selection,
    required this.maxWidth,
    required this.maxHeight,
    required this.boldTooltip,
    required this.italicTooltip,
    required this.linkTooltip,
    required this.onBold,
    required this.onItalic,
    required this.onQuote,
    required this.onLink,
  });

  final EditorSelection selection;
  final double maxWidth;
  final double maxHeight;
  final String boldTooltip;
  final String italicTooltip;
  final String linkTooltip;
  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onQuote;
  final VoidCallback onLink;

  @override
  Widget build(BuildContext context) {
    const width = 192.0;
    const height = 48.0;
    const gap = 8.0;
    final left = (selection.x - width / 2)
        .clamp(8.0, math.max(8.0, maxWidth - width - 8))
        .toDouble();
    final above = selection.top - height - gap;
    final below = selection.top + selection.height + gap;
    final top = above >= 8
        ? above
        : (below + height <= maxHeight - 8
              ? below
              : (maxHeight - height - 8)
                    .clamp(8.0, double.infinity)
                    .toDouble());
    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: Material(
        elevation: 4,
        color: Theme.of(context).colorScheme.inverseSurface,
        borderRadius: BorderRadius.circular(8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              tooltip: boldTooltip,
              onPressed: onBold,
              icon: const Icon(Icons.format_bold),
              color: Theme.of(context).colorScheme.onInverseSurface,
            ),
            IconButton(
              tooltip: 'Quote',
              onPressed: onQuote,
              icon: const Icon(Icons.format_quote),
              color: Theme.of(context).colorScheme.onInverseSurface,
            ),
            IconButton(
              tooltip: italicTooltip,
              onPressed: onItalic,
              icon: const Icon(Icons.format_italic),
              color: Theme.of(context).colorScheme.onInverseSurface,
            ),
            IconButton(
              tooltip: linkTooltip,
              onPressed: onLink,
              icon: const Icon(Icons.link),
              color: Theme.of(context).colorScheme.onInverseSurface,
            ),
          ],
        ),
      ),
    );
  }
}

class _MarkdownSymbolBar extends StatelessWidget {
  const _MarkdownSymbolBar({required this.onPressed});

  final ValueChanged<String> onPressed;

  static const symbols = <String>[
    '# ',
    '*',
    '- ',
    '1. ',
    '> ',
    '[ ]',
    '![image]()',
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainer,
        child: SizedBox(
          height: 48,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Wrap(
              spacing: 4,
              children: [
                for (final symbol in symbols)
                  TextButton(
                    onPressed: () => onPressed(symbol),
                    child: Text(symbol),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 56,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              l.t('load_failed'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
