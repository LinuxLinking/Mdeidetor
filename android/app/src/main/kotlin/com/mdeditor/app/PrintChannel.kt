package com.mdeditor.app

import android.app.Activity
import android.content.Context
import android.print.PrintAttributes
import android.print.PrintManager
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * PDF 导出 Platform Channel:把 HTML 发到 Android `PrintManager` 系统打印对话框。
 *
 * 设计参见 dev-doc.md 第 10 节。
 *
 * 流程:
 *   1. Dart 侧 `PdfExporter.printHtml` 把渲染片段包裹为完整 HTML 文档 + 注入打印 CSS
 *   2. 通过 `mdeditor/print` channel 传 [printHtml] 的 `html` + `jobName`
 *   3. 本类创建离线 `WebView`(`blockNetworkLoads=true`),`loadDataWithBaseURL` 加载
 *   4. `onPageFinished` 时调 `createPrintDocumentAdapter(jobName)` 交给 `PrintManager`
 *   5. 用户选"保存为 PDF"或打印机,系统字体(中文零配置)
 */
class PrintChannel(private val activity: Activity) {
    companion object {
        const val CHANNEL = "mdeditor/print"
    }

    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "printHtml" -> {
                        val html = call.argument<String>("html")!!
                        val jobName = call.argument<String>("jobName") ?: "Mdeditor Document"
                        printHtml(html, jobName)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun printHtml(html: String, jobName: String) {
        val webView = WebView(activity).apply {
            settings.javaScriptEnabled = false
            settings.blockNetworkLoads = true   // 离线:防止加载外部资源
            webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView?, url: String?) {
                    val adapter = view!!.createPrintDocumentAdapter(jobName)
                    val printManager =
                        activity.getSystemService(Context.PRINT_SERVICE) as PrintManager
                    val attrs = PrintAttributes.Builder()
                        .setMediaSize(PrintAttributes.MediaSize.ISO_A4)
                        .setResolution(
                            PrintAttributes.Resolution("default", "default", 300, 300)
                        )
                        .setMinMargins(PrintAttributes.Margins.NO_MARGINS)
                        .build()
                    printManager.print(jobName, adapter, attrs)
                }
            }
            loadDataWithBaseURL(null, html, "text/html", "UTF-8", null)
        }
    }
}
