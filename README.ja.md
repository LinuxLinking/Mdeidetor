# Mdeditor

Mdeditor は Android 向けの Markdown エディタで、Flutter + WebView + Milkdown で構築されています。`.md` ファイルの直接編集、最近使用したファイルの管理、テーマ切り替え、PDF / DOCX / HTML へのエクスポートに対応しています。

## 主な機能

- Markdown ファイルの開く・編集・保存
- Android SAF 経由でのファイルアクセス（元の `content://` URI を保持）
- 最近使用したファイル一覧とクイックオープン
- テーマ切り替え、エディタテーマ切り替え、フォントスケーリング
- PDF、DOCX、HTML へのエクスポート
- 外部 intent による `.md` ファイルのオープン
- コードブロックのシンタックスハイライト（JS/TS、Python、Bash、HTML、CSS、JSON、SQL、Markdown）
- 括弧の自動補完（`[` -> `[]`、`(` -> `()`、カーソルを間に配置）
- スマートな閉じ文字スキップ（カーソルの直後に同じ `]` がある場合、`]` を入力すると重複をスキップ）

## 環境要件

- Flutter 3.47+
- Android 9+（本プロジェクトは主に Android をターゲット）

* Node.js（`milkdown_src` のフロントエンドアセット更新時のみ必要）

## 実行

```bash
flutter pub get
flutter run
```

## ビルド

```bash
flutter build apk --release
flutter build appbundle --release
```

## フロントエンドアセットのビルド

`milkdown_src/` 配下のフロントエンドコードを変更した後、エディタアセットを再ビルドします：

```bash
cd milkdown_src
npm install
npm run build
```

出力は `assets/web/` に同期され、Flutter の WebView で読み込まれます。

## 補足

- ファイルの読み書きは Android SAF 経由で処理
- DOCX エクスポートは Dart 側の OOXML 生成を使用
- PDF エクスポートはネイティブの印刷機能に依存

## 変更履歴

### 2026-08-26

**新機能**
- コードブロックシンタックスハイライト：`@codemirror/language` の StreamLanguage ベースの軽量シンタックス解析（JS/TS、Python、Bash、HTML、CSS、JSON、SQL、Markdown）。完全な `@codemirror/language-data` をインポートせず、APK サイズを抑制
- 括弧の自動補完：`[` または `(` 入力時にマッチする括弧を自動挿入し、カーソルを間に配置
- スマートな閉じ文字スキップ：`]`、`)`、`` ` ``、`*` などの閉じ文字入力時、カーソル直後に同じ文字がある場合はスキップ

**安定性の修正**
- EditorController：WebView 破棄後の非同期コールバックによるクラッシュを防ぐため、`_disposed` ライフサイクルチェックを全面的に追加
- すべての WebView JS 呼び出しを try-catch で包み、レンダリング/テーマ/シンボル挿入/フォーマットのエラーでアプリがクラッシュしなくなる
- ネイティブレンダリングパイプライン `_drainNativeRender`：try-finally 構造を修正し、エラー後も保留中のレンダリングキューを処理
- `_asciiEscapeJson`：サプレメンタリ平面文字（絵文字など、コードユニット > 0xFFFF）のエスケープ処理を修正
- ホームページ更新時の `_future` 代入順序の問題を修正し、競合状態を回避

**ビルド修正**
- Vite ビルド設定：prosemirror/micromark ランタイムの `process is not defined` エラーを修正するため、`process.env` ポリフィルを追加

**新規モジュール**
- `android/render-core`：ネイティブ Markdown レンダリングモジュール（増分レンダリング、LaTeX/Math 前処理、カーソルオフセットマッピングなど Kotlin 実装）

## ライセンス

本プロジェクトは [GNU General Public License v3.0](LICENSE) でライセンスされています。
