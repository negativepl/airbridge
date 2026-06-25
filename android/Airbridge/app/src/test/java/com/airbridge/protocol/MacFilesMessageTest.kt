package com.airbridge.protocol

import org.junit.Assert.assertEquals
import org.junit.Test

class MacFilesMessageTest {
    @Test fun listRequestRoundTrips() {
        val msg = Message.MacFilesListRequest("Documents", 1, 200, "modified", "desc", true, "report")
        val parsed = Message.fromJson(msg.toJson()) as Message.MacFilesListRequest
        assertEquals("Documents", parsed.path)
        assertEquals("modified", parsed.sortBy)
        assertEquals("report", parsed.query)
    }

    @Test fun listResponseRoundTrips() {
        val e = FileEntry("a.txt", "Documents/a.txt", false, 12L, 99L, "text/plain")
        val msg = Message.MacFilesListResponse("Documents", listOf(e), 1, 0, false)
        val parsed = Message.fromJson(msg.toJson()) as Message.MacFilesListResponse
        assertEquals(1, parsed.entries.size)
        assertEquals("a.txt", parsed.entries[0].name)
        assertEquals(false, parsed.needsPermission)
    }

    @Test fun downloadReadyRoundTrips() {
        val msg = Message.MacFileDownloadReady("T1", "a.txt", "text/plain", 12L)
        val parsed = Message.fromJson(msg.toJson()) as Message.MacFileDownloadReady
        assertEquals("T1", parsed.transferId)
        assertEquals(12L, parsed.fileSize)
    }
}
