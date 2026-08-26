package com.mdeditor.app.render

import org.commonmark.parser.Parser
import org.commonmark.renderer.html.HtmlRenderer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RenderHelpersTest {
    @Test
    fun latexPreprocessorEscapesInlineAndBlockMath() {
        val dollars = "${'$'}${'$'}"
        val output = LatexPreprocessor.process("inline \\(a < b\\)\n\n${dollars}c & d$dollars")

        assertTrue(output.contains("class=\"latex latex-inline\""))
        assertTrue(output.contains("data-latex=\"a &lt; b\""))
        assertTrue(output.contains("class=\"latex latex-block\""))
        assertTrue(output.contains("c &amp; d"))
        assertFalse(output.contains("a < b"))
    }

    @Test
    fun cursorOffsetIsClampedAndUsesUtf16Lengths() {
        assertEquals(7, CursorOffsetMapper.absoluteOffset(listOf(2, 4, 3), 2, 1))
        assertEquals(6, CursorOffsetMapper.absoluteOffset(listOf(2, 4, 3), 1, 99))
        assertEquals(0, CursorOffsetMapper.absoluteOffset(emptyList(), 3, 8))
    }

    @Test
    fun incrementalRendererReparsesOnlyChangedBlock() {
        val renderer = renderer()
        val first = renderer.render("first\n\nsecond\n\nthird")
        val second = renderer.render("first\n\nchanged\n\nthird")

        assertEquals(3, first.parsedBlockCount)
        assertEquals(1, second.parsedBlockCount)
        assertEquals(1, second.patches.single().from)
        assertEquals(1, second.patches.single().deleteCount)
        assertEquals("splice", second.patches.single().type)
        assertEquals("blocks/1", second.patches.single().path)
        assertEquals(1, second.patches.single().html.size)
        assertTrue(second.patches.single().html.single().contains("<p>changed</p>"))
        assertEquals("", second.html)
    }

    @Test
    fun fencedCodeWithBlankLinesRemainsOneIncrementalBlock() {
        val renderer = renderer()
        val markdown = """
            ```mermaid
            graph TD

            A --> B
            ```

            tail
        """.trimIndent()

        assertEquals(2, renderer.render(markdown).parsedBlockCount)
    }

    @Test
    fun mediaPreprocessorClampsWidthAndAddsAlignmentClass() {
        val output = MediaPreprocessor.process(
            "![Preview](https://example.test/a.png){width=140 align=right}",
        )

        assertTrue(output.contains("class=\"native-image align-right\""))
        assertTrue(output.contains("--image-width:100%"))
        assertTrue(output.contains("alt=\"Preview\""))
    }

    private fun renderer(): IncrementalMarkdownRenderer {
        val parser = Parser.builder().build()
        val html = HtmlRenderer.builder().build()
        return IncrementalMarkdownRenderer(parser, html) { it }
    }
}
