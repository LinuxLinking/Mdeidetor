# Mdeditor

Mdeditor 是一个面向 Android 的 Markdown 编辑器，基于 Flutter + WebView + Milkdown 构建。它支持直接编辑 `.md` 文件、最近文件管理、主题切换，以及导出 PDF / DOCX / HTML。

## 主要功能

- 打开、编辑、保存 Markdown 文件
- 通过 Android SAF 访问文件，保留原始 `content://` URI
- 最近文件列表与快速打开
- 主题切换、编辑器主题切换、字体缩放
- 导出为 PDF、DOCX、HTML
- 支持外部 intent 打开 `.md` 文件
- 代码块语法高亮（JS/TS、Python、Bash、HTML、CSS、JSON、SQL、Markdown）
- 编辑器括号自动补全（`[` → `[]`、`(` → `()`，光标定位到中间）
- 智能闭合符号跳过（输入 `]` 时光标后已有 `]` 则跳过而非重复输入）

## 环境要求

- Flutter 3.47+
- Android 9+（当前项目主要面向 Android）

* Node.js（仅在更新 `milkdown_src` 前端资源时需要）

## 运行

```bash
flutter pub get
flutter run
```

## 构建

```bash
flutter build apk --release
flutter build appbundle --release
```

## 前端资源打包

当你修改 `milkdown_src/` 下的前端代码后，重新构建编辑器资源：

```bash
cd milkdown_src
npm install
npm run build
```

生成的产物会同步到 `assets/web/`，供 Flutter 端 WebView 加载。

## 说明

- 文件读写通过 Android SAF 完成
- 导出 DOCX 使用 Dart 端 OOXML 生成
- 导出 PDF 依赖原生打印能力

## 更新日志

### 2026-08-26

**新功能**
- 代码块语法高亮：基于 `@codemirror/language` 的 `StreamLanguage`，内置 JS/TS、Python、Bash、HTML、CSS、JSON、SQL、Markdown 轻量语法解析，无需引入完整 `@codemirror/language-data`，保持 APK 精简
- 括号自动补全：输入 `[` 或 `(` 时自动插入配对括号并定位光标
- 智能闭合跳过：输入 `]`、`)`、`` ` ``、`*` 等闭合字符时，若光标后紧接相同字符则跳过而非重复输入

**稳定性修复**
- EditorController 全面增加 `_disposed` 生命周期检查，防止 WebView 销毁后异步回调导致崩溃
- 所有 WebView JS 调用统一包裹 try-catch，渲染/主题切换/符号插入/格式化操作异常不再导致应用闪退
- 原生渲染管线 `_drainNativeRender` 修正 try-finally 结构，确保错误后仍能处理待渲染队列
- `_asciiEscapeJson` 修复 emoji 等补充平面字符（code unit > 0xFFFF）的转义处理
- 修复首页刷新时 `_future` 赋值顺序问题，避免竞态

**构建修复**
- Vite 构建配置增加 `process.env` polyfill，修复 prosemirror/micromark 运行时 `process is not defined` 错误

**新增模块**
- `android/render-core`：原生 Markdown 渲染模块（增量渲染、LaTeX/Math 预处理、光标偏移映射等 Kotlin 实现）

