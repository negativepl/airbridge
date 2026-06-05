package com.airbridge.mirror

import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.projection.MediaProjection
import android.os.Handler
import android.os.Looper
import android.os.Build
import android.util.Log
import java.nio.ByteBuffer

class ScreenEncoder(
    private val mediaProjection: MediaProjection,
    private val width: Int,
    private val height: Int,
    private val fps: Int,
    private val bitrateBps: Int,
    private val keyframeIntervalSeconds: Int,
    private val onMessage: (MirrorMessage) -> Unit
) {
    private var encoder: MediaCodec? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var pendingSps: ByteArray? = null
    private var pendingPps: ByteArray? = null
    private var configEmitted = false
    private val mainHandler = Handler(Looper.getMainLooper())
    private var started = false
    private val projectionCallback = object : MediaProjection.Callback() {
        override fun onStop() {
            stop()
        }
    }

    fun start() {
        if (started) return
        started = true
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, bitrateBps)
            setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            // Actually throttles how many frames the VirtualDisplay surface
            // feeds the encoder. Without it a 120 Hz panel pushes ~120 fps of
            // mostly-duplicate frames regardless of KEY_FRAME_RATE (which is
            // only a rate-control hint).
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                setFloat(MediaFormat.KEY_MAX_FPS_TO_ENCODER, fps.toFloat())
            }
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, keyframeIntervalSeconds)
            setInteger(MediaFormat.KEY_BITRATE_MODE, MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                setInteger(MediaFormat.KEY_LOW_LATENCY, 1)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                setInteger(MediaFormat.KEY_OPERATING_RATE, Short.MAX_VALUE.toInt())
                setInteger(MediaFormat.KEY_PRIORITY, 0)
            }
        }
        val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        val inputSurface = codec.createInputSurface()

        codec.setCallback(object : MediaCodec.Callback() {
            override fun onInputBufferAvailable(c: MediaCodec, idx: Int) { /* Surface input, ignored */ }
            override fun onOutputBufferAvailable(c: MediaCodec, idx: Int, info: MediaCodec.BufferInfo) {
                val buf: ByteBuffer = c.getOutputBuffer(idx) ?: return run { c.releaseOutputBuffer(idx, false) }
                buf.position(info.offset); buf.limit(info.offset + info.size)
                val payload = ByteArray(info.size); buf.get(payload)

                if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
                    extractSpsPps(payload)
                    maybeEmitConfig()
                } else if (info.size > 0) {
                    onMessage(MirrorMessage.VideoFrame(
                        presentationTimestampUs = info.presentationTimeUs.toULong(),
                        naluBytes = payload
                    ))
                }
                c.releaseOutputBuffer(idx, false)
            }
            override fun onError(c: MediaCodec, e: MediaCodec.CodecException) {
                Log.e(TAG, "MediaCodec error", e)
                onMessage(MirrorMessage.Status(MirrorStatusCode.ENCODER_ERROR))
            }
            override fun onOutputFormatChanged(c: MediaCodec, format: MediaFormat) {
                format.getByteBuffer("csd-0")?.let { pendingSps = stripAnnexBStartCode(it.toBytes()) }
                format.getByteBuffer("csd-1")?.let { pendingPps = stripAnnexBStartCode(it.toBytes()) }
                maybeEmitConfig()
            }
        })

        codec.start()
        encoder = codec

        mediaProjection.registerCallback(projectionCallback, mainHandler)

        // MediaProjection.createVirtualDisplay handles scaling internally — pass target encoder dims.
        virtualDisplay = mediaProjection.createVirtualDisplay(
            "AirBridgeMirror", width, height, /*dpi*/ 320,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            inputSurface, null, null
        )
    }

    fun stop() {
        if (!started && encoder == null && virtualDisplay == null) return
        started = false
        virtualDisplay?.release(); virtualDisplay = null
        encoder?.runCatching { stop() }
        encoder?.release(); encoder = null
        runCatching { mediaProjection.unregisterCallback(projectionCallback) }
        configEmitted = false; pendingSps = null; pendingPps = null
    }

    private fun extractSpsPps(annexB: ByteArray) {
        val parts = NALUSplitter.split(annexB)
        for (nalu in parts) {
            when ((nalu[0].toInt() and 0x1F)) {
                7 -> pendingSps = nalu
                8 -> pendingPps = nalu
            }
        }
    }

    private fun maybeEmitConfig() {
        val sps = pendingSps; val pps = pendingPps
        if (!configEmitted && sps != null && pps != null) {
            onMessage(MirrorMessage.VideoConfig(sps, pps))
            configEmitted = true
        }
    }

    private fun stripAnnexBStartCode(annexB: ByteArray): ByteArray {
        return when {
            annexB.size > 4 &&
                annexB[0] == 0.toByte() &&
                annexB[1] == 0.toByte() &&
                annexB[2] == 0.toByte() &&
                annexB[3] == 1.toByte() -> annexB.copyOfRange(4, annexB.size)
            annexB.size > 3 &&
                annexB[0] == 0.toByte() &&
                annexB[1] == 0.toByte() &&
                annexB[2] == 1.toByte() -> annexB.copyOfRange(3, annexB.size)
            else -> annexB
        }
    }

    private fun ByteBuffer.toBytes(): ByteArray = ByteArray(remaining()).also { get(it) }

    companion object { private const val TAG = "ScreenEncoder" }
}

internal object NALUSplitter {
    fun split(stream: ByteArray): List<ByteArray> {
        val out = mutableListOf<ByteArray>()
        var i = 0; var lastStart = -1
        while (i + 2 < stream.size) {
            val isStart4 = i + 3 < stream.size && stream[i] == 0.toByte() && stream[i+1] == 0.toByte() && stream[i+2] == 0.toByte() && stream[i+3] == 1.toByte()
            val isStart3 = stream[i] == 0.toByte() && stream[i+1] == 0.toByte() && stream[i+2] == 1.toByte()
            when {
                isStart4 -> { if (lastStart >= 0) out += stream.copyOfRange(lastStart, i); lastStart = i + 4; i += 4 }
                isStart3 -> { if (lastStart >= 0) out += stream.copyOfRange(lastStart, i); lastStart = i + 3; i += 3 }
                else -> i++
            }
        }
        if (lastStart in 0 until stream.size) out += stream.copyOfRange(lastStart, stream.size)
        return out
    }
}
