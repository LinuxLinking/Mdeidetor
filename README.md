# Mdeditor

Mdeditor 是一个面向 Android 的 Markdown 编辑器，基于 Flutter + WebView + Milkdown 构建。它支持直接编辑 `.md` 文件、最近文件管理、主题切换，以及导出 PDF / DOCX / HTML。

## 主要功能

- 打开、编辑、保存 Markdown 文件
- 通过 Android SAF 访问文件，保留原始 `content://` URI
- 最近文件列表与快速打开
- 主题切换、编辑器主题切换、字体缩放
- 导出为 PDF、DOCX、HTML
- 支持外部 intent 打开 `.md` 文件

## 环境要求

- Flutter 3.47+
- Android 9+（当前项目主要面向 Android）
- Node.js（仅在更新 `milkdown_src` 前端资源时需要）

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
