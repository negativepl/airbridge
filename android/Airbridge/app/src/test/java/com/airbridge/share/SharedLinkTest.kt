package com.airbridge.share

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SharedLinkTest {
    @Test fun bareUrl() = assertEquals("https://example.com/a?b=c", SharedLink.extract("https://example.com/a?b=c"))
    @Test fun titleThenUrl() = assertEquals("https://news.site/x", SharedLink.extract("Some article title\nhttps://news.site/x"))
    @Test fun sentencePunctuation() = assertEquals("https://x.pl/a", SharedLink.extract("Look: https://x.pl/a."))
    @Test fun parenthesised() = assertEquals("https://x.pl/a", SharedLink.extract("(https://x.pl/a)"))
    @Test fun wikipediaParens() = assertEquals("https://en.wikipedia.org/wiki/Foo_(bar)", SharedLink.extract("https://en.wikipedia.org/wiki/Foo_(bar)"))
    @Test fun httpAllowed() = assertEquals("http://local.test", SharedLink.extract("http://local.test"))
    @Test fun upperCaseScheme() = assertEquals("HTTPS://X.PL", SharedLink.extract("HTTPS://X.PL"))
    @Test fun plainText() = assertNull(SharedLink.extract("just some words"))
    @Test fun otherScheme() = assertNull(SharedLink.extract("file:///etc/passwd"))
    @Test fun schemeOnly() = assertNull(SharedLink.extract("https://"))
}
