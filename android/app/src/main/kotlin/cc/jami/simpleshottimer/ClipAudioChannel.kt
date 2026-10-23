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
import android.os.SystemClock
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
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import kotlin.math.roundToInt

/**
 * Reads a video clip's sound for the offline clip analyzer
 * (lib/services/video/clip_audio_source.dart): `probe` describes the clip,
 * `decode` writes its audio (or a window of it) as raw little-endian 16-bit
 * mono PCM (the first channel) to a file the Dart side owns and deletes, and
 * for clips too long to analyse whole, `loudness` and `thumbnails` feed the
 * Choose-the-part screen.
 *
 * Decoding takes a while, so decode and loudness share one background
 * thread, and probe and thumbnails run on a second one so they never wait
 * behind them; the replies go back on the main thread, as MethodChannel
 * requires. A job reports progress back on [channel] and stops when cancel
 * names it. Failures carry the codes the Dart side maps:
 * no_audio_track, unsupported_codec, unreadable_file, unsupported_file,
 * no_space, decode_failed, cancelled.
 */
class ClipAudioChannel(private val channel: MethodChannel) : MethodChannel.MethodCallHandler {
    private val worker = Executors.newSingleThreadExecutor()

    /** Probes and thumbnails: quick work that must not wait behind a decode. */
    private val light = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val cancelled = ConcurrentHashMap.newKeySet<Int>()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        when (call.method) {
            "probe" -> reply(result, light) { probe(required(path, "path")) }
            "decode" -> reply(result) {
                decode(
                    required(path, "path"),
                    required(call.argument("outputPath"), "outputPath"),
                    call.argument<Int>("jobId"),
                    (call.argument<Number>("startMs")?.toLong() ?: 0L) * 1000,
                    call.argument<Number>("endMs")?.toLong()?.times(1000),
                )
            }
            "loudness" -> reply(result) {
                loudness(
                    required(path, "path"),
                    call.argument<Int>("jobId") ?: 0,
                    call.argument<Int>("bucketMs") ?: 250,
                )
            }
            "thumbnails" -> reply(result, light) {
                thumbnails(
                    required(path, "path"),
                    call.argument<Int>("jobId") ?: 0,
                    call.argument<List<Number>>("timesMs")?.map { it.toLong() } ?: emptyList(),
                    call.argument<Int>("width") ?: 160,
                )
            }
            // Answered here, not on the worker: it must not wait behind the
            // decode it stops. A job cancelled before it starts never runs.
            "cancel" -> {
                call.argument<Int>("jobId")?.let(cancelled::add)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun dispose() {
        worker.shutdown()
        light.shutdown()
    }

    private fun reply(
        result: MethodChannel.Result,
        executor: java.util.concurrent.Executor = worker,
        work: () -> Any?,
    ) {
        executor.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: ClipAudioFailure) {
                main.post { result.error(e.code, e.message, null) }
            } catch (e: Throwable) {
                // Anything, even running out of memory: Dart waits for a reply.
                val code = if (e.isNoSpace()) "no_space" else "decode_failed"
                main.post { result.error(code, e.toString(), null) }
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
            val meta = metadata(path)
            val (width, height) = videoSize(extractor, meta.rotation)
            return mapOf(
                "hasAudio" to (audio >= 0),
                "durationMs" to durationUs / 1000,
                "audioMime" to if (audio >= 0) {
                    extractor.getTrackFormat(audio).getString(MediaFormat.KEY_MIME)
                } else {
                    null
                },
                "videoMime" to videoMime,
                "rotation" to meta.rotation,
                "width" to width,
                "height" to height,
                "colorTransfer" to transfer,
                "frameRate" to frameRate,
                "captureFrameRate" to meta.captureFrameRate,
                "creationTimeMs" to meta.created,
            )
        } finally {
            extractor.release()
        }
    }

    /**
     * Writes [path]'s sound from [startUs] to [endUs] (null: to the end) as
     * 16-bit little-endian mono PCM. firstSampleTimeUs is the media time of
     * the first sample written, so the window stays in step with the video.
     */
    private fun decode(path: String, outputPath: String, jobId: Int?, startUs: Long, endUs: Long?): Map<String, Any?> {
        val out = File(outputPath)
        var finished = false
        try {
            var firstTimeUs: Long? = null
            var written = 0L
            val bytes = ByteArray(1 shl 14)
            val result = BufferedOutputStream(FileOutputStream(out), 1 shl 16).use { stream ->
                decodeLoop(path, jobId, startUs, endUs, reportProgress = true) { samples, count, timeUs, _ ->
                    if (firstTimeUs == null) firstTimeUs = timeUs
                    var i = 0
                    while (i < count) {
                        val n = minOf(count - i, bytes.size / 2)
                        for (j in 0 until n) {
                            val sample = samples[i + j].toInt()
                            bytes[2 * j] = (sample and 0xFF).toByte()
                            bytes[2 * j + 1] = ((sample shr 8) and 0xFF).toByte()
                        }
                        stream.write(bytes, 0, 2 * n)
                        i += n
                    }
                    written += count
                }
            }
            if (written == 0L) throw ClipAudioFailure("no_audio_track", "the audio track is empty")
            finished = true
            return mapOf(
                "sampleRate" to result.sampleRate,
                "channelCount" to result.channels,
                "sampleCount" to written,
                "firstSampleTimeUs" to (firstTimeUs ?: 0L),
            )
        } finally {
            if (!finished) out.delete()
        }
    }

    /**
     * The whole track's loudness for Choose the part: the RMS of the first
     * channel over every [bucketMs], sent as `loudness` batches
     * ({jobId, from, values}) about every 200 ms while it runs. Returns the
     * bucket count.
     */
    private fun loudness(path: String, jobId: Int, bucketMs: Int): Map<String, Any?> {
        val pending = ArrayList<Double>()
        var sent = 0
        var sum = 0.0
        var inBucket = 0
        var lastSend = SystemClock.elapsedRealtime()
        fun send(force: Boolean) {
            val now = SystemClock.elapsedRealtime()
            if (pending.isEmpty() || (!force && now - lastSend < 200)) return
            lastSend = now
            val batch = pending.toList()
            val from = sent
            sent += batch.size
            pending.clear()
            main.post {
                channel.invokeMethod("loudness", mapOf("jobId" to jobId, "from" to from, "values" to batch))
            }
        }
        val result = decodeLoop(path, jobId, 0L, null, reportProgress = false) { samples, count, _, rate ->
            val bucketSamples = maxOf(1, rate * bucketMs / 1000)
            for (i in 0 until count) {
                val v = samples[i] / 32768.0
                sum += v * v
                if (++inBucket >= bucketSamples) {
                    pending.add(Math.sqrt(sum / inBucket))
                    sum = 0.0
                    inBucket = 0
                }
            }
            send(force = false)
        }
        if (inBucket > 0) pending.add(Math.sqrt(sum / inBucket))
        send(force = true)
        return mapOf("buckets" to sent, "sampleRate" to result.sampleRate)
    }

    private class LoopResult(val sampleRate: Int, val channels: Int)

    /**
     * Decodes the audio track and hands [sink] the first channel as 16-bit
     * samples with the media time of the first one, cut to [startUs]..[endUs]
     * sample-accurately. Stops when [jobId] is cancelled.
     */
    private fun decodeLoop(
        path: String,
        jobId: Int?,
        startUs: Long,
        endUs: Long?,
        reportProgress: Boolean,
        sink: (samples: ShortArray, count: Int, timeUs: Long, sampleRate: Int) -> Unit,
    ): LoopResult {
        if (jobId != null && cancelled.remove(jobId)) throw ClipAudioFailure("cancelled", null)
        val extractor = open(path)
        var codec: MediaCodec? = null
        try {
            val track = audioTrack(extractor)
            if (track < 0) throw ClipAudioFailure("no_audio_track", null)
            extractor.selectTrack(track)
            if (startUs > 0) extractor.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            val format = extractor.getTrackFormat(track)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
            val decoder = try {
                MediaCodec.createDecoderByType(mime)
            } catch (e: Exception) {
                throw ClipAudioFailure("unsupported_codec", mime)
            }
            // Before configure, so finally releases it if configure throws.
            codec = decoder
            try {
                decoder.configure(format, null, null, 0)
            } catch (e: Exception) {
                throw ClipAudioFailure("unsupported_codec", mime)
            }
            decoder.start()

            val durationUs = if (format.containsKey(MediaFormat.KEY_DURATION)) {
                format.getLong(MediaFormat.KEY_DURATION)
            } else {
                0L
            }
            val spanUs = (endUs ?: durationUs) - startUs
            var lastProgressAt = 0L
            var sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var floatPcm = false
            var samples = ShortArray(4096)
            var inputDone = false
            var idleSinceInputDone = 0
            val info = MediaCodec.BufferInfo()
            while (true) {
                if (jobId != null && cancelled.remove(jobId)) throw ClipAudioFailure("cancelled", null)
                if (!inputDone) {
                    val inIndex = decoder.dequeueInputBuffer(TIMEOUT_US)
                    if (inIndex >= 0) {
                        val buffer = decoder.getInputBuffer(inIndex)!!
                        val size = extractor.readSampleData(buffer, 0)
                        val timeUs = extractor.sampleTime
                        if (size < 0 || (endUs != null && timeUs > endUs)) {
                            decoder.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            decoder.queueInputBuffer(inIndex, 0, size, timeUs, 0)
                            extractor.advance()
                            val now = SystemClock.elapsedRealtime()
                            if (reportProgress && jobId != null && spanUs > 0 && now - lastProgressAt >= 100) {
                                lastProgressAt = now
                                val fraction = ((timeUs - startUs).toDouble() / spanUs).coerceIn(0.0, 1.0)
                                main.post {
                                    channel.invokeMethod("progress", mapOf("jobId" to jobId, "fraction" to fraction))
                                }
                            }
                        }
                    }
                }
                val outIndex = decoder.dequeueOutputBuffer(info, TIMEOUT_US)
                if (outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val changed = decoder.outputFormat
                    sampleRate = changed.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    channels = changed.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    floatPcm = changed.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                        changed.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT
                } else if (outIndex >= 0) {
                    idleSinceInputDone = 0
                    val buffer = decoder.getOutputBuffer(outIndex)!!
                    if (info.size > 0) {
                        val frames = info.size / ((if (floatPcm) 4 else 2) * channels)
                        if (samples.size < frames) samples = ShortArray(frames)
                        firstChannel(buffer, info, channels, floatPcm, samples, frames)
                        // Cut to the window, sample-accurately.
                        val t0 = info.presentationTimeUs
                        val skip = if (t0 < startUs) {
                            ((startUs - t0) * sampleRate / 1_000_000L).toInt().coerceIn(0, frames)
                        } else {
                            0
                        }
                        var end = frames
                        if (endUs != null) {
                            val keep = ((endUs - t0) * sampleRate / 1_000_000L).toInt()
                            end = keep.coerceIn(0, frames)
                        }
                        if (end > skip) {
                            val first = if (skip > 0) samples.copyOfRange(skip, end) else samples
                            sink(first, end - skip, t0 + skip * 1_000_000L / sampleRate, sampleRate)
                        }
                    }
                    decoder.releaseOutputBuffer(outIndex, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                } else if (inputDone && ++idleSinceInputDone > MAX_IDLE_POLLS) {
                    // A decoder that never signals the end; keep what it gave.
                    break
                }
            }
            return LoopResult(sampleRate, channels)
        } finally {
            try {
                codec?.stop()
            } catch (_: Exception) {
            }
            codec?.release()
            extractor.release()
        }
    }

    /** The first channel of one decoded buffer, as 16-bit samples. */
    private fun firstChannel(
        buffer: ByteBuffer,
        info: MediaCodec.BufferInfo,
        channels: Int,
        floatPcm: Boolean,
        out: ShortArray,
        frames: Int,
    ) {
        buffer.position(info.offset)
        buffer.limit(info.offset + info.size)
        val pcm = buffer.slice().order(ByteOrder.nativeOrder())
        for (i in 0 until frames) {
            out[i] = if (floatPcm) {
                (pcm.getFloat(i * channels * 4) * 32767f).roundToInt().coerceIn(-32768, 32767).toShort()
            } else {
                pcm.getShort(i * channels * 2)
            }
        }
    }

    /**
     * Preview frames for the Choose-the-part filmstrip, nearest keyframe to
     * each time, sent one by one as `thumbnail` ({jobId, index, bytes}: a
     * JPEG [width] wide) so the strip fills from the left.
     */
    private fun thumbnails(path: String, jobId: Int, timesMs: List<Long>, width: Int): Map<String, Any?> {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            for ((index, ms) in timesMs.withIndex()) {
                if (cancelled.remove(jobId)) throw ClipAudioFailure("cancelled", null)
                val frame = if (android.os.Build.VERSION.SDK_INT >= 27) {
                    retriever.getScaledFrameAtTime(ms * 1000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, width, width * 2)
                } else {
                    retriever.getFrameAtTime(ms * 1000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)?.let {
                        val scaled = android.graphics.Bitmap.createScaledBitmap(it, width, it.height * width / it.width, true)
                        if (scaled !== it) it.recycle()
                        scaled
                    }
                } ?: continue
                val bytes = java.io.ByteArrayOutputStream().use { stream ->
                    frame.compress(android.graphics.Bitmap.CompressFormat.JPEG, 75, stream)
                    stream.toByteArray()
                }
                frame.recycle()
                main.post {
                    channel.invokeMethod("thumbnail", mapOf("jobId" to jobId, "index" to index, "bytes" to bytes))
                }
            }
        } catch (e: ClipAudioFailure) {
            throw e
        } catch (e: Exception) {
            throw ClipAudioFailure("unreadable_file", e.message)
        } finally {
            retriever.release()
        }
        return mapOf("count" to timesMs.size)
    }

    private fun open(path: String): MediaExtractor {
        if (!File(path).canRead()) throw ClipAudioFailure("unreadable_file", path)
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(path)
        } catch (e: Exception) {
            // The file is there: it is cut short (no index) or a container
            // this phone can't open.
            extractor.release()
            throw ClipAudioFailure("unsupported_file", e.message)
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

    /**
     * Rotation in degrees, recording time (ms since epoch, UTC) and the
     * capture frame rate (slow motion, time-lapse), if known.
     */
    private class Metadata(val rotation: Int, val created: Long?, val captureFrameRate: Double?)

    private fun metadata(path: String): Metadata {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            val rotation = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull() ?: 0
            val date = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DATE)
            // Slow-motion and time-lapse clips record at another rate than
            // they play back at.
            val capture = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_CAPTURE_FRAMERATE)
                ?.toDoubleOrNull()
            Metadata(rotation, date?.let(::parseDate), capture)
        } catch (_: Exception) {
            Metadata(0, null, null)
        } finally {
            retriever.release()
        }
    }

    /** The first video track's size as displayed (rotation applied). */
    private fun videoSize(extractor: MediaExtractor, rotation: Int): Pair<Int?, Int?> {
        for (i in 0 until extractor.trackCount) {
            val format = extractor.getTrackFormat(i)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
            if (!mime.startsWith("video/")) continue
            if (!format.containsKey(MediaFormat.KEY_WIDTH) || !format.containsKey(MediaFormat.KEY_HEIGHT)) break
            val w = format.getInteger(MediaFormat.KEY_WIDTH)
            val h = format.getInteger(MediaFormat.KEY_HEIGHT)
            return if (rotation % 180 == 0) Pair(w, h) else Pair(h, w)
        }
        return Pair(null, null)
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
