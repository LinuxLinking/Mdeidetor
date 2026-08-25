import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Lightweight hand-written localization used by the Flutter shell UI.
class AppLocalizations {
  AppLocalizations(this._dict);

  final Map<String, String> _dict;

  String t(String key) => _dict[key] ?? key;

  String format(String key, Map<String, Object> values) {
    var text = t(key);
    for (final entry in values.entries) {
      text = text.replaceAll('{${entry.key}}', entry.value.toString());
    }
    return text;
  }

  static const _zh = <String, String>{
    'app_title': 'Mdeditor',
    'settings': '设置',
    'new_doc': '新建',
    'open': '打开',
    'save': '保存',
    'save_as': '另存为',
    'export_pdf': '导出 PDF',
    'export_docx': '导出 DOCX',
    'export_html': '导出 HTML',
    'cancel': '取消',
    'confirm': '确定',
    'delete': '移除',
    'more': '更多',
    'untitled': '未命名.md',
    'no_recent_title': '还没有最近文件',
    'no_recent_body': '新建一个 Markdown 文档，或从设备中打开现有文件。',
    'no_recent': '暂无最近文件。点击右上角“打开”或“新建”。',
    'recent_files': '最近文件',
    'last_opened': '上次打开：{time}',
    'remove_recent': '从最近列表移除',
    'appearance': '外观',
    'font': '字体',
    'editor_theme': '编辑器主题',
    'render_theme': '渲染主题',
    'github_light': 'GitHub Light',
    'github_dark': 'GitHub Dark',
    'vue_theme': 'Vue',
    'editor_theme_desc': '同步应用到原生解析器与 WebView 渲染层',
    'theme_system': '跟随系统',
    'theme_system_desc': '浅色和深色自动切换',
    'theme_light': '浅色',
    'theme_dark': '深色',
    'text_scale_small': '小',
    'text_scale_standard': '标准',
    'text_scale_large': '大',
    'about': '关于',
    'about_subtitle': 'Markdown 编辑器 · v1.0.0+1',
    'editor_not_ready': '编辑器尚未就绪，请稍候',
    'content_empty': '内容为空，无法导出',
    'load_failed': '加载失败',
    'saved_file': '已保存：{name}',
    'save_failed': '保存失败',
    'saved_as_file': '已另存为：{name}',
    'save_as_failed': '另存为失败',
    'pdf_exported': '已导出 PDF：{name}',
    'pdf_export_failed': '导出 PDF 失败',
    'html_exported': '已导出 HTML：{name}',
    'html_export_failed': '导出 HTML 失败',
    'insert_link': '插入链接',
    'format_bold': '加粗',
    'format_italic': '斜体',
    'link_url': '链接地址',
    'generating_docx': '正在生成 DOCX...',
    'docx_exported': '已导出 DOCX：{name}',
    'docx_generate_failed': '生成 DOCX 失败',
    'write_failed': '写入文件失败',
    'discard_changes_title': '放弃未保存的更改？',
    'discard_changes_body': '当前文档还有未保存内容，返回后这些更改不会自动保留。',
    'discard_changes': '放弃更改',
    'docx_options_title': '导出 DOCX 选项',
    'include_toc': '包含目录（TOC）',
    'include_toc_desc': 'Word 打开后可右键更新域生成目录',
    'include_header_footer': '包含页眉页脚',
    'header_text': '页眉文本',
    'footer_text': '页脚文本',
    'export': '导出',
  };

  static const _en = <String, String>{
    'app_title': 'Mdeditor',
    'settings': 'Settings',
    'new_doc': 'New',
    'open': 'Open',
    'save': 'Save',
    'save_as': 'Save As',
    'export_pdf': 'Export PDF',
    'export_docx': 'Export DOCX',
    'export_html': 'Export HTML',
    'cancel': 'Cancel',
    'confirm': 'OK',
    'delete': 'Remove',
    'more': 'More',
    'untitled': 'Untitled.md',
    'no_recent_title': 'No recent files',
    'no_recent_body':
        'Create a Markdown document or open one from this device.',
    'no_recent': 'No recent files. Tap "Open" or "New" in the top right.',
    'recent_files': 'Recent files',
    'last_opened': 'Last opened: {time}',
    'remove_recent': 'Remove from recent files',
    'appearance': 'Appearance',
    'font': 'Font',
    'editor_theme': 'Editor theme',
    'render_theme': 'Rendering theme',
    'github_light': 'GitHub Light',
    'github_dark': 'GitHub Dark',
    'vue_theme': 'Vue',
    'editor_theme_desc': 'Applied to the native parser and WebView renderer',
    'theme_system': 'Follow system',
    'theme_system_desc': 'Switches automatically between light and dark',
    'theme_light': 'Light',
    'theme_dark': 'Dark',
    'text_scale_small': 'Small',
    'text_scale_standard': 'Standard',
    'text_scale_large': 'Large',
    'about': 'About',
    'about_subtitle': 'Markdown editor · v1.0.0+1',
    'editor_not_ready': 'Editor is not ready, please wait',
    'content_empty': 'Content is empty, cannot export',
    'load_failed': 'Load failed',
    'saved_file': 'Saved: {name}',
    'save_failed': 'Save failed',
    'saved_as_file': 'Saved as: {name}',
    'save_as_failed': 'Save As failed',
    'pdf_exported': 'Exported PDF: {name}',
    'pdf_export_failed': 'Export PDF failed',
    'html_exported': 'Exported HTML: {name}',
    'html_export_failed': 'Export HTML failed',
    'insert_link': 'Insert link',
    'format_bold': 'Bold',
    'format_italic': 'Italic',
    'link_url': 'Link URL',
    'generating_docx': 'Generating DOCX...',
    'docx_exported': 'Exported DOCX: {name}',
    'docx_generate_failed': 'DOCX generation failed',
    'write_failed': 'Write to file failed',
    'discard_changes_title': 'Discard unsaved changes?',
    'discard_changes_body': 'This document has unsaved changes. They will not be kept automatically.',
    'discard_changes': 'Discard changes',
    'docx_options_title': 'DOCX export options',
    'include_toc': 'Include table of contents',
    'include_toc_desc': 'Open in Word and update fields to generate the TOC',
    'include_header_footer': 'Include header and footer',
    'header_text': 'Header text',
    'footer_text': 'Footer text',
    'export': 'Export',
  };

  static AppLocalizations of(BuildContext context) {
    final localizations = Localizations.of<AppLocalizations>(
      context,
      AppLocalizations,
    );
    return localizations ?? AppLocalizations(_zh);
  }

  static const supportedLocales = <Locale>[Locale('zh'), Locale('en')];

  static const delegates = <LocalizationsDelegate<dynamic>>[
    _AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    final lang = locale.languageCode;
    return lang == 'zh' || lang == 'en';
  }

  @override
  Future<AppLocalizations> load(Locale locale) {
    final dict = locale.languageCode == 'en'
        ? AppLocalizations._en
        : AppLocalizations._zh;
    return Future.value(AppLocalizations(dict));
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
