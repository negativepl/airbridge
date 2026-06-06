package com.airbridge.protocol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class FilesMessageTest {
    @Test fun filesListRequestRoundTrip() {
        val msg = Message.FilesListRequest(path = "Download", page = 0, pageSize = 200)
        val parsed = Message.fromJson(msg.toJson()) as Message.FilesListRequest
        assertEquals("Download", parsed.path)
        assertEquals(200, parsed.pageSize)
    }

    @Test fun filesListResponseRoundTrip() {
        val entry = FileEntry("a.pdf", "Download/a.pdf", false, 1234, 1_700_000_000_000, "application/pdf")
        val msg = Message.FilesListResponse("Download", listOf(entry), 1, 0, false)
        val parsed = Message.fromJson(msg.toJson()) as Message.FilesListResponse
        assertEquals(1, parsed.entries.size)
        assertEquals("Download/a.pdf", parsed.entries[0].relativePath)
        assertFalse(parsed.needsPermission)
    }

    @Test fun fileDownloadRequestRoundTrip() {
        val msg = Message.FileDownloadRequest("T1", "Download/a.pdf")
        val parsed = Message.fromJson(msg.toJson()) as Message.FileDownloadRequest
        assertEquals("T1", parsed.transferId)
        assertEquals("Download/a.pdf", parsed.path)
    }

    @Test fun fileTransferOfferWithDestination() {
        val msg = Message.FileTransferOffer("T1", "a.pdf", "application/pdf", 10, "Download")
        val parsed = Message.fromJson(msg.toJson()) as Message.FileTransferOffer
        assertEquals("Download", parsed.destinationDir)
    }

    @Test fun filesListRequestSortSearchRoundTrip() {
        val msg = Message.FilesListRequest(
            path = "Download", page = 1, pageSize = 200,
            sortBy = "size", sortDir = "desc", foldersFirst = false, query = "raport"
        )
        val parsed = Message.fromJson(msg.toJson()) as Message.FilesListRequest
        assertEquals("size", parsed.sortBy)
        assertEquals("desc", parsed.sortDir)
        assertFalse(parsed.foldersFirst)
        assertEquals("raport", parsed.query)
    }

    @Test fun filesListRequestDefaultsWhenFieldsMissing() {
        val legacy = """{"type":"files_list_request","path":"","page":0,"page_size":200}"""
        val parsed = Message.fromJson(legacy) as Message.FilesListRequest
        assertEquals("name", parsed.sortBy)
        assertEquals("asc", parsed.sortDir)
        assertEquals(true, parsed.foldersFirst)
        assertEquals("", parsed.query)
    }

    @Test fun fileDeleteRequestRoundTrip() {
        val msg = Message.FileDeleteRequest("DCIM/old.jpg")
        val parsed = Message.fromJson(msg.toJson()) as Message.FileDeleteRequest
        assertEquals("DCIM/old.jpg", parsed.path)
    }

    @Test fun fileDeleteResponseSuccessRoundTrip() {
        val msg = Message.FileDeleteResponse("DCIM/old.jpg", true, null)
        val parsed = Message.fromJson(msg.toJson()) as Message.FileDeleteResponse
        assertEquals("DCIM/old.jpg", parsed.path)
        assertEquals(true, parsed.success)
        assertEquals(null, parsed.error)
    }

    @Test fun fileDeleteResponseErrorRoundTrip() {
        val msg = Message.FileDeleteResponse("DCIM/old.jpg", false, "delete_failed")
        val parsed = Message.fromJson(msg.toJson()) as Message.FileDeleteResponse
        assertEquals(false, parsed.success)
        assertEquals("delete_failed", parsed.error)
    }
}
