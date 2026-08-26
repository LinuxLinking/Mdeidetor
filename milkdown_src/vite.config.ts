import { defineConfig } from 'vite';
import path from 'node:path';

// 把 Milkdown 工程打包为单文件 IIFE editor.js,输出到 ../assets/web/
// (Flutter WebView 通过 loadFlutterAsset('assets/web/index.html') 加载)
export default defineConfig({
  define: {
    // 修复 "process is not defined":替换 prosemirror/micromark 中的 Node.js 环境检查
    'process.env.NODE_ENV': JSON.stringify('production'),
    'process.env': JSON.stringify({}),
    'process.platform': JSON.stringify('browser'),
  },
  build: {
    lib: {
      entry: path.resolve(__dirname, 'src/main.ts'),
      name: 'MdeditorEditor',
      formats: ['iife'],
      fileName: () => 'editor.js',
    },
    outDir: path.resolve(__dirname, '../assets/web'),
    emptyOutDir: false, // 不清空 outDir,保留 index.html / editor.css
    rollupOptions: {
      // Milkdown v7 模块较多,强制内联动态导入为单文件
      output: { inlineDynamicImports: true },
    },
    // Android 9 WebView 兼容:target es2017
    target: 'es2017',
    // 单文件打包,inline 所有资源
    assetsInlineLimit: 100000000,
  },
  // ProseMirror / Milkdown 某些内部依赖需保留
  optimizeDeps: {
    include: ['@milkdown/kit', '@milkdown/theme-nord', 'prosemirror-markdown'],
  },
});
