package com.mdeditor.app.render

object LatexPreprocessor {
    private val block = Regex("(?s)\\$\\$(.+?)\\$\\$")
    private val inline = Regex("\\\\\\((.+?)\\\\\\)")

    fun process(markdown: String): String = inline.replace(
        block.replace(markdown) { mathHtml(it.groupValues[1], true) },
    ) { mathHtml(it.groupValues[1], false) }

    fun mathHtml(source: String, display: Boolean): String {
        val tag = if (display) "div" else "span"
        val className = if (display) "latex latex-block" else "latex latex-inline"
        return "<$tag class=\"$className\" data-latex=\"${escape(source)}\">${escape(source)}</$tag>"
    }

    private fun escape(value: String): String = value
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("\"", "&quot;")
        .replace("'", "&#39;")
        .replace("\n", "&#10;")
}
