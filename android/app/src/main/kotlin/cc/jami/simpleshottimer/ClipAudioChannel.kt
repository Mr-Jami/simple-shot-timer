// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

package cc.jami.simpleshottimer

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.Executors
import kotlin.math.roundToInt

/**
 * Reads a video clip's sound for the offline clip analyzer
 * (lib/services/video/clip_audio_source.dart): `probe` describes the clip,
 * `decode` writes its audio as raw little-endian 16-bit mono PCM (the first
 * channel) to a file the Dart side owns and deletes.
 *
 * Decoding a minute of audio takes a while, so both run on one background
 * thread; the replies go back on the main thread, as MethodChannel requires.
 * Failures carry the codes the Dart side maps: no_audio_track,
 * unsupported_codec, unreadable_file, decode_failed.
 */
class ClipAudioChannel : MethodChannel.MethodCallHandler {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        when (call.method) {
            "probe" -> reply(result) { probe(required(path, "path")) }
            "decode" -> reply(result) {
                decode(required(path, "path"), required(call.argument("outputPath"), "outputPath"))
            }
            else -> result.notImplemented()
        }
    }

    fun dispose() {
        worker.shutdown()
    }

    private fun reply(result: MethodChannel.Result, work: () -> Any?) {
        worker.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: ClipAudioFailure) {
                main.post { result.error(e.code, e.message, null) }
            } catch (e: Exception) {
                main.post { result.error("decode_failed", e.toString(), null) }
            }
        }
    }

    private fun required(value: String?, name: String): String =
        value ?: throw ClipAudioFailure("decode_failed", "missing $name")

    private fun probe(path: String): Map<String, Any?> {
        val extractor = open(path)
        try {
            val audio = audioTrack(extractor)
            var durationUs = 0L
            var videoMime: String? = null
            var frameRate: Double? = null
            var transfer: String? = null
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                if (format.containsKey(MediaFormat.KEY_DURATION)) {
                    durationUs = maxOf(durationUs, format.getLong(MediaFormat.KEY_DURATION))
                }
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (!mime.startsWith("video/") || videoMime != null) continue
                videoMime = mime
                frameRate = number(format, MediaFormat.KEY_FRAME_RATE)
                if (format.containsKey(MediaFormat.KEY_COLOR_TRANSFER)) {
                    transfer = when (format.getInteger(MediaFormat.KEY_COLOR_TRANSFER)) {
                        MediaFormat.COLOR_TRANSFER_ST2084 -> "pq"
                        MediaFormat.COLOR_TRANSFER_HLG -> "hlg"
                        else -> "sdr"
                    }
                }
            }
            val (rotation, created) = metadata(path)
            return mapOf(
                "hasAudio" to (audio >= 0),
                "durationMs" to durationUs / 1000,
                "audioMime" to if (audio >= 0) {
                    extractor.getTrackFormat(audio).getString(MediaFormat.KEY_MIME)
                } else {
                    null
                },
                "videoMime" to videoMime,
                "rotation" to rotation,
                "colorTransfer" to transfer,
                "frameRate" to frameRate,
                "creationTimeMs" to created,
            )
        } finally {
            extractor.release()
        }
    }

    private fun decode(path: String, outputPath: String): Map<String, Any?> {
        val extractor = open(path)
        val out = File(outputPath)
        var codec: MediaCodec? = null
        var finished = false
        try {
            val track = audioTrack(extractor)
            if (track < 0) throw ClipAudioFailure("no_audio_track", null)
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
            codec = try {
                MediaCodec.createDecoderByType(mime).also { it.configure(format, null, null, 0) }
            } catch (e: Exception) {
                throw ClipAudioFailure("unsupported_codec", mime)
            }
            codec.start()

            var sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var floatPcm = false
            var written = 0L
            var firstTimeUs: Long? = null
            var inputDone = false
            var idleSinceInputDone = 0
            val info = MediaCodec.BufferInfo()
            BufferedOutputStream(FileOutputStream(out), 1 shl 16).use { stream ->
                while (true) {
                    if (!inputDone) {
                        val inIndex = codec.dequeueInputBuffer(TIMEOUT_US)
                        if (inIndex >= 0) {
                            val buffer = codec.getInputBuffer(inIndex)!!
                            val size = extractor.readSampleData(buffer, 0)
                            if (size < 0) {
                                codec.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                inputDone = true
                            } else {
                                codec.queueInputBuffer(inIndex, 0, size, extractor.sampleTime, 0)
                                extractor.advance()
                            }
                        }
                    }
                    val outIndex = codec.dequeueOutputBuffer(info, TIMEOUT_US)
                    if (outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        val changed = codec.outputFormat
                        sampleRate = changed.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        channels = changed.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        floatPcm = changed.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                            changed.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT
                    } else if (outIndex >= 0) {
                        idleSinceInputDone = 0
                        val buffer = codec.getOutputBuffer(outIndex)!!
                        if (info.size > 0) {
                            if (firstTimeUs == null) firstTimeUs = info.presentationTimeUs
                            written += writeFirstChannel(buffer, info, channels, floatPcm, stream)
                        }
                        codec.releaseOutputBuffer(outIndex, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                    } else if (inputDone && ++idleSinceInputDone > MAX_IDLE_POLLS) {
                        // A decoder that never signals the end; keep what it gave.
                        break
                    }
                }
            }
            finished = true
            return mapOf(
                "sampleRate" to sampleRate,
                "channelCount" to channels,
                "sampleCount" to written,
                "firstSampleTimeUs" to (firstTimeUs ?: 0L),
            )
        } finally {
            try {
                codec?.stop()
            } catch (_: Exception) {
            }
            codec?.release()
            extractor.release()
            if (!finished) out.delete()
        }
    }

    /** Writes the first channel of one decoded buffer as 16-bit little-endian. */
    private fun writeFirstChannel(
        buffer: ByteBuffer,
        info: MediaCodec.BufferInfo,
        channels: Int,
        floatPcm: Boolean,
        stream: BufferedOutputStream,
    ): Long {
        buffer.position(info.offset)
        buffer.limit(info.offset + info.size)
        val pcm = buffer.slice().order(ByteOrder.nativeOrder())
        val bytesPerSample = if (floatPcm) 4 else 2
        val frames = info.size / (bytesPerSample * channels)
        val bytes = ByteArray(frames * 2)
        for (i in 0 until frames) {
            val sample = if (floatPcm) {
                (pcm.getFloat(i * channels * 4) * 32767f).roundToInt().coerceIn(-32768, 32767)
            } else {
                pcm.getShort(i * channels * 2).toInt()
            }
            bytes[2 * i] = (sample and 0xFF).toByte()
            bytes[2 * i + 1] = ((sample shr 8) and 0xFF).toByte()
        }
        stream.write(bytes)
        return frames.toLong()
    }

    private fun open(path: String): MediaExtractor {
        if (!File(path).canRead()) throw ClipAudioFailure("unreadable_file", path)
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(path)
        } catch (e: Exception) {
            extractor.release()
            throw ClipAudioFailure("unreadable_file", e.message)
        }
        return extractor
    }

    /**
     * The audio track to analyse: stereo or mono AAC when there is one (iPhone
     * spatial-audio clips add a 4-channel APAC track next to it), else the
     * first audio track. -1 when there is none.
     */
    private fun audioTrack(extractor: MediaExtractor): Int {
        var first = -1
        for (i in 0 until extractor.trackCount) {
            val format = extractor.getTrackFormat(i)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
            if (!mime.startsWith("audio/")) continue
            if (first < 0) first = i
            val channels = if (format.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            } else {
                0
            }
            if (mime == MediaFormat.MIMETYPE_AUDIO_AAC && channels <= 2) return i
        }
        return first
    }

    /** Rotation in degrees and recording time (ms since epoch, UTC), if known. */
    private fun metadata(path: String): Pair<Int, Long?> {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            val rotation = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull() ?: 0
            val date = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DATE)
            Pair(rotation, date?.let(::parseDate))
        } catch (_: Exception) {
            Pair(0, null)
        } finally {
            retriever.release()
        }
    }

    /** MP4 dates come back like 20260921T123456.000Z. */
    private fun parseDate(value: String): Long? {
        for (pattern in listOf("yyyyMMdd'T'HHmmss.SSS'Z'", "yyyyMMdd'T'HHmmss")) {
            try {
                val format = SimpleDateFormat(pattern, Locale.US)
                format.timeZone = TimeZone.getTimeZone("UTC")
                val time = format.parse(value)?.time ?: continue
                // Files without a date carry 1904-01-01 (the MP4 epoch).
                return if (time > 0) time else null
            } catch (_: Exception) {
            }
        }
        return null
    }

    /** A format number that may be stored as an int or a float. */
    private fun number(format: MediaFormat, key: String): Double? {
        if (!format.containsKey(key)) return null
        return try {
            format.getInteger(key).toDouble()
        } catch (_: ClassCastException) {
            format.getFloat(key).toDouble()
        }
    }

    private class ClipAudioFailure(val code: String, message: String?) : Exception(message)

    private companion object {
        const val TIMEOUT_US = 10_000L
        const val MAX_IDLE_POLLS = 200
    }
}
