package com.airbridge.share

/**
 * The web link inside shared text, if there is one. Browsers share a bare URL,
 * but many apps share "Title https://…" or a sentence ending in the link; the
 * first http(s) URL wins. Only http and https qualify: those are the links the
 * Mac opens straight away, anything else stays ordinary clipboard text.
 */
object SharedLink {
    private val url = Regex("""https?://[^\s<>"]+""", RegexOption.IGNORE_CASE)

    fun extract(text: String): String? {
        val match = url.find(text)?.value ?: return null
        // Punctuation that closes the surrounding sentence is not part of the
        // link: "see https://x.pl/a." or "(https://x.pl/a)".
        var link = match.trimEnd('.', ',', ';', ':', '!', '?', '\'')
        if (link.endsWith(')') && link.count { it == '(' } < link.count { it == ')' }) link = link.dropLast(1)
        // A scheme with no host ("https://") is not a link.
        return link.takeIf { it.substringAfter("://").isNotEmpty() }
    }
}
