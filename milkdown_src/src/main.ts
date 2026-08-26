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
import { LanguageDescription, StreamLanguage } from '@codemirror/language';
import { HighlightStyle, syntaxHighlighting } from '@codemirror/language';
import { tags } from '@lezer/highlight';
import { keymap } from '@milkdown/kit/prose/keymap';
import { inputRules, InputRule } from '@milkdown/kit/prose/inputrules';
import { nord } from '@milkdown/theme-nord';
import '@milkdown/theme-nord/style.css';

import { setupBridge, postBridge } from './bridge';
import type { Plugin, Selection } from '@milkdown/kit/prose/state';
import { $prose } from '@milkdown/kit/utils';
import { TextSelection } from '@milkdown/kit/prose/state';

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

    // 自动补全:方括号/圆括号输入时自动插入配对;所有配对符号输入闭合时跳过已有的右符号。
    const skipChars = new Set(['*', '`', ']', ')']);
    const autoCloseKeymap = $prose(() => keymap({
      '[': (state: any, dispatch: any) => {
        if (state.selection.$from.parent.type.spec.code) return false;
        if (!state.selection.empty) return false;
        const pos = state.selection.from;
        const tr = state.tr.insertText('[]', pos, pos);
        tr.setSelection(TextSelection.create(tr.doc, pos + 1));
        dispatch(tr);
        return true;
      },
      '(': (state: any, dispatch: any) => {
        if (state.selection.$from.parent.type.spec.code) return false;
        if (!state.selection.empty) return false;
        const pos = state.selection.from;
        const tr = state.tr.insertText('()', pos, pos);
        tr.setSelection(TextSelection.create(tr.doc, pos + 1));
        dispatch(tr);
        return true;
      },
    }) as Plugin);
    // 输入闭合符号时:如果光标后面紧跟同样的符号,直接跳过而非重复插入。
    const closingRules = Array.from(skipChars).map(
      (ch) => new InputRule(new RegExp(`${ch.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`), (state) => {
        const { $from, empty } = state.selection;
        if (!empty || $from.parent.type.spec.code) return null;
        const next = state.doc.textBetween(
          state.selection.from,
          Math.min(state.selection.from + 1, state.doc.content.size),
        );
        return next === ch ? state.tr.insertText('') : null;
      }),
    );
    const closingInputRulesPlugin = $prose(() => inputRules({ rules: closingRules }) as any as Plugin);

    editor = await Editor.make()
      .use(commonmark)
      .use(gfm)
      .use(history)
      .use(clipboard)
      .use(cursor)
      .use(listener)
      .use(autoCloseKeymap)
      .use(closingInputRulesPlugin)
      .use(codeBlockComponent)
      .config((ctx) => {
        ctx.set(rootCtx, root);
        ctx.set(defaultValueCtx, opts.initialContent);
        // 代码块组件配置:使用 StreamLanguage 定义轻量语言支持。
        // 不依赖 @codemirror/language-data,保持 APK 体积可控。
        const codeHighlight = HighlightStyle.define([
          { tag: tags.comment, color: '#6a737d', fontStyle: 'italic' },
          { tag: tags.string, color: '#22863a' },
          { tag: tags.number, color: '#005cc5' },
          { tag: tags.keyword, color: '#d73a49', fontWeight: 'bold' },
          { tag: tags.typeName, color: '#6f42c1' },
          { tag: tags.function(tags.name), color: '#6f42c1' },
          { tag: tags.operator, color: '#d73a49' },
          { tag: tags.variableName, color: '#24292e' },
          { tag: tags.definition(tags.name), color: '#6f42c1' },
          { tag: tags.special(tags.string), color: '#e36209' },
        ]);
        const mkLang = (name: string, aliases: string[], keywords: string[], builtins: string[] = []) =>
          LanguageDescription.of({
            name,
            alias: aliases,
            support: StreamLanguage.define({
              token(stream, _state) {
                if (stream.match(/\/\/.*/)) return 'comment';
                if (stream.match(/\/\*[\s\S]*?\*\//)) return 'comment';
                if (stream.match(/#.*/)) return 'comment';
                if (stream.match(/"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`(?:[^`\\]|\\.)*`/)) return 'string';
                if (stream.match(/\b\d+\.?\d*\b/)) return 'number';
                if (stream.match(new RegExp('\\b(' + keywords.join('|') + ')\\b'))) return 'keyword';
                if (builtins.length && stream.match(new RegExp('\\b(' + builtins.join('|') + ')\\b'))) return 'typeName';
                if (stream.match(/\b[a-zA-Z_]\w*(?=\s*\()/)) return 'function';
                stream.next();
                return null;
              },
            }),
          });
        const langs = [
          mkLang('javascript', ['js', 'jsx', 'ts', 'typescript', 'tsx'],
            ['const','let','var','function','return','if','else','for','while','do','switch','case','break','continue','new','this','class','extends','import','export','from','default','async','await','try','catch','finally','throw','typeof','instanceof','in','of','yield','delete','void','null','undefined','true','false','super','static','get','set'],
            ['console','window','document','Math','JSON','Promise','Array','Object','String','Number','Boolean','Map','Set','Date','RegExp','Error','Symbol','parseInt','parseFloat','setTimeout','setInterval','fetch','require','module','exports','process']),
          mkLang('python', ['py'],
            ['def','class','if','elif','else','for','while','return','import','from','as','try','except','finally','raise','with','yield','lambda','pass','break','continue','and','or','not','is','in','True','False','None','global','nonlocal','assert','del','print'],
            ['range','len','int','str','float','list','dict','tuple','set','bool','type','input','open','print','enumerate','zip','map','filter','sorted','reversed','abs','max','min','sum','any','all','isinstance','hasattr','getattr','setattr']),
          mkLang('bash', ['sh', 'shell', 'zsh'],
            ['if','then','else','elif','fi','for','while','do','done','case','esac','function','return','in','select','until','local','export','source','alias','unalias','readonly','shift','exit','exec','eval','set','unset','trap','wait']),
          mkLang('html', ['xml'],
            ['html','head','body','div','span','p','a','img','ul','ol','li','table','tr','td','th','form','input','button','select','option','script','style','link','meta','title','h1','h2','h3','h4','h5','h6','br','hr']),
          mkLang('css', ['scss', 'less'],
            ['color','background','margin','padding','border','font','display','position','width','height','top','left','right','bottom','flex','grid','transition','animation','transform','opacity','z-index','overflow','cursor']),
          mkLang('json', [],
            []),
          mkLang('sql', [],
            ['SELECT','FROM','WHERE','INSERT','INTO','VALUES','UPDATE','SET','DELETE','CREATE','TABLE','ALTER','DROP','INDEX','JOIN','LEFT','RIGHT','INNER','OUTER','ON','AND','OR','NOT','IN','BETWEEN','LIKE','ORDER','BY','GROUP','HAVING','LIMIT','OFFSET','UNION','AS','DISTINCT','NULL','IS','TRUE','FALSE','COUNT','SUM','AVG','MIN','MAX']),
          mkLang('markdown', ['md'],
            []),
        ];

        ctx.set(codeBlockConfig.key, {
          extensions: [syntaxHighlighting(codeHighlight)],
          languages: langs,
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
