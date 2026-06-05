package com.airbridge.files

import org.junit.Assert.assertEquals
import org.junit.Test

class SafTreeStoreTest {
    @Test fun emptyPathHasNoSegments() {
        assertEquals(emptyList<String>(), SafTreeStore.pathSegments(""))
    }

    @Test fun singleSegment() {
        assertEquals(listOf("Download"), SafTreeStore.pathSegments("Download"))
    }

    @Test fun nestedSegmentsTrimSlashes() {
        assertEquals(listOf("Download", "Sub"), SafTreeStore.pathSegments("/Download/Sub/"))
    }

    @Test fun collapsesEmptySegments() {
        assertEquals(listOf("A", "B"), SafTreeStore.pathSegments("A//B"))
    }

    @Test fun childPathJoins() {
        assertEquals("Download/a.pdf", SafTreeStore.childPath("Download", "a.pdf"))
        assertEquals("a.pdf", SafTreeStore.childPath("", "a.pdf"))
    }
}
