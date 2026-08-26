package com.mdeditor.app.render

/** Maps a DOM text-node path and local offset to a document-wide UTF-16 offset. */
object CursorOffsetMapper {
    fun absoluteOffset(textNodeLengths: List<Int>, nodeIndex: Int, localOffset: Int): Int {
        if (textNodeLengths.isEmpty()) return 0
        val index = nodeIndex.coerceIn(0, textNodeLengths.lastIndex)
        val prefix = textNodeLengths.take(index).sum()
        return prefix + localOffset.coerceIn(0, textNodeLengths[index])
    }
}
