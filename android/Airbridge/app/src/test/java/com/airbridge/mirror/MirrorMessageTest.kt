package com.airbridge.mirror

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class MirrorMessageTest {

    @Test fun `HELLO round-trip`() {
        val token = ByteArray(16) { 0xAB.toByte() }
        val msg = MirrorMessage.Hello(token = token, screenWidth = 1080u, screenHeight = 2376u, orientation = 0u)
        val bytes = msg.encode()
        assertEquals(26, bytes.size)
        assertEquals(0x01.toByte(), bytes[0])
        assertEquals(msg, MirrorMessage.decode(bytes))
    }

    @Test fun `HELLO_ACK round-trip`() {
        val msg = MirrorMessage.HelloAck(targetBitrateBps = 12_000_000u, fps = 60u, keyframeIntervalSeconds = 2u, targetWidth = 1080u, targetHeight = 1920u, codec = 0u)
        assertEquals(msg, MirrorMessage.decode(msg.encode()))
    }

    @Test fun `VIDEO_CONFIG_HEVC round-trip`() {
        val vps = byteArrayOf(0x40, 0x01, 0x0C, 0x01)
        val sps = byteArrayOf(0x42, 0x01, 0x01, 0x01)
        val pps = byteArrayOf(0x44, 0x01, 0xC0.toByte(), 0xF2.toByte())
        val msg = MirrorMessage.VideoConfigHEVC(vps = vps, sps = sps, pps = pps)
        assertEquals(msg, MirrorMessage.decode(msg.encode()))
    }

    @Test fun `VIDEO_CONFIG round-trip`() {
        val sps = byteArrayOf(0x67, 0x42, 0x00, 0x1F)
        val pps = byteArrayOf(0x68.toByte(), 0xCE.toByte(), 0x3C, 0x80.toByte())
        val msg = MirrorMessage.VideoConfig(sps = sps, pps = pps)
        assertEquals(msg, MirrorMessage.decode(msg.encode()))
    }

    @Test fun `VIDEO_FRAME round-trip`() {
        val nalu = ByteArray(2048) { (it and 0xFF).toByte() }
        val msg = MirrorMessage.VideoFrame(presentationTimestampUs = 1_234_567_890uL, naluBytes = nalu)
        assertEquals(msg, MirrorMessage.decode(msg.encode()))
    }

    @Test fun `STATUS round-trip - all codes`() {
        for (code in MirrorStatusCode.values()) {
            val msg = MirrorMessage.Status(code)
            assertEquals(msg, MirrorMessage.decode(msg.encode()))
        }
    }

    @Test fun `decode rejects empty`() {
        assertThrows(MirrorMessageException::class.java) { MirrorMessage.decode(byteArrayOf()) }
    }

    @Test fun `decode rejects unknown type`() {
        assertThrows(MirrorMessageException::class.java) { MirrorMessage.decode(byteArrayOf(0xFE.toByte(), 0, 0, 0)) }
    }

    @Test fun `cross-platform pinned bytes - HELLO`() {
        val token = ByteArray(16) { 0xAB.toByte() }
        val msg = MirrorMessage.Hello(token, 1080u, 2376u, 0u)
        val expected = byteArrayOf(0x01) + token +
            byteArrayOf(0, 0, 0x04, 0x38) + // 1080
            byteArrayOf(0, 0, 0x09, 0x48) + // 2376
            byteArrayOf(0)
        assertEquals(expected.toList(), msg.encode().toList())
    }
}
