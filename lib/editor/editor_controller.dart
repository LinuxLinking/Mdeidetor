import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../native/native_render_channel.dart';

class EditorSelection {
  const EditorSelection({
    required this.text,
    required this.start,
    required this.end,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final String text;
  final int start;
  final int end;
  final double left;
  final double top;
  final double width;
  final double height;

  double get x => left + width / 2;
  double get y => top;

  bool get isCollapsed => start == end || text.isEmpty;
}

/// 编辑器模式：WYSIWYG（所见即所得）/ 源码。
/// 当前编辑器资源失败时会降级为 textarea；模式切换由 bridge 负责。
/// Milkdown 真实产物覆盖后由 `bridge.setMode` 实现。
enum EditorMode { wysiwyg, source }

/// 编辑器控制器：封装 WebView + Milkdown(JS Bridge)的生命周期与操作。
/// 设计参见 dev-doc.md 第 7.1 节，接口契约参见第 8.3 节。
/// 流程:
///   1. [bindWebView] 注入 WebViewController,注册 `MdBridge` JS channel
///   2. WebView 加载 `assets/web/index.html` 完成 �?`_onPageFinished`
///   3. `_onPageFinished` �?`window.bridge.init({initialContent, theme})`
///   4. JS �?Milkdown 初始化完�?�?`MdBridge.postMessage({type:'ready'})`
///   5. 用户编辑 �?`MdBridge.postMessage({type:'changed', md})` �?[onContentChanged]
class EditorController extends ChangeNotifier {
  WebViewController? _wvc;

  /// Milkdown 是否已完成 init（收到 `ready` 消息）。
  bool _isReady = false;
  bool _isDirty = false;
  String _lastContent = '';
  EditorSelection? _selection;
  NativeEditorTheme? _nativeTheme;
  int _renderGeneration = 0;
  Timer? _renderDebounce;
  bool _renderInFlight = false;
  String? _pendingNativeMarkdown;

  bool get isReady => _isReady;
  bool get isDirty => _isDirty;
  EditorSelection? get selection => _selection;

  /// 注入 WebViewController 并注册 JS Bridge channel。
  /// EditorPage �?`initState` 中创�?`WebViewController`(cascade 配置
  /// `setJavaScriptMode(unrestricted)` + `loadFlutterAsset('assets/web/index.html')`)
  /// 后调用本方法注入 channel，然后 `_editor.bindWebView(_wvc)`。
  void bindWebView(WebViewController wvc) {
    _wvc = wvc
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: _onPageFinished,
        onWebResourceError: (error) {
          debugPrint('EditorController: WebView error: ${error.description} (${error.errorType})');
        },
      ))
      ..addJavaScriptChannel('MdBridge', onMessageReceived: _onBridgeMessage);
  }

  /// 初始内容（在 WebView 加载完成、init() 调用前由 EditorPage 设置）。
  String? pendingInitialContent;
  String theme = 'light';

  /// 生成只含 ASCII 的 JS 字符串字面量。
  /// 所有非 ASCII 字符转义为 `\uXXXX`，避免 Android WebView 在
  /// MethodChannel/evaluateJavascript 链路中发生编码差异。
  /// helper 同样处理 JSON 特殊字符（引号、反斜杠、控制字符）。
  String _jsStringLiteral(String s) {
    // 1) 先用 jsonEncode 处理引号/反斜�?控制字符(输出含中文字�?
    final json = jsonEncode(s);
    // 2) 把所有非 ASCII 码点�?\uXXXX,确保最终字面量�?ASCII
    final buf = StringBuffer();
    for (int i = 0; i < json.length; i++) {
      final c = json.codeUnitAt(i);
      if (c < 0x80) {
        buf.writeCharCode(c);
      } else {
        // Dart String �?UTF-16,代理对会拆成两个 codeUnit,各自转义
        // V8 解析 \uD83D\uDE00 这种代理对序列会正确组合�?emoji
        buf.write('\\u${c.toRadixString(16).padLeft(4, '0')}');
      }
    }
    return buf.toString();
  }

  /// WebView 页面加载完成时回调，调用 `window.bridge.init` 启动 Milkdown。
  void _onPageFinished(String url) {
    final md = pendingInitialContent ?? '';
    final js = 'if (window.bridge && window.bridge.init) {'
        'window.bridge.init({'
        'initialContent: ${_jsStringLiteral(md)}, '
        'theme: ${_jsStringLiteral(theme)}'
        '});'
        '} else {'
        // This branch handles a script parse/load failure in the WebView.
        'var r=document.getElementById("app");'
        'if(r){r.innerHTML="";var t=document.createElement("textarea");'
        't.value=${_jsStringLiteral(md)};t.style.cssText="width:100%;height:100%;padding:18px;";'
        'r.appendChild(t);'
        't.addEventListener("input",function(){window.MdBridge&&window.MdBridge.postMessage(JSON.stringify({type:"changed",md:t.value}));});'
        'window.bridge={getContent:function(){return t.value;},getHTML:function(){return "<pre>"+t.value+"</pre>";},setContent:function(v){t.value=v;},setMode:function(){},setTheme:function(){}};'
        'window.MdBridge&&window.MdBridge.postMessage(JSON.stringify({type:"ready"}));}'
        '}';
    _wvc?.runJavaScript(js);
  }

  /// 接收 JS 通过 `MdBridge.postMessage(json)` 推送的消息。
  void _onBridgeMessage(JavaScriptMessage msg) {
    try {
      final data = jsonDecode(msg.message) as Map<String, dynamic>;
      final payload = data['payload'] is Map
          ? (data['payload'] as Map).cast<String, dynamic>()
          : const <String, dynamic>{};
      debugPrint('EditorController: received bridge message type=${data['type']}');
      switch (data['type']) {
        case 'ready':
          debugPrint('EditorController: Milkdown ready!');
          _isReady = true;
          notifyListeners();
          final initial = pendingInitialContent;
          if (initial != null) {
            // The file may finish reading after onPageFinished. Re-apply it
            // now that the JavaScript editor is guaranteed to exist.
            pendingInitialContent = null;
            unawaited(loadContent(initial));
          } else {
            _scheduleNativeRender(_lastContent);
          }
          break;
        case 'changed':
          _lastContent =
              (data['md'] as String?) ?? (payload['md'] as String?) ?? '';
          if (!_isDirty) {
            _isDirty = true;
            notifyListeners();
          }
          _scheduleNativeRender(_lastContent);
          break;
        case 'selection':
          final selectionData = data['payload'] is Map
              ? (data['payload'] as Map).cast<String, dynamic>()
              : data;
          final next = EditorSelection(
            text: selectionData['text'] as String? ?? '',
            start: (selectionData['start'] as num?)?.toInt() ?? 0,
            end: (selectionData['end'] as num?)?.toInt() ?? 0,
            left: (selectionData['left'] as num?)?.toDouble() ??
                (selectionData['x'] as num?)?.toDouble() ?? 0,
            top: (selectionData['top'] as num?)?.toDouble() ??
                (selectionData['y'] as num?)?.toDouble() ?? 0,
            width: (selectionData['width'] as num?)?.toDouble() ?? 0,
            height: (selectionData['height'] as num?)?.toDouble() ?? 0,
          );
          _selection = next.isCollapsed ? null : next;
          notifyListeners();
          break;
        case 'mermaidRequest':
          final request = data['payload'] is Map
              ? (data['payload'] as Map).cast<String, dynamic>()
              : data;
          unawaited(_renderRequestedMermaid(
            request['source'] as String? ?? '',
            request['hash'] as String? ?? '',
          ));
          break;
        case 'codeCopy':
          unawaited(NativeRenderChannel.copyText(payload['text'] as String? ?? ''));
          break;
        case 'error':
          // TODO Phase 1+: 上报错误(SnackBar / 日志)
          break;
      }
    } catch (e) {
      // 忽略无法解析的消息。
    }
  }

  Future<void> _renderRequestedMermaid(String source, String hash) async {
    if (source.isEmpty || _wvc == null || !_isReady) return;
    // NativeRenderChannel.renderMermaid is cache-first (MD5 keyed). A direct
    // cached lookup is available for callers that already know the hash.
    final svg = hash.isNotEmpty
        ? await NativeRenderChannel.getCachedMermaid(hash) ??
            await NativeRenderChannel.renderMermaid(source)
        : await NativeRenderChannel.renderMermaid(source);
    if (svg == null || _wvc == null) return;
    await _wvc!.runJavaScript(
      'window.nativeFeatures && window.nativeFeatures.applyNativeMermaid('
      '${_jsStringLiteral(source)}, ${_jsStringLiteral(svg)})',
    );
  }

  Future<void> setNativeTheme(NativeEditorTheme theme) async {
    _nativeTheme = theme;
    await NativeRenderChannel.setTheme(theme);
    if (_wvc == null) return;
    await _wvc!.runJavaScript(
      'window.bridge && window.bridge.setTheme && window.bridge.setTheme('
      '${_jsObjectLiteral(theme.variables)});'
      'window.nativeFeatures && window.nativeFeatures.setTheme('
      '${_jsObjectLiteral(theme.variables)})',
    );
    if (_lastContent.isNotEmpty) _scheduleNativeRender(_lastContent);
  }

  Future<void> insertSymbol(String symbol) async {
    if (_wvc == null || !_isReady) return;
    await _wvc!.runJavaScript(
      'window.nativeFeatures && window.nativeFeatures.insertAtSelection('
      '${_jsStringLiteral(symbol)})',
    );
  }

  Future<void> insertTextAtCursor(String text) => insertSymbol(text);

  Future<void> formatSelection(String command, [String? value]) async {
    if (_wvc == null || !_isReady) return;
    await _wvc!.runJavaScript(
      'window.nativeFeatures && window.nativeFeatures.formatSelection('
      '${_jsStringLiteral(command)}, ${_jsStringLiteral(value ?? '')})',
    );
    _selection = null;
    notifyListeners();
  }

  String _jsObjectLiteral(Map<String, String> value) {
    return jsonEncode(value).replaceAllMapped(
      RegExp(r'[^\x00-\x7F]'),
      (match) => '\\u${match.group(0)!.codeUnitAt(0).toRadixString(16).padLeft(4, '0')}',
    );
  }

  void _scheduleNativeRender(String markdown) {
    _pendingNativeMarkdown = markdown;
    _renderDebounce?.cancel();
    _renderDebounce = Timer(const Duration(milliseconds: 32), _drainNativeRender);
  }

  Future<void> _drainNativeRender() async {
    if (_renderInFlight) return;
    final markdown = _pendingNativeMarkdown;
    if (markdown == null) return;
    _pendingNativeMarkdown = null;
    _renderInFlight = true;
    try {
      await _renderNative(markdown);
    } finally {
      _renderInFlight = false;
      if (_pendingNativeMarkdown != null) {
        _renderDebounce?.cancel();
        _renderDebounce = Timer(Duration.zero, _drainNativeRender);
      }
    }
  }

  Future<void> _renderNative(String markdown) async {
    final theme = _nativeTheme;
    if (theme == null || _wvc == null) return;
    final generation = ++_renderGeneration;
    final result = await NativeRenderChannel.renderMarkdown(
      markdown: markdown,
      theme: theme,
    );
    if (result == null || generation != _renderGeneration || _wvc == null) return;
    final patches = result.patches.map((patch) => patch.toMap()).toList(growable: false);
    await _wvc!.runJavaScript(
      'window.nativeFeatures && window.nativeFeatures.applyPatches('
      '${_jsObjectLiteralList(patches)})',
    );
    await _renderNativeEmbeds(markdown, generation);
  }

  Future<void> _renderNativeEmbeds(String markdown, int generation) async {
    final blockLatex = RegExp(
      r'\$\$([\s\S]*?)\$\$',
      multiLine: true,
    ).allMatches(markdown).map((match) => match.group(1)!.trim()).toSet();
    final inlineLatex = RegExp(r'\\\((.+?)\\\)')
        .allMatches(markdown)
        .map((match) => match.group(1)!.trim())
        .toSet();

    await Future.wait(<Future<void>>[
      for (final source in blockLatex)
        _applyNativeEmbed(
          source: source,
          generation: generation,
          render: () => NativeRenderChannel.renderLatex(source, display: true),
          javascriptMethod: 'applyNativeLatex',
          extraArgument: ', true',
        ),
      for (final source in inlineLatex)
        _applyNativeEmbed(
          source: source,
          generation: generation,
          render: () => NativeRenderChannel.renderLatex(source),
          javascriptMethod: 'applyNativeLatex',
          extraArgument: ', false',
        ),
    ]);
  }

  Future<void> _applyNativeEmbed({
    required String source,
    required int generation,
    required Future<String?> Function() render,
    required String javascriptMethod,
    required String extraArgument,
  }) async {
    final html = await render();
    if (html == null || generation != _renderGeneration || _wvc == null) return;
    await _wvc!.runJavaScript(
      'window.nativeFeatures && window.nativeFeatures.$javascriptMethod('
      '${_jsStringLiteral(source)}, ${_jsStringLiteral(html)}$extraArgument)',
    );
  }

  String _jsObjectLiteralList(List<Map<String, Object>> value) {
    return jsonEncode(value).replaceAllMapped(
      RegExp(r'[^\x00-\x7F]'),
      (match) => '\\u${match.group(0)!.codeUnitAt(0).toRadixString(16).padLeft(4, '0')}',
    );
  }

  /// 加载新内容（替换编辑器内容并重置 dirty）。
  Future<void> loadContent(String md) async {
    _lastContent = md;
    if (_wvc == null) {
      pendingInitialContent = md;
      return;
    }
    if (!_isReady) {
      // Milkdown 尚未 init,先暂�?�?'ready' 后再 setContent
      pendingInitialContent = md;
      return;
    }
    await _wvc!.runJavaScript(
      'window.bridge.setContent(${_jsStringLiteral(md)})',
    );
    _scheduleNativeRender(md);
    _isDirty = false;
    notifyListeners();
  }

  /// 获取当前 md 文本（JS 异步返回）。
  /// 反向链路(JS �?Dart):V8 �?evaluateJavascript 自动 JSON.stringify
  /// MethodChannel 返回 JSON 编码的字符串，使用 jsonDecode 还原。
  Future<String> getContent() async {
    if (_wvc == null || !_isReady) return pendingInitialContent ?? _lastContent;
    final result = await _wvc!.runJavaScriptReturningResult(
      'window.bridge.getContent()',
    );
    // JS 端返回字符串字面�?Flutter 端收到的�?JSON 编码形式(带引号、转�?
    return jsonDecode(result.toString()) as String;
  }

  /// 获取渲染后的 HTML（用于 PDF 导出）。
  Future<String> getHTML() async {
    if (_wvc == null || !_isReady) return '';
    final result = await _wvc!.runJavaScriptReturningResult(
      'window.bridge.getHTML()',
    );
    return jsonDecode(result.toString()) as String;
  }

  /// 切换模式（当前 Milkdown 产物暂不实现源码模式）。
  Future<void> setMode(EditorMode mode) async {
    if (_wvc == null || !_isReady) return;
    await _wvc!.runJavaScript('window.bridge.setMode("${mode.name}")');
  }

  /// 标记已保存（重置 dirty）。
  void markSaved() {
    _isDirty = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _renderDebounce?.cancel();
    _pendingNativeMarkdown = null;
    _wvc = null;
    super.dispose();
  }
}
