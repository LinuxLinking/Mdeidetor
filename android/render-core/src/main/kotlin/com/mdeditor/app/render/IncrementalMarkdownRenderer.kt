package com.mdeditor.app.render

import org.commonmark.parser.Parser
import org.commonmark.renderer.html.HtmlRenderer

data class DomPatch(
    /** JSON patch operation. `splice` replaces a contiguous range of block nodes. */
    val type: String,
    val path: String,
    val from: Int,
    val deleteCount: Int,
    val html: List<String>,
) {
    fun toMap(): Map<String, Any> = mapOf(
        "type" to type,
        "path" to path,
        "from" to from,
        "deleteCount" to deleteCount,
        "html" to html,
    )
}

data class IncrementalRenderResult(
    /** Kept for export/API compatibility. Interactive renders never populate this. */
    val html: String,
    val patches: List<DomPatch>,
    val parsedBlockCount: Int,
)

/**
 * Keeps rendered block nodes and reparses only the changed contiguous range.
 * The common prefix/suffix comparison is linear and does not reload WebView.
 */
class IncrementalMarkdownRenderer(
    private val parser: Parser,
    private val renderer: HtmlRenderer,
    private val enhancer: (String) -> String,
) {
    private data class Block(val markdown: String, val html: String)

    private var blocks: List<Block> = emptyList()

    fun render(markdown: String): IncrementalRenderResult {
        val sourceBlocks = splitBlocks(markdown)
        var prefix = 0
        while (
            prefix < blocks.size &&
            prefix < sourceBlocks.size &&
            blocks[prefix].markdown == sourceBlocks[prefix]
        ) prefix++

        var oldEnd = blocks.size
        var newEnd = sourceBlocks.size
        while (
            oldEnd > prefix &&
            newEnd > prefix &&
            blocks[oldEnd - 1].markdown == sourceBlocks[newEnd - 1]
        ) {
            oldEnd--
            newEnd--
        }

        val changed = sourceBlocks.subList(prefix, newEnd).map { source ->
            val prepared = LatexPreprocessor.process(
                RichTextPreprocessor.process(MediaPreprocessor.process(source)),
            )
            Block(source, enhancer(renderer.render(parser.parse(prepared))))
        }
        val next = buildList {
            addAll(blocks.take(prefix))
            addAll(changed)
            addAll(blocks.drop(oldEnd))
        }
        val patch = if (prefix == oldEnd && prefix == newEnd) {
            emptyList()
        } else {
            listOf(
                DomPatch(
                    type = "splice",
                    path = "blocks/$prefix",
                    from = prefix,
                    deleteCount = oldEnd - prefix,
                    html = changed.map { wrapBlock(it.html) },
                ),
            )
        }
        blocks = next
        return IncrementalRenderResult(
            // Do not build/return the complete document. The Flutter/WebView path
            // consumes only `patches`; constructing this string made every keystroke
            // O(document size) and defeated incremental rendering.
            html = "",
            patches = patch,
            parsedBlockCount = changed.size,
        )
    }

    private fun splitBlocks(markdown: String): List<String> {
        if (markdown.isEmpty()) return emptyList()
        val result = mutableListOf<String>()
        val current = mutableListOf<String>()
        var fenceMarker: Char? = null
        var fenceLength = 0

        fun flush() {
            if (current.isNotEmpty()) {
                result += current.joinToString("\n")
                current.clear()
            }
        }

        markdown.split('\n').forEach { line ->
            val trimmed = line.trimStart()
            val marker = trimmed.firstOrNull()
            val markerLength = if (marker == '`' || marker == '~') {
                trimmed.takeWhile { it == marker }.length
            } else {
                0
            }

            if (fenceMarker == null && markerLength >= 3) {
                fenceMarker = marker
                fenceLength = markerLength
            } else if (fenceMarker == marker && markerLength >= fenceLength) {
                fenceMarker = null
                fenceLength = 0
            }

            if (line.isBlank() && fenceMarker == null) {
                flush()
            } else {
                current += line
            }
        }
        flush()
        return result
    }

    private fun wrapBlock(html: String): String =
        "<section class=\"native-render-block\">$html</section>"
}
