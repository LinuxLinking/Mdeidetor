import 'package:flutter/services.dart';

/// Theme data shared by the Flutter shell and the Android renderer.
class NativeEditorTheme {
  const NativeEditorTheme({required this.name, required this.variables});

  final String name;
  final Map<String, String> variables;

  Map<String, Object> toMap() => <String, Object>{
    'name': name,
    'variables': variables,
  };
}

class NativeRenderResult {
  const NativeRenderResult({
    required this.html,
    required this.changed,
    required this.changedStart,
    required this.changedEnd,
    required this.mermaidCacheHits,
    required this.patches,
    required this.parsedBlockCount,
  });

  final String html;
  final bool changed;
  final int changedStart;
  final int changedEnd;
  final int mermaidCacheHits;
  final List<NativeDomPatch> patches;
  final int parsedBlockCount;

  factory NativeRenderResult.fromMap(Map<Object?, Object?> map) {
    return NativeRenderResult(
      html: map['html'] as String? ?? '',
      changed: map['changed'] as bool? ?? true,
      changedStart: (map['changedStart'] as num?)?.toInt() ?? 0,
      changedEnd: (map['changedEnd'] as num?)?.toInt() ?? 0,
      mermaidCacheHits: (map['mermaidCacheHits'] as num?)?.toInt() ?? 0,
      patches: (map['patches'] as List<Object?>? ?? const <Object?>[])
          .whereType<Map>()
          .map(
            (value) => NativeDomPatch.fromMap(value.cast<Object?, Object?>()),
          )
          .toList(growable: false),
      parsedBlockCount: (map['parsedBlockCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class NativeDomPatch {
  const NativeDomPatch({
    this.type = 'splice',
    this.path = '',
    required this.from,
    required this.deleteCount,
    required this.html,
  });

  final String type;
  final String path;
  final int from;
  final int deleteCount;
  final List<String> html;

  factory NativeDomPatch.fromMap(Map<Object?, Object?> map) {
    return NativeDomPatch(
      type: map['type'] as String? ?? 'splice',
      path: map['path'] as String? ?? '',
      from: (map['from'] as num?)?.toInt() ?? 0,
      deleteCount: (map['deleteCount'] as num?)?.toInt() ?? 0,
      html: (map['html'] as List<Object?>? ?? const <Object?>[])
          .whereType<String>()
          .toList(growable: false),
    );
  }

  Map<String, Object> toMap() => <String, Object>{
    'type': type,
    'path': path,
    'from': from,
    'deleteCount': deleteCount,
    'html': html,
  };
}

class NativeRenderEvent {
  const NativeRenderEvent(this.type, this.payload);

  final String type;
  final Map<Object?, Object?> payload;
}

/// Dart facade for the optional Android-native Markdown renderer.
///
/// The WebView remains the editing surface. This channel is used for native
/// parsing/rendering, cached Mermaid SVG generation, clipboard operations and
/// export, so the UI can degrade to the existing WebView implementation when
/// the platform implementation is not available (for example in widget tests).
class NativeRenderChannel {
  NativeRenderChannel._();

  static const MethodChannel _methods = MethodChannel('mdeditor/render');
  static const EventChannel _events = EventChannel('mdeditor/render/events');

  static Stream<NativeRenderEvent> get events =>
      _events.receiveBroadcastStream().map((Object? event) {
        final map = (event as Map).cast<Object?, Object?>();
        return NativeRenderEvent(
          map['type'] as String? ?? 'unknown',
          map['payload'] is Map
              ? (map['payload'] as Map).cast<Object?, Object?>()
              : const <Object?, Object?>{},
        );
      });

  static Future<NativeRenderResult?> renderMarkdown({
    required String markdown,
    required NativeEditorTheme theme,
  }) async {
    try {
      final value = await _methods.invokeMethod<Object?>('renderMarkdown', {
        'markdown': markdown,
        'theme': theme.toMap(),
      });
      if (value is! Map) return null;
      return NativeRenderResult.fromMap(value.cast<Object?, Object?>());
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static Future<void> setTheme(NativeEditorTheme theme) async {
    try {
      await _methods.invokeMethod<void>('setTheme', theme.toMap());
    } on MissingPluginException {
      // iOS/desktop and test environments can continue with WebView CSS.
    }
  }

  static Future<String?> renderMermaid(String source) async {
    try {
      return await _methods.invokeMethod<String>('renderMermaid', {
        'source': source,
      });
    } on MissingPluginException {
      return null;
    }
  }

  static Future<String?> getCachedMermaid(String hash) async {
    try {
      return await _methods.invokeMethod<String>('getCachedMermaid', {'hash': hash});
    } on MissingPluginException {
      return null;
    }
  }

  static Future<String?> renderLatex(
    String source, {
    bool display = false,
  }) async {
    try {
      return await _methods.invokeMethod<String>('renderLatex', {
        'source': source,
        'display': display,
      });
    } on MissingPluginException {
      return null;
    }
  }

  static Future<void> copyText(String text) async {
    try {
      await _methods.invokeMethod<void>('copyText', {'text': text});
    } on MissingPluginException {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  static Future<String?> exportHtml({
    required String markdown,
    required String fileName,
    required NativeEditorTheme theme,
  }) async {
    try {
      return await _methods.invokeMethod<String>('exportHtml', {
        'markdown': markdown,
        'fileName': fileName,
        'theme': theme.toMap(),
      });
    } on MissingPluginException {
      return null;
    }
  }

  static Future<String?> exportPdf({
    required String markdown,
    required String fileName,
    required NativeEditorTheme theme,
  }) async {
    try {
      return await _methods.invokeMethod<String>('exportPdf', {
        'markdown': markdown,
        'fileName': fileName,
        'theme': theme.toMap(),
      });
    } on MissingPluginException {
      return null;
    }
  }

  static Future<void> registerInterceptor({
    required String name,
    required String pattern,
  }) async {
    try {
      await _methods.invokeMethod<void>('registerInterceptor', {
        'name': name,
        'pattern': pattern,
      });
    } on MissingPluginException {
      // Registration is an Android extension point; keep callers portable.
    }
  }
}
