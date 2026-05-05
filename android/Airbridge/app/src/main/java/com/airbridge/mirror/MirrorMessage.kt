package com.airbridge.mirror

import java.nio.ByteBuffer
import java.nio.ByteOrder

enum class MirrorStatusCode(val raw: Byte) {
    SCREEN_OFF(1),
    APP_BACKGROUNDED(2),
    ACCESSIBILITY_DISABLED(3),
    ENCODER_ERROR(4),
    ACCESSIBILITY_BLOCKED(5);

    companion object {
        fun fromRaw(raw: Byte): MirrorStatusCode? = values().firstOrNull { it.raw == raw }
    }
}

class MirrorMessageException(message: String) : RuntimeException(message)

@OptIn(ExperimentalUnsignedTypes::class)
sealed class MirrorMessage {
    data class Hello(
        val token: ByteArray,
        val screenWidth: UInt,
        val screenHeight: UInt,
        val orientation: UByte
    ) : MirrorMessage() {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is Hello) return false
            return token.contentEquals(other.token) &&
                screenWidth == other.screenWidth &&
                screenHeight == other.screenHeight &&
                orientation == other.orientation
        }
        override fun hashCode(): Int =
            (((token.contentHashCode() * 31) + screenWidth.hashCode()) * 31 + screenHeight.hashCode()) * 31 + orientation.hashCode()
    }

    data class HelloAck(
        val targetBitrateBps: UInt,
        val fps: UByte,
        val keyframeIntervalSeconds: UByte,
        val targetWidth: UInt,
        val targetHeight: UInt
    ) : MirrorMessage()

    data class VideoConfig(val sps: ByteArray, val pps: ByteArray) : MirrorMessage() {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is VideoConfig) return false
            return sps.contentEquals(other.sps) && pps.contentEquals(other.pps)
        }
        override fun hashCode() = sps.contentHashCode() * 31 + pps.contentHashCode()
    }

    data class VideoFrame(val presentationTimestampUs: ULong, val naluBytes: ByteArray) : MirrorMessage() {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is VideoFrame) return false
            return presentationTimestampUs == other.presentationTimestampUs && naluBytes.contentEquals(other.naluBytes)
        }
        override fun hashCode() = presentationTimestampUs.hashCode() * 31 + naluBytes.contentHashCode()
    }

    data class Status(val code: MirrorStatusCode) : MirrorMessage()

    companion object {
        private const val TYPE_HELLO: Byte = 0x01
        private const val TYPE_HELLO_ACK: Byte = 0x02
        private const val TYPE_VIDEO_CONFIG: Byte = 0x10
        private const val TYPE_VIDEO_FRAME: Byte = 0x11
        private const val TYPE_STATUS: Byte = 0x30

        fun decode(bytes: ByteArray): MirrorMessage {
            if (bytes.isEmpty()) throw MirrorMessageException("empty payload")
            val buf = ByteBuffer.wrap(bytes).order(ByteOrder.BIG_ENDIAN)
            return when (val type = buf.get()) {
                TYPE_HELLO -> {
                    if (bytes.size != 1 + 16 + 4 + 4 + 1) throw MirrorMessageException("HELLO truncated")
                    val token = ByteArray(16); buf.get(token)
                    val w = buf.int.toUInt(); val h = buf.int.toUInt()
                    val orient = buf.get().toUByte()
                    Hello(token, w, h, orient)
                }
                TYPE_HELLO_ACK -> {
                    if (bytes.size != 1 + 4 + 1 + 1 + 4 + 4) throw MirrorMessageException("HELLO_ACK truncated")
                    val bitrate = buf.int.toUInt()
                    val fps = buf.get().toUByte()
                    val kf = buf.get().toUByte()
                    val w = buf.int.toUInt(); val h = buf.int.toUInt()
                    HelloAck(bitrate, fps, kf, w, h)
                }
                TYPE_VIDEO_CONFIG -> {
                    if (buf.remaining() < 4) throw MirrorMessageException("VIDEO_CONFIG short SPS len")
                    val spsLen = buf.int
                    if (buf.remaining() < spsLen + 4) throw MirrorMessageException("VIDEO_CONFIG short SPS")
                    val sps = ByteArray(spsLen); buf.get(sps)
                    val ppsLen = buf.int
                    if (buf.remaining() != ppsLen) throw MirrorMessageException("VIDEO_CONFIG bad PPS")
                    val pps = ByteArray(ppsLen); buf.get(pps)
                    VideoConfig(sps, pps)
                }
                TYPE_VIDEO_FRAME -> {
                    if (buf.remaining() < 8) throw MirrorMessageException("VIDEO_FRAME no PTS")
                    val pts = buf.long.toULong()
                    val nalu = ByteArray(buf.remaining()); buf.get(nalu)
                    VideoFrame(pts, nalu)
                }
                TYPE_STATUS -> {
                    if (buf.remaining() != 1) throw MirrorMessageException("STATUS truncated")
                    val code = MirrorStatusCode.fromRaw(buf.get())
                        ?: throw MirrorMessageException("STATUS unknown code")
                    Status(code)
                }
                else -> throw MirrorMessageException("unknown type 0x${type.toUByte().toString(16)}")
            }
        }
    }

    fun encode(): ByteArray = when (this) {
        is Hello -> ByteBuffer.allocate(1 + 16 + 4 + 4 + 1).order(ByteOrder.BIG_ENDIAN)
            .put(TYPE_HELLO).put(token).putInt(screenWidth.toInt()).putInt(screenHeight.toInt()).put(orientation.toByte()).array()
        is HelloAck -> ByteBuffer.allocate(1 + 4 + 1 + 1 + 4 + 4).order(ByteOrder.BIG_ENDIAN)
            .put(TYPE_HELLO_ACK).putInt(targetBitrateBps.toInt()).put(fps.toByte()).put(keyframeIntervalSeconds.toByte())
            .putInt(targetWidth.toInt()).putInt(targetHeight.toInt()).array()
        is VideoConfig -> ByteBuffer.allocate(1 + 4 + sps.size + 4 + pps.size).order(ByteOrder.BIG_ENDIAN)
            .put(TYPE_VIDEO_CONFIG).putInt(sps.size).put(sps).putInt(pps.size).put(pps).array()
        is VideoFrame -> ByteBuffer.allocate(1 + 8 + naluBytes.size).order(ByteOrder.BIG_ENDIAN)
            .put(TYPE_VIDEO_FRAME).putLong(presentationTimestampUs.toLong()).put(naluBytes).array()
        is Status -> byteArrayOf(TYPE_STATUS, code.raw)
    }
}
