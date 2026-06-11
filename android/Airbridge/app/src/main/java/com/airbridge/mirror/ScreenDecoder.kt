package com.airbridge.mirror

import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Build
import android.util.Log
import android.view.Surface
import java.nio.ByteBuffer

/**
 * Reverse mirror (Mac -> phone): decodes the H.264 stream the Mac sends and
 * renders it straight to a [Surface]. Mirror of [ScreenEncoder]. Configured
 * once from VideoConfig (SPS/PPS), then fed Annex-B access units.
 *
 * MediaCodec runs in async mode; input buffers and pending frames are matched
 * under [lock] since the callbacks arrive on a codec thread.
 */
class ScreenDecoder(
    private val surface: Surface,
    private val onVideoSize: (width: Int, height: Int) -> Unit = { _, _ -> }
) {

    @Volatile private var codec: MediaCodec? = null
    private var configured = false
    /**
     * Set (under [lock]) before the codec is torn down. Callbacks arrive on a
     * codec thread and [onFrame] on the network thread, so without this guard
     * they could touch an already-released codec (IllegalStateException /
     * native crash) or leak a codec created by a late config message.
     */
    @Volatile private var stopped = false

    private val lock = Object()
    private val pendingFrames = ArrayDeque<Pair<ByteArray, Long>>()   // (annexB, ptsUs)
    private val freeInputs = ArrayDeque<Int>()

    /** First config: SPS/PPS (raw, no start codes). Builds + starts the codec. */
    /** H.264 config: SPS/PPS (raw, no start codes). */
    fun onConfig(sps: ByteArray, pps: ByteArray) {
        if (!claimConfigured()) return
        val (w, h) = parseSpsDimensions(sps) ?: (DEFAULT_WIDTH to DEFAULT_HEIGHT)
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, w, h).apply {
            setByteBuffer("csd-0", ByteBuffer.wrap(withStartCode(sps)))
            setByteBuffer("csd-1", ByteBuffer.wrap(withStartCode(pps)))
            lowLatency()
        }
        startCodec(MediaFormat.MIMETYPE_VIDEO_AVC, format)
    }

    /** HEVC config: VPS/SPS/PPS (raw, no start codes). HEVC packs all three into csd-0. */
    fun onConfigHEVC(vps: ByteArray, sps: ByteArray, pps: ByteArray) {
        if (!claimConfigured()) return
        val csd0 = withStartCode(vps) + withStartCode(sps) + withStartCode(pps)
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_HEVC, DEFAULT_WIDTH, DEFAULT_HEIGHT).apply {
            setByteBuffer("csd-0", ByteBuffer.wrap(csd0))
            lowLatency()
        }
        startCodec(MediaFormat.MIMETYPE_VIDEO_HEVC, format)
    }

    private fun claimConfigured(): Boolean = synchronized(lock) {
        if (configured || stopped) return false
        configured = true
        true
    }

    private fun MediaFormat.lowLatency() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) setInteger(MediaFormat.KEY_LOW_LATENCY, 1)
    }

    private fun startCodec(mime: String, format: MediaFormat) {
        val c = MediaCodec.createDecoderByType(mime)
        c.setCallback(object : MediaCodec.Callback() {
            override fun onInputBufferAvailable(codec: MediaCodec, index: Int) {
                if (stopped) return
                val frame = synchronized(lock) {
                    if (stopped) return
                    val f = pendingFrames.removeFirstOrNull()
                    if (f == null) { freeInputs.addLast(index); null } else f
                } ?: return
                feed(codec, index, frame.first, frame.second)
            }
            override fun onOutputBufferAvailable(codec: MediaCodec, index: Int, info: MediaCodec.BufferInfo) {
                if (stopped) return
                // render = true draws the decoded frame onto the Surface.
                runCatching { codec.releaseOutputBuffer(index, info.size > 0) }
            }
            override fun onError(codec: MediaCodec, e: MediaCodec.CodecException) {
                if (stopped) return
                Log.e(TAG, "decoder error", e)
            }
            override fun onOutputFormatChanged(codec: MediaCodec, format: MediaFormat) {
                if (stopped) return
                Log.d(TAG, "output format: $format")
                // Crop-corrected display dimensions for correct aspect ratio.
                val w = if (format.containsKey("crop-right") && format.containsKey("crop-left"))
                    format.getInteger("crop-right") - format.getInteger("crop-left") + 1
                else format.getInteger(MediaFormat.KEY_WIDTH)
                val h = if (format.containsKey("crop-bottom") && format.containsKey("crop-top"))
                    format.getInteger("crop-bottom") - format.getInteger("crop-top") + 1
                else format.getInteger(MediaFormat.KEY_HEIGHT)
                if (w > 0 && h > 0) onVideoSize(w, h)
            }
        })
        c.configure(format, surface, null, 0)
        c.start()
        synchronized(lock) {
            if (stopped) {
                // stop() raced the (network-thread) config — don't leak the codec.
                c.runCatching { stop() }
                c.runCatching { release() }
                return
            }
            codec = c
        }
    }

    /** A decoded Annex-B access unit from the Mac. */
    fun onFrame(annexB: ByteArray, ptsUs: Long) {
        if (stopped) return
        val c = codec ?: return
        val index = synchronized(lock) {
            val i = freeInputs.removeFirstOrNull()
            if (i == null) { pendingFrames.addLast(annexB to ptsUs); null } else i
        } ?: return
        feed(c, index, annexB, ptsUs)
    }

    private fun feed(codec: MediaCodec, index: Int, data: ByteArray, ptsUs: Long) {
        val buf = runCatching { codec.getInputBuffer(index) }.getOrNull() ?: return
        buf.clear()
        buf.put(data)
        runCatching { codec.queueInputBuffer(index, 0, data.size, ptsUs, 0) }
    }

    fun stop() {
        // Claim the codec under the lock so callbacks see `stopped` before the
        // codec is touched; release it outside the lock (stop() can block on
        // the codec thread, which may be waiting for [lock]).
        val c = synchronized(lock) {
            stopped = true
            pendingFrames.clear(); freeInputs.clear()
            codec.also { codec = null }
        }
        c?.runCatching { stop() }
        c?.runCatching { release() }
    }

    private fun withStartCode(nalu: ByteArray): ByteArray =
        ByteArray(4 + nalu.size).also {
            it[0] = 0; it[1] = 0; it[2] = 0; it[3] = 1
            System.arraycopy(nalu, 0, it, 4, nalu.size)
        }

    /**
     * Minimal SPS parse for coded width/height. Best-effort: on any parse
     * trouble we fall back to a default and let onOutputFormatChanged correct
     * the real size. Handles frame_cropping; ignores exotic profiles' extra
     * fields (which don't affect the dimension fields we read).
     */
    private fun parseSpsDimensions(sps: ByteArray): Pair<Int, Int>? = runCatching {
        // Skip NAL header byte if present (type 7).
        val start = if (sps.isNotEmpty() && (sps[0].toInt() and 0x1F) == 7) 1 else 0
        val r = RbspReader(sps, start)
        val profileIdc = r.u(8)
        r.u(8)              // constraint flags + reserved
        r.u(8)              // level_idc
        r.ue()              // seq_parameter_set_id
        if (profileIdc in intArrayOf(100, 110, 122, 244, 44, 83, 86, 118, 128, 138, 139, 134, 135)) {
            val chroma = r.ue()
            if (chroma == 3) r.u(1)
            r.ue(); r.ue(); r.u(1)
            if (r.u(1) == 1) { // seq_scaling_matrix_present — skip lists
                val n = if (chroma != 3) 8 else 12
                repeat(n) { if (r.u(1) == 1) skipScalingList(r, if (it < 6) 16 else 64) }
            }
        }
        r.ue()              // log2_max_frame_num
        val pocType = r.ue()
        if (pocType == 0) r.ue()
        else if (pocType == 1) {
            r.u(1); r.se(); r.se()
            val n = r.ue(); repeat(n) { r.se() }
        }
        r.ue()              // max_num_ref_frames
        r.u(1)              // gaps_in_frame_num_value_allowed
        val widthMbs = r.ue() + 1
        val heightMapUnits = r.ue() + 1
        val frameMbsOnly = r.u(1)
        if (frameMbsOnly == 0) r.u(1) // mb_adaptive_frame_field
        r.u(1)              // direct_8x8_inference
        var cropL = 0; var cropR = 0; var cropT = 0; var cropB = 0
        if (r.u(1) == 1) { cropL = r.ue(); cropR = r.ue(); cropT = r.ue(); cropB = r.ue() }
        val width = widthMbs * 16 - (cropL + cropR) * 2
        val height = (2 - frameMbsOnly) * heightMapUnits * 16 - (cropT + cropB) * 2
        if (width in 2..8192 && height in 2..8192) width to height else null
    }.getOrNull()

    private fun skipScalingList(r: RbspReader, size: Int) {
        var lastScale = 8; var nextScale = 8
        for (j in 0 until size) {
            if (nextScale != 0) { val delta = r.se(); nextScale = (lastScale + delta + 256) % 256 }
            lastScale = if (nextScale == 0) lastScale else nextScale
        }
    }

    companion object {
        private const val TAG = "ScreenDecoder"
        private const val DEFAULT_WIDTH = 1280
        private const val DEFAULT_HEIGHT = 720
    }
}

/** Exp-Golomb / bit reader over an SPS RBSP (with emulation-prevention bytes removed). */
private class RbspReader(raw: ByteArray, start: Int) {
    private val bytes: ByteArray
    private var bitPos = 0

    init {
        // Strip emulation_prevention_three_byte (00 00 03 -> 00 00).
        val out = ArrayList<Byte>(raw.size)
        var zeros = 0
        for (i in start until raw.size) {
            val b = raw[i]
            if (zeros >= 2 && b == 3.toByte()) { zeros = 0; continue }
            out.add(b)
            zeros = if (b == 0.toByte()) zeros + 1 else 0
        }
        bytes = out.toByteArray()
    }

    fun u(n: Int): Int {
        var v = 0
        repeat(n) {
            val byte = bytes[bitPos ushr 3].toInt() and 0xFF
            val bit = (byte ushr (7 - (bitPos and 7))) and 1
            v = (v shl 1) or bit
            bitPos++
        }
        return v
    }

    fun ue(): Int {
        var zeros = 0
        while (u(1) == 0) zeros++
        if (zeros == 0) return 0
        return (1 shl zeros) - 1 + u(zeros)
    }

    fun se(): Int {
        val k = ue()
        return if (k % 2 == 0) -(k / 2) else (k + 1) / 2
    }
}
