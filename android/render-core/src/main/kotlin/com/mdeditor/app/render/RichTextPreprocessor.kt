package com.mdeditor.app.render

/** Small, explicit syntax additions that become safe raw HTML before CommonMark parsing. */
object RichTextPreprocessor {
    private val underline = Regex("\\+\\+([^\\n+]+)\\+\\+")
    private val highlight = Regex("==([^\\n=]+)==")
    // 注意:Android ICU 正则引擎对花括号要求严格:
    //   - 量词 {3,8} 的闭合 } 必须转义为 \\} (写成 \\{3,8\\})
    //   - 字面量 { 和 } 必须转义为 \\{ 和 \\}
    // JVM 的 java.util.regex 可以容忍未转义花括号,但 Android ICU 会抛
    // PatternSyntaxException → ExceptionInInitializerError → 应用崩溃。
    private val color = Regex("\\{color:(#[0-9a-fA-F]\\{3,8\\})\\}([^\\n]+?)\\{/color\\}")

    fun process(markdown: String): String {
        var result = color.replace(markdown) {
            "<span style=\"color:${it.groupValues[1]}\">${escape(it.groupValues[2])}</span>"
        }
        result = highlight.replace(result) { "<mark>${escape(it.groupValues[1])}</mark>" }
        return underline.replace(result) { "<u>${escape(it.groupValues[1])}</u>" }
    }

    private fun escape(value: String): String = value
        .replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
}
