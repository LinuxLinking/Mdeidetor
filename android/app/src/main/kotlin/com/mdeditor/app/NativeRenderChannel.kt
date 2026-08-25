package com.mdeditor.app

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.print.PageRange
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.print.PrintDocumentInfo
import android.util.LruCache
import android.webkit.JavascriptInterface
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.BinaryMessenger
import org.commonmark.Extension
import org.commonmark.parser.Parser
import org.commonmark.renderer.html.HtmlRenderer
import org.commonmark.ext.autolink.AutolinkExtension
import org.commonmark.ext.gfm.strikethrough.StrikethroughExtension
import org.commonmark.ext.gfm.tables.TablesExtension
import com.mdeditor.app.render.IncrementalMarkdownRenderer
import com.mdeditor.app.render.LatexPreprocessor
import com.mdeditor.app.render.MediaPreprocessor
import com.mdeditor.app.render.RichTextPreprocessor
import com.android.dx.stock.ProxyBuilder
import java.io.File
import java.lang.reflect.InvocationHandler
import java.util.Collections
import java.util.UUID
import java.security.MessageDigest

/**
 * Native rendering boundary. Parsing stays in commonmark-java and the
 * browser runtimes are bundled as app assets, so rendering never needs a
 * network connection. The WebView used for Mermaid/KaTeX is deliberately
 * isolated from the Flutter editing WebView.
 */
class NativeRenderChannel(private val activity: Activity) :
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    companion object {
        const val CHANNEL = "mdeditor/render"
        const val EVENTS = "mdeditor/render/events"
    }

    private val main = Handler(Looper.getMainLooper())
    // SVGs are small compared with the source document; retain enough entries
    // for long documents with dozens of diagrams while still bounding memory.
    private val cache = LruCache<String, String>(128)
    private val interceptors = Collections.synchronizedMap(mutableMapOf<String, Regex>())
    private val extensions: List<Extension> = listOf(
        TablesExtension.create(),
        StrikethroughExtension.create(),
        AutolinkExtension.create(),
    )
    private val parser = Parser.builder().extensions(extensions).build()
    private val renderer = HtmlRenderer.builder().extensions(extensions).build()
    private val incrementalRenderer = IncrementalMarkdownRenderer(parser, renderer, ::enhanceHtml)
    private var sink: EventChannel.EventSink? = null
    private var themeVariables: Map<String, String> = emptyMap()
    private var runtime: RuntimeWebView? = null
    private val pdfJobs = mutableSetOf<PdfExportJob>()

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
        EventChannel(messenger, EVENTS).setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "renderMarkdown" -> {
                val markdown = call.argument<String>("markdown").orEmpty()
                val theme = call.argument<Map<String, Any?>>("theme")
                @Suppress("UNCHECKED_CAST")
                themeVariables = (theme?.get("variables") as? Map<String, String>) ?: themeVariables
                val rendered = renderMarkdown(markdown)
                result.success(rendered)
            }
            "setTheme" -> {
                @Suppress("UNCHECKED_CAST")
                themeVariables = (call.argument<Map<String, Any?>>("variables") as? Map<String, String>)
                    ?: emptyMap()
                result.success(null)
            }
            "renderMermaid" -> {
                val source = call.argument<String>("source").orEmpty()
                runtime().render("mermaid", source, false, result)
            }
            "getCachedMermaid" -> {
                runtime().getCachedMermaid(call.argument<String>("hash").orEmpty(), result)
            }
            "renderLatex" -> {
                val source = call.argument<String>("source").orEmpty()
                runtime().render("latex", source, call.argument<Boolean>("display") == true, result)
            }
            "copyText" -> {
                val text = call.argument<String>("text").orEmpty()
                val clipboard = activity.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                clipboard.setPrimaryClip(ClipData.newPlainText("Markdown code", text))
                result.success(null)
            }
            "exportHtml" -> exportHtml(call, result)
            "exportPdf" -> exportPdf(call, result)
            "registerInterceptor" -> {
                val name = call.argument<String>("name")
                val pattern = call.argument<String>("pattern")
                if (name.isNullOrBlank() || pattern.isNullOrBlank()) {
                    result.error("INVALID_INTERCEPTOR", "name and pattern are required", null)
                } else {
                    interceptors[name] = Regex(pattern)
                    result.success(null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun renderMarkdown(markdown: String): Map<String, Any> {
        val incremental = incrementalRenderer.render(markdown)
        val changed = incremental.patches.isNotEmpty()
        return mapOf(
            // Interactive rendering is patch-only. `html` is intentionally empty;
            // full HTML remains available exclusively to exportHtml/exportPdf.
            "html" to "",
            "changed" to changed,
            "changedStart" to 0,
            "changedEnd" to if (changed) markdown.length else 0,
            "mermaidCacheHits" to countCachedMermaid(markdown),
            "patches" to incremental.patches.map { it.toMap() },
            "parsedBlockCount" to incremental.parsedBlockCount,
            "protocol" to "native-dom-patch-v1",
        )
    }

    private fun enhanceHtml(html: String): String {
        var result = html
        result = result.replace(Regex("<pre><code class=\"language-([^\"]+)\">")) {
            "<pre class=\"native-code-block\"><div class=\"native-code-toolbar\"><span>${escapeHtml(it.groupValues[1])}</span><button type=\"button\">Copy</button></div><code class=\"language-${escapeHtml(it.groupValues[1])}\">"
        }
        result = result.replace(Regex("(?s)\\$\\$(.+?)\\$\\$")) {
            latexHtml(it.groupValues[1], true)
        }
        result = result.replace(Regex("\\\\\\((.+?)\\\\\\)")) {
            latexHtml(it.groupValues[1], false)
        }
        result = result.replace(Regex("(?s)<pre class=\"native-code-block\"><div class=\"native-code-toolbar\"><span>mermaid</span><button type=\"button\">Copy</button></div><code class=\"language-mermaid\">(.+?)</code></pre>")) {
            "<div class=\"native-mermaid\" data-mermaid=\"${escapeAttribute(it.groupValues[1])}\"></div>"
        }
        result = result.replace(Regex("<p><a href=\"([^\"]+\\.(?:mp4|webm))\">([^<]+)</a></p>", RegexOption.IGNORE_CASE)) {
            "<figure class=\"media-card video-card\"><video controls preload=\"metadata\" src=\"${escapeAttribute(it.groupValues[1])}\"></video><figcaption>${escapeHtml(it.groupValues[2])}</figcaption></figure>"
        }
        result = result.replace(Regex("<p><a href=\"([^\"]+\\.(?:mp3|m4a|ogg|wav))\">([^<]+)</a></p>", RegexOption.IGNORE_CASE)) {
            "<figure class=\"media-card audio-card\"><audio controls preload=\"metadata\" src=\"${escapeAttribute(it.groupValues[1])}\"></audio><figcaption>${escapeHtml(it.groupValues[2])}</figcaption></figure>"
        }
        result = result.replace("<blockquote>", "<blockquote class=\"nested-quote\">")
        result = result.replace("<ul>", "<ul class=\"native-list native-list-unordered\">")
        result = result.replace("<ol>", "<ol class=\"native-list native-list-ordered\">")
        return result
    }

    private fun latexHtml(source: String, display: Boolean): String {
        val tag = if (display) "div" else "span"
        val className = if (display) "latex latex-block" else "latex latex-inline"
        return "<$tag class=\"$className\" data-latex=\"${escapeAttribute(source)}\">${escapeHtml(source)}</$tag>"
    }

    private fun exportHtml(call: MethodCall, result: MethodChannel.Result) {
        applyExportTheme(call)
        val markdown = call.argument<String>("markdown").orEmpty()
        val fileName = call.argument<String>("fileName").orEmpty().ifBlank { "document.html" }
        try {
            val file = exportFile(fileName)
            file.writeText(htmlDocument(markdown), Charsets.UTF_8)
            result.success(file.absolutePath)
        } catch (error: Exception) {
            result.error("HTML_EXPORT_FAILED", error.message, null)
        }
    }

    private fun exportPdf(call: MethodCall, result: MethodChannel.Result) {
        applyExportTheme(call)
        val markdown = call.argument<String>("markdown").orEmpty()
        val fileName = call.argument<String>("fileName").orEmpty().ifBlank { "document.pdf" }
        val job = PdfExportJob(
            file = exportFile(fileName),
            html = htmlDocument(markdown),
            jobName = fileName,
            result = result,
        ) { finished -> pdfJobs.remove(finished) }
        pdfJobs += job
        job.start()
    }

    private fun applyExportTheme(call: MethodCall) {
        val theme = call.argument<Map<String, Any?>>("theme")
        @Suppress("UNCHECKED_CAST")
        themeVariables = (theme?.get("variables") as? Map<String, String>) ?: themeVariables
    }

    private fun exportFile(fileName: String): File {
        val safeName = fileName.replace(Regex("[^A-Za-z0-9._-]"), "_")
        return File(activity.cacheDir, "exports").apply { mkdirs() }
            .resolve("${System.currentTimeMillis()}-$safeName")
    }

    private fun renderFullMarkdown(markdown: String): String {
        val prepared = LatexPreprocessor.process(
            RichTextPreprocessor.process(MediaPreprocessor.process(markdown)),
        )
        return enhanceHtml(renderer.render(parser.parse(prepared)))
    }

    private fun htmlDocument(markdown: String): String = """
        <!doctype html>
        <html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>${themeCss()}</style></head><body>${renderFullMarkdown(markdown)}</body></html>
    """.trimIndent()

    private fun themeCss(): String {
        val bg = themeVariables["--editor-bg"] ?: "#ffffff"
        val fg = themeVariables["--editor-fg"] ?: "#24292f"
        val code = themeVariables["--editor-code-bg"] ?: "#f6f8fa"
        val headings = (1..6).joinToString("") { level ->
            val size = themeVariables["--h$level-size"] ?: "${2.2 - level * 0.22}em"
            val color = themeVariables["--h$level-color"] ?: fg
            val space = themeVariables["--h$level-space"] ?: "16px"
            "h$level{font-size:$size;color:$color;margin-top:$space}"
        }
        return "body{background:$bg;color:$fg;font:16px/1.65 sans-serif;max-width:900px;margin:24px auto;padding:0 20px}" +
            headings +
            "pre{background:$code;padding:16px;overflow:auto}img,svg,video,audio{max-width:100%}" +
            "blockquote{border-left:3px solid #8b949e;padding-left:12px}" +
            "blockquote blockquote,li>ul,li>ol{border-left:1px solid #8b949e;margin-left:4px;padding-left:16px}" +
            ".media-card{border:1px solid #8b949e;border-radius:8px;padding:12px;margin:16px 0}" +
            ".native-image{display:flex;margin:16px 0}.native-image.align-left{justify-content:flex-start}" +
            ".native-image.align-center{justify-content:center}.native-image.align-right{justify-content:flex-end}" +
            ".native-image img{width:min(var(--image-width,100%),100%);height:auto}" +
            "@page{size:A4;margin:18mm}@media print{body{margin:0;max-width:none}pre,table,figure{break-inside:avoid}}"
    }

    private inner class PdfExportJob(
        private val file: File,
        private val html: String,
        private val jobName: String,
        private val result: MethodChannel.Result,
        private val onFinished: (PdfExportJob) -> Unit,
    ) {
        private val webView = WebView(activity)
        private var adapter: PrintDocumentAdapter? = null
        private var pageLoaded = false
        private var completed = false

        fun start() {
            try {
                webView.settings.javaScriptEnabled = false
                // 导出不应在后台访问 Markdown 中的远程图片或媒体地址；
                // 这样 PDF 生成保持离线且不会泄露文档内容或用户 IP。
                webView.settings.blockNetworkLoads = true
                webView.webViewClient = object : WebViewClient() {
                    override fun onPageFinished(view: WebView?, url: String?) {
                        if (pageLoaded || view == null) return
                        pageLoaded = true
                        layout(view.createPrintDocumentAdapter(jobName))
                    }
                }
                webView.loadDataWithBaseURL(null, html, "text/html", "UTF-8", null)
            } catch (error: Exception) {
                fail("Unable to load PDF document", error)
            }
        }

        private fun layout(printAdapter: PrintDocumentAdapter) {
            adapter = printAdapter
            val attributes = PrintAttributes.Builder()
                .setMediaSize(PrintAttributes.MediaSize.ISO_A4)
                .setResolution(PrintAttributes.Resolution("pdf", "PDF", 300, 300))
                .setMinMargins(PrintAttributes.Margins.NO_MARGINS)
                .setColorMode(PrintAttributes.COLOR_MODE_COLOR)
                .build()
            // LayoutResultCallback/WriteResultCallback 的构造器是包私有的（API 19 起一直如此），
            // 无法直接匿名子类化，用 dexmaker 在运行时生成代理子类。
            val layoutCallback = ProxyBuilder
                .forClass(PrintDocumentAdapter.LayoutResultCallback::class.java)
                .dexCache(File(activity.cacheDir, "dexmaker").apply { mkdirs() })
                .handler(InvocationHandler { _, method, args ->
                    when (method.name) {
                        "onLayoutFinished" -> {
                            write(printAdapter)
                            null
                        }
                        "onLayoutFailed" -> {
                            fail((args?.getOrNull(0) as? CharSequence)?.toString() ?: "PDF layout failed")
                            null
                        }
                        "onLayoutCancelled" -> {
                            fail("PDF layout cancelled")
                            null
                        }
                        else -> null
                    }
                })
                .build()
            printAdapter.onLayout(
                null,
                attributes,
                CancellationSignal(),
                layoutCallback,
                Bundle(),
            )
        }

        private fun write(printAdapter: PrintDocumentAdapter) {
            val descriptor = try {
                ParcelFileDescriptor.open(
                    file,
                    ParcelFileDescriptor.MODE_CREATE or
                        ParcelFileDescriptor.MODE_TRUNCATE or
                        ParcelFileDescriptor.MODE_READ_WRITE,
                )
            } catch (error: Exception) {
                fail("Unable to create PDF file", error)
                return
            }
            // WriteResultCallback 构造器同样包私有，同上用 dexmaker 代理。
            val writeCallback = ProxyBuilder
                .forClass(PrintDocumentAdapter.WriteResultCallback::class.java)
                .dexCache(File(activity.cacheDir, "dexmaker").apply { mkdirs() })
                .handler(InvocationHandler { _, method, args ->
                    when (method.name) {
                        "onWriteFinished" -> {
                            descriptor.close()
                            succeed()
                            null
                        }
                        "onWriteFailed" -> {
                            descriptor.close()
                            fail((args?.getOrNull(0) as? CharSequence)?.toString() ?: "PDF write failed")
                            null
                        }
                        "onWriteCancelled" -> {
                            descriptor.close()
                            fail("PDF write cancelled")
                            null
                        }
                        else -> null
                    }
                })
                .build()
            printAdapter.onWrite(
                arrayOf(PageRange.ALL_PAGES),
                descriptor,
                CancellationSignal(),
                writeCallback,
            )
        }

        private fun succeed() {
            if (completed) return
            completed = true
            cleanup()
            result.success(file.absolutePath)
        }

        private fun fail(message: String, error: Exception? = null) {
            if (completed) return
            completed = true
            file.delete()
            cleanup()
            result.error("PDF_EXPORT_FAILED", error?.message ?: message, null)
        }

        private fun cleanup() {
            adapter?.onFinish()
            webView.stopLoading()
            webView.destroy()
            onFinished(this)
        }
    }

    private fun runtime(): RuntimeWebView {
        if (runtime == null) runtime = RuntimeWebView(activity, main, cache) { type, payload ->
            sink?.success(mapOf("type" to type, "payload" to payload))
        }
        return runtime!!
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    private fun countCachedMermaid(markdown: String): Int =
        Regex("(?s)```mermaid\\s*\\n(.+?)```").findAll(markdown).count {
            cache.get("mermaid:${md5(it.groupValues[1].trim())}") != null
        }

    private fun md5(value: String): String = MessageDigest.getInstance("MD5")
        .digest(value.toByteArray(Charsets.UTF_8))
        .joinToString("") { "%02x".format(it.toInt() and 0xff) }

    private fun escapeHtml(value: String): String = value
        .replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
        .replace("\"", "&quot;").replace("'", "&#39;")

    private fun escapeAttribute(value: String): String = escapeHtml(value).replace("\n", "&#10;")

    private data class Pending(
        val result: MethodChannel.Result,
        val key: String,
        val type: String,
        val source: String,
        val display: Boolean,
    )

    private inner class RuntimeWebView(
        activity: Activity,
        private val main: Handler,
        private val cache: LruCache<String, String>,
        private val event: (String, Map<String, Any>) -> Unit,
    ) {
        private val pending = mutableMapOf<String, Pending>()
        private val webView = WebView(activity)
        private var ready = false

        init {
            webView.settings.javaScriptEnabled = true
            webView.settings.allowFileAccess = false
            webView.addJavascriptInterface(Bridge(), "NativeRenderBridge")
            webView.webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView?, url: String?) {
                    ready = true
                    pending.keys.toList().forEach(::evaluate)
                }
            }
            val mermaid = readAsset(activity, "flutter_assets/assets/web/vendor/mermaid/mermaid.min.js")
            val katex = readAsset(activity, "flutter_assets/assets/web/vendor/katex/katex.min.js")
            val css = readAsset(activity, "flutter_assets/assets/web/vendor/katex/katex.min.css")
            webView.loadDataWithBaseURL(
                "https://mdeditor.invalid/",
                "<style>$css</style><script>$mermaid</script><script>$katex</script><script>if(window.mermaid)mermaid.initialize({startOnLoad:false,securityLevel:'strict'});</script>",
                "text/html", "UTF-8", null,
            )
        }

        fun render(type: String, source: String, display: Boolean, result: MethodChannel.Result) {
            val key = if (type == "mermaid") "mermaid:${md5(source.trim())}" else "$type:$display:$source"
            cache.get(key)?.let {
                result.success(it)
                event(
                    if (type == "mermaid") "mermaidRendered" else "latexRendered",
                    mapOf("cached" to true),
                )
                return
            }
            val id = UUID.randomUUID().toString()
            pending[id] = Pending(result, key, type, source, display)
            if (ready) evaluate(id)
        }

        fun getCachedMermaid(hash: String, result: MethodChannel.Result) {
            if (hash.isBlank()) { result.success(null); return }
            val key = if (hash.matches(Regex("[0-9a-fA-F]{32}"))) hash.lowercase() else md5(hash.trim())
            cache.get("mermaid:$key")?.let { result.success(it) } ?: result.success(null)
        }

        private fun evaluate(id: String) {
            val request = pending[id] ?: return
            val encoded = org.json.JSONObject.quote(request.source)
            val script = if (request.type == "mermaid") {
                "mermaid.render('$id',$encoded).then(function(r){NativeRenderBridge.onResult('$id',r.svg)}).catch(function(e){NativeRenderBridge.onError('$id',String(e))})"
            } else {
                "Promise.resolve().then(function(){return katex.renderToString($encoded,{displayMode:${request.display}})}).then(function(html){NativeRenderBridge.onResult('$id',html)}).catch(function(e){NativeRenderBridge.onError('$id',String(e))})"
            }
            main.post { webView.evaluateJavascript(script, null) }
        }

        private inner class Bridge {
            @JavascriptInterface
            fun onResult(id: String, value: String) {
                main.post {
                    val request = pending.remove(id) ?: return@post
                    cache.put(request.key, value)
                    request.result.success(value)
                    event(
                        if (request.type == "mermaid") "mermaidRendered" else "latexRendered",
                        mapOf("cached" to false),
                    )
                }
            }

            @JavascriptInterface
            fun onError(id: String, message: String) {
                main.post { pending.remove(id)?.result?.error("RENDER_FAILED", message, null) }
            }
        }

        private fun readAsset(context: Context, path: String): String = try {
            context.assets.open(path).bufferedReader(Charsets.UTF_8).use { it.readText() }
        } catch (_: Exception) {
            ""
        }
    }
}
