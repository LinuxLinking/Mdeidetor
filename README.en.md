# Mdeditor

Mdeditor is a Markdown editor for Android, built with Flutter + WebView + Milkdown. It supports direct `.md` file editing, recent file management, theme switching, and export to PDF / DOCX / HTML.

## Features

- Open, edit, and save Markdown files
- Access files via Android SAF, preserving original `content://` URI
- Recent files list with quick open
- Theme switching, editor theme switching, font scaling
- Export to PDF, DOCX, HTML
- Open `.md` files via external intent
- Code block syntax highlighting (JS/TS, Python, Bash, HTML, CSS, JSON, SQL, Markdown)
- Bracket auto-completion (`[` -> `[]`, `(` -> `()`, cursor positioned in the middle)
- Smart closing character skip (typing `]` when `]` already follows the cursor skips instead of duplicating)

## Requirements

- Flutter 3.47+
- Android 9+ (the project primarily targets Android)

* Node.js (only needed when updating `milkdown_src` frontend assets)

## Run

```bash
flutter pub get
flutter run
```

## Build

```bash
flutter build apk --release
flutter build appbundle --release
```

## Frontend Asset Build

After modifying frontend code under `milkdown_src/`, rebuild the editor assets:

```bash
cd milkdown_src
npm install
npm run build
```

The output is synced to `assets/web/` for the Flutter WebView to load.

## Notes

- File read/write is handled via Android SAF
- DOCX export uses Dart-side OOXML generation
- PDF export relies on native print capabilities

## Changelog

### 2026-08-26

**New Features**
- Code block syntax highlighting: StreamLanguage-based lightweight syntax parsing for JS/TS, Python, Bash, HTML, CSS, JSON, SQL, and Markdown, without importing the full `@codemirror/language-data` to keep APK size small
- Bracket auto-completion: auto-insert matching brackets when typing `[` or `(`, with cursor positioned in the middle
- Smart closing skip: when typing `]`, `)`, `` ` ``, `*`, etc., if the same character already follows the cursor, skip instead of duplicating

**Stability Fixes**
- EditorController: comprehensive `_disposed` lifecycle checks to prevent crashes from async callbacks after WebView disposal
- All WebView JS calls wrapped in try-catch; rendering/theme/symbol insert/formatting errors no longer crash the app
- Native render pipeline `_drainNativeRender`: fixed try-finally structure to ensure pending render queue is processed after errors
- `_asciiEscapeJson`: fixed escaping for supplementary plane characters (emoji, etc., code unit > 0xFFFF)
- Fixed homepage refresh `_future` assignment ordering to avoid race conditions

**Build Fixes**
- Vite build config: added `process.env` polyfill to fix prosemirror/micromark runtime `process is not defined` error

**New Modules**
- `android/render-core`: native Markdown rendering module (incremental rendering, LaTeX/Math preprocessing, cursor offset mapping, etc. in Kotlin)

## License

This project is licensed under the [GNU General Public License v3.0](LICENSE).
