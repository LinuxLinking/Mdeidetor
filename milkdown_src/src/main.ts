/**
 * Milkdown v7 编辑器入口。
 *
 * Vite 打包为 IIFE 单文件 `assets/web/editor.js`,由 Flutter WebView 通过
 * `loadFlutterAsset('assets/web/index.html')` 加载。
 *
 * 对齐 docs/dev-doc.md 第 8.2 节。
 *
 * Phase 6 修复:
 *   - 删除 `@milkdown/kit/plugin/prism`(v7.22.1 该路径不存在)
 *   - 改用 `@milkdown/kit/component/code-block`(v7 内置 CodeMirror 代码块组件)
 *   - 修正 CSS 路径为 `@milkdown/theme-nord/style.css`
 */
import { Editor, rootCtx, defaultValueCtx } from '@milkdown/kit/core';
import { commonmark } from '@milkdown/kit/preset/commonmark';
import { gfm } from '@milkdown/kit/preset/gfm';
import { history } from '@milkdown/kit/plugin/history';
import { clipboard } from '@milkdown/kit/plugin/clipboard';
import { listener, listenerCtx } from '@milkdown/kit/plugin/listener';
import { cursor } from '@milkdown/kit/plugin/cursor';
import { codeBlockComponent, codeBlockConfig } from '@milkdown/kit/component/code-block';
import { nord } from '@milkdown/theme-nord';
import '@milkdown/theme-nord/style.css';

import { setupBridge, postBridge } from './bridge';

let editor: Editor | null = null;

/**
 * Keep the editing surface usable if a Milkdown plugin fails to initialise on
 * an older Android WebView.  A blank WebView is much worse than a plain
 * Markdown textarea: users can still open, edit and save the document.
 */
function mountFallback(root: HTMLElement, initialContent: string): void {
  root.innerHTML = '';
  const textarea = document.createElement('textarea');
  textarea.value = initialContent;
  textarea.setAttribute('aria-label', 'Markdown source');
  textarea.addEventListener('input', () => {
    postBridge('changed', { md: textarea.value });
  });
  root.appendChild(textarea);
  window.bridge = {
    init: async () => {},
    setContent: (md: string) => { textarea.value = md; },
    getContent: () => textarea.value,
    getHTML: () => `<pre>${textarea.value.replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c] ?? c))}</pre>`,
    setMode: () => {},
    setTheme: () => {},
    applyPatches: () => {},
    renderMermaid: () => {},
  };
  postBridge('ready');
}

async function init(opts: { initialContent: string; theme: string }): Promise<void> {
  const root = document.getElementById('app');
  try {
    if (!root) throw new Error('#app element not found');

    editor = await Editor.make()
      .enable(commonmark)
      .enable(gfm)
      .enable(history)
      .enable(clipboard)
      .enable(cursor)
      .enable(listener)
      .use(codeBlockComponent)
      .config((ctx) => {
        ctx.set(rootCtx, root);
        ctx.set(defaultValueCtx, opts.initialContent);
        // 代码块组件配置:languages 为空数组时,CodeMirror 用纯文本模式
        // (等宽字体 + 灰底,无语法高亮)。要支持高亮,需在此注入
        // @codemirror/language-data 的 LanguageDescription[]。
        // 当前版本:无高亮,但代码块可编辑、可换行、可复制。
        ctx.set(codeBlockConfig.key, {
          extensions: [],
          languages: [],
          expandIcon: '⬇',
          searchIcon: '🔍',
          clearSearchIcon: '⌫',
          searchPlaceholder: '搜索语言',
          noResultText: '无结果',
          copyText: '复制',
          copyIcon: '📋',
          onCopy: () => {},
          renderLanguage: (lang: string) => lang,
          renderPreview: () => null,
          previewToggleButton: (previewOnly: boolean) => previewOnly ? '编辑' : '隐藏',
          previewLabel: '预览',
          previewLoading: '加载中...',
        });
        ctx.get(listenerCtx).markdownUpdated((_ctx, md) => {
          postBridge('changed', { md });
        });
      })
      .use(nord)
      .create();

    setupBridge(editor);
    postBridge('ready');
  } catch (e) {
    // Do not leave #app empty when Milkdown is incompatible with the device.
    // The fallback still fulfils the core open/edit/save workflow.
    if (root) mountFallback(root, opts.initialContent);
    postBridge('error', { message: String(e) });
    console.error('Milkdown initialisation failed; using textarea fallback', e);
  }
}

// 暴露给 Flutter 端 runJavaScript 调用。
// init() 完成前(setupBridge 未执行),setContent/getContent 等为 noop/空;
// init() 内部调用 setupBridge 后会覆盖为真实实现。
window.bridge = {
  init,
  setContent: (_md: string) => { /* init 前为 noop */ },
  getContent: () => '',
  getHTML: () => '',
  setMode: (_mode: 'wysiwyg' | 'source') => { /* TODO Phase 1+ */ },
  setTheme: (_variables) => { /* setupBridge installs the DOM implementation */ },
  applyPatches: (_patches) => { /* setupBridge installs the DOM implementation */ },
  renderMermaid: (_source, _hash) => { /* setupBridge installs the native request */ },
};
