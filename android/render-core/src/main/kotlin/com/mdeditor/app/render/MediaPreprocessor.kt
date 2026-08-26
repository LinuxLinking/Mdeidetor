package com.mdeditor.app.render

/** Native image layout extension: `![alt](url){width=75 align=center}`. */
object MediaPreprocessor {
    // 末尾的花括号必须转义(\\}),否则 Android ICU 正则引擎会报 PatternSyntaxException。
    private val image = Regex("!\\[([^]\\n]*)]\\(([^)\\s]+)\\)\\{([^}\\n]+)\\}")
    private val width = Regex("(?:^|\\s)width=(\\d{1,3})(%|px)?(?:\\s|$)")
    private val align = Regex("(?:^|\\s)align=(left|center|right)(?:\\s|$)")

    fun process(markdown: String): String = image.replace(markdown) { match ->
        val attributes = match.groupValues[3]
        val widthMatch = width.find(attributes)
        val widthValue = widthMatch?.groupValues?.get(1)?.toIntOrNull()?.coerceIn(10, 100) ?: 100
        val widthUnit = widthMatch?.groupValues?.get(2)?.ifBlank { "%" } ?: "%"
        val alignment = align.find(attributes)?.groupValues?.get(1) ?: "center"
        val source = escape(match.groupValues[2])
        val alt = escape(match.groupValues[1])

        "<figure class=\"native-image align-$alignment\" style=\"--image-width:$widthValue$widthUnit\">" +
            "<img src=\"$source\" alt=\"$alt\"></figure>"
    }

    private fun escape(value: String): String = value
        .replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
        .replace("\"", "&quot;").replace("'", "&#39;")
}
