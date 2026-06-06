package com.airbridge.files

import org.junit.Assert.assertEquals
import org.junit.Test

class FileDedupTest {
    @Test fun noCollisionReturnsOriginal() {
        assertEquals("foto.jpg", dedupedName("foto.jpg") { false })
    }

    @Test fun oneCollisionAppendsOne() {
        val taken = setOf("foto.jpg")
        assertEquals("foto (1).jpg", dedupedName("foto.jpg") { it in taken })
    }

    @Test fun chainOfCollisions() {
        val taken = setOf("foto.jpg", "foto (1).jpg")
        assertEquals("foto (2).jpg", dedupedName("foto.jpg") { it in taken })
    }

    @Test fun noExtension() {
        val taken = setOf("nazwa")
        assertEquals("nazwa (1)", dedupedName("nazwa") { it in taken })
    }

    @Test fun multipleDotsNumberBeforeLastExtension() {
        val taken = setOf("a.tar.gz")
        assertEquals("a.tar (1).gz", dedupedName("a.tar.gz") { it in taken })
    }
}
