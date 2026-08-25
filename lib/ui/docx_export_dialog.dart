import 'package:flutter/material.dart';

import '../export/docx_export/docx_options.dart';
import '../l10n/app_localizations.dart';

class DocxExportDialog extends StatefulWidget {
  const DocxExportDialog({super.key});

  @override
  State<DocxExportDialog> createState() => _DocxExportDialogState();
}

class _DocxExportDialogState extends State<DocxExportDialog> {
  bool _includeToc = false;
  bool _includeHeaderFooter = false;
  final _headerCtrl = TextEditingController();
  final _footerCtrl = TextEditingController();

  @override
  void dispose() {
    _headerCtrl.dispose();
    _footerCtrl.dispose();
    super.dispose();
  }

  void _confirm() {
    Navigator.of(context).pop(
      DocxOptions(
        includeToc: _includeToc,
        includeHeaderFooter: _includeHeaderFooter,
        headerText: _blankToNull(_headerCtrl.text),
        footerText: _blankToNull(_footerCtrl.text),
      ),
    );
  }

  String? _blankToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.t('docx_options_title')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: Text(l.t('include_toc')),
                subtitle: Text(l.t('include_toc_desc')),
                value: _includeToc,
                onChanged: (v) => setState(() => _includeToc = v),
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                title: Text(l.t('include_header_footer')),
                value: _includeHeaderFooter,
                onChanged: (v) => setState(() => _includeHeaderFooter = v),
                contentPadding: EdgeInsets.zero,
              ),
              if (_includeHeaderFooter) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _headerCtrl,
                  decoration: InputDecoration(
                    labelText: l.t('header_text'),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _footerCtrl,
                  decoration: InputDecoration(
                    labelText: l.t('footer_text'),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.t('cancel')),
        ),
        FilledButton(onPressed: _confirm, child: Text(l.t('export'))),
      ],
    );
  }
}
