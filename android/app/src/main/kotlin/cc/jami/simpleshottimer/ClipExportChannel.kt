// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

package cc.jami.simpleshottimer

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.OverlaySettings
import androidx.media3.common.util.Size
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.FrameDropEffect
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.Presentation
import androidx.media3.effect.RgbMatrix
import androidx.media3.effect.StaticOverlaySettings
import androidx.media3.effect.TextureOverlay
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import com.google.common.collect.ImmutableList
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.util.concurrent.Executors
import java.util.zip.Inflater
import kotlin.math.abs

/**
 * Exports a range video with the shot timer overlay
 * (lib/services/video/clip_exporter.dart). Media3 Transformer, on the main
 * looper as it requires:
 *
 * - `export` trims the clip to [startMs, endMs), scales it to at most
 *   `shortSide`, drops frames above `maxFps`, tone-maps HDR to SDR and
 *   encodes H.264 with the sound kept. Each overlay is a folder of images
 *   (`i.z`: premultiplied RGBA, zlib) that Dart drew, image `i` showing from
 *   `timesUs[i]` (output time) on, placed with its top left at (`x`, `y`)
 *   in fractions of the frame. Progress (0..1) comes back as `progress`
 *   messages; `cancel` names the job to stop. Fails with `cancelled` or
 *   `export_failed`.
 * - `checkEncoderColors` encodes one green frame and reads its luma back:
 *   some encoders (the Galaxy S21 FE's) convert RGB with the BT.601 matrix
 *   while the file says BT.709, which shifts saturated colours; the answer
 *   ("bt601" or "bt709") tells Dart whether to send `colorFix`.
 */
@OptIn(UnstableApi::class)
class ClipExportChannel(
    private val context: Context,
    private val channel: MethodChannel,
) : MethodChannel.MethodCallHandler {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var job: Job? = null

    /** The colour check's encode, held while it runs. */
    private var checking: Transformer? = null

    private class Job(
        val id: Int,
        val transformer: Transformer,
        val result: MethodChannel.Result,
        val output: File,
        val overlays: List<FrameSequenceOverlay>,
    )

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "export" -> {
                if (job != null) return result.error("busy", null, null)
                try {
                    start(call, result)
                } catch (e: Exception) {
                    result.error("export_failed", e.toString(), null)
                }
            }
            "cancel" -> {
                val running = job
                if (running != null && running.id == call.argument<Int>("jobId")) {
                    running.transformer.cancel()
                    finish(running) { it.error("cancelled", null, null) }
                }
                result.success(null)
            }
            "checkEncoderColors" -> checkEncoderColors(result)
            else -> result.notImplemented()
        }
    }

    fun dispose() {
        job?.let {
            it.transformer.cancel()
            finish(it) { r -> r.error("cancelled", null, null) }
        }
        worker.shutdown()
    }

    private fun start(call: MethodCall, result: MethodChannel.Result) {
        val jobId = call.argument<Int>("jobId") ?: 0
        val input = File(call.argument<String>("input")!!)
        val output = File(call.argument<String>("output")!!)
        val startMs = call.argument<Number>("startMs")!!.toLong()
        val endMs = call.argument<Number>("endMs")!!.toLong()
        val shortSide = call.argument<Int>("shortSide") ?: 0
        val maxFps = call.argument<Double>("maxFps")
        val bitrate = call.argument<Int>("bitrate") ?: 12_000_000
        val colorFix = call.argument<Boolean>("colorFix") == true
        val overlays = (call.argument<List<Map<String, Any?>>>("overlays") ?: emptyList()).map {
            FrameSequenceOverlay(
                dir = File(it["dir"] as String),
                timesUs = (it["timesUs"] as List<*>).map { t -> (t as Number).toLong() }.toLongArray(),
                width = (it["width"] as Number).toInt(),
                height = (it["height"] as Number).toInt(),
                x = (it["x"] as Number).toFloat(),
                y = (it["y"] as Number).toFloat(),
            )
        }

        val effects = buildList<Effect> {
            if (maxFps != null) add(FrameDropEffect.createDefaultFrameDropEffect(maxFps.toFloat()))
            if (shortSide > 0) add(Presentation.createForShortSide(shortSide))
            if (overlays.isNotEmpty()) add(OverlayEffect(ImmutableList.copyOf<TextureOverlay>(overlays)))
            if (colorFix) add(RgbMatrix { _, _ -> BT601_TO_709_FIX })
        }
        val item = MediaItem.Builder()
            .setUri(Uri.fromFile(input))
            .setClippingConfiguration(
                MediaItem.ClippingConfiguration.Builder()
                    .setStartPositionMs(startMs)
                    .setEndPositionMs(endMs)
                    .build(),
            )
            .build()
        val edited = EditedMediaItem.Builder(item).setEffects(Effects(listOf(), effects)).build()
        val composition = Composition.Builder(EditedMediaItemSequence.withAudioAndVideoFrom(listOf(edited)))
            .setHdrMode(Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL)
            .build()
        output.delete()
        val transformer = Transformer.Builder(context)
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .setEncoderFactory(encoders(bitrate))
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    val running = job ?: return
                    finish(running) {
                        it.success(
                            mapOf(
                                "fileSizeBytes" to exportResult.fileSizeBytes,
                                "durationMs" to exportResult.approximateDurationMs,
                                "width" to exportResult.width,
                                "height" to exportResult.height,
                                "firstOverlayUs" to running.overlays.firstOrNull()?.firstUs,
                            ),
                        )
                    }
                }

                override fun onError(
                    composition: Composition,
                    exportResult: ExportResult,
                    exportException: ExportException,
                ) {
                    val running = job ?: return
                    finish(running) {
                        it.error("export_failed", "${exportException.errorCodeName}: ${exportException.message}", null)
                    }
                }
            })
            .build()
        job = Job(jobId, transformer, result, output, overlays)
        transformer.start(composition, output.path)
        main.post(progress)
    }

    private val progress = object : Runnable {
        override fun run() {
            val running = job ?: return
            val holder = ProgressHolder()
            if (running.transformer.getProgress(holder) == Transformer.PROGRESS_STATE_AVAILABLE) {
                channel.invokeMethod("progress", mapOf("jobId" to running.id, "fraction" to holder.progress / 100.0))
            }
            main.postDelayed(this, 250)
        }
    }

    /** Ends [running]: replies through [reply], and leaves no partial file on failure. */
    private fun finish(running: Job, reply: (MethodChannel.Result) -> Unit) {
        if (job !== running) return
        job = null
        main.removeCallbacks(progress)
        try {
            reply(running.result)
        } finally {
            if (!running.output.exists() || running.output.length() == 0L) running.output.delete()
        }
    }

    private fun encoders(bitrate: Int) = DefaultEncoderFactory.Builder(context)
        .setRequestedVideoEncoderSettings(VideoEncoderSettings.Builder().setBitrate(bitrate).build())
        .build()

    private fun checkEncoderColors(result: MethodChannel.Result) {
        val dir = File(context.cacheDir, "encoder_check").apply { mkdirs() }
        val image = File(dir, "green.png")
        val video = File(dir, "green.mp4")
        try {
            val green = Bitmap.createBitmap(64, 64, Bitmap.Config.ARGB_8888)
            green.eraseColor(Color.rgb(0, 255, 0))
            FileOutputStream(image).use { green.compress(Bitmap.CompressFormat.PNG, 100, it) }
            green.recycle()
        } catch (e: Exception) {
            return result.error("check_failed", e.toString(), null)
        }
        val item = MediaItem.Builder().setUri(Uri.fromFile(image)).setImageDurationMs(200).build()
        val edited = EditedMediaItem.Builder(item).setFrameRate(10).build()
        video.delete()
        checking = Transformer.Builder(context)
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .setEncoderFactory(encoders(2_000_000))
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    checking = null
                    val encoder = exportResult.videoEncoderName
                    worker.execute {
                        val luma = try {
                            centreLuma(video)
                        } catch (e: Exception) {
                            null
                        } finally {
                            dir.deleteRecursively()
                        }
                        main.post {
                            if (luma == null) {
                                result.error("check_failed", "no frame", null)
                            } else {
                                result.success(
                                    mapOf(
                                        "matrix" to matrixFor(luma),
                                        "luma" to luma,
                                        "encoder" to encoder,
                                        "build" to Build.FINGERPRINT,
                                    ),
                                )
                            }
                        }
                    }
                }

                override fun onError(
                    composition: Composition,
                    exportResult: ExportResult,
                    exportException: ExportException,
                ) {
                    checking = null
                    dir.deleteRecursively()
                    result.error("check_failed", exportException.toString(), null)
                }
            })
            .build()
            .also { it.start(edited, video.path) }
    }

    /** The luma of the middle pixel of [video]'s first frame, as encoded. */
    private fun centreLuma(video: File): Int {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            extractor.setDataSource(video.path)
            val track = (0 until extractor.trackCount).first {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true
            }
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            val decoder = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
            codec = decoder
            decoder.configure(format, null, null, 0)
            decoder.start()
            val info = MediaCodec.BufferInfo()
            var inputDone = false
            repeat(400) {
                if (!inputDone) {
                    val inIndex = decoder.dequeueInputBuffer(10_000)
                    if (inIndex >= 0) {
                        val buffer: ByteBuffer = decoder.getInputBuffer(inIndex)!!
                        val size = extractor.readSampleData(buffer, 0)
                        if (size < 0) {
                            decoder.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            decoder.queueInputBuffer(inIndex, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val outIndex = decoder.dequeueOutputBuffer(info, 10_000)
                if (outIndex >= 0) {
                    val image = decoder.getOutputImage(outIndex)
                    if (image != null && info.size > 0) {
                        val plane = image.planes[0]
                        val x = image.width / 2
                        val y = image.height / 2
                        val luma = plane.buffer.get(y * plane.rowStride + x * plane.pixelStride).toInt() and 0xFF
                        image.close()
                        decoder.releaseOutputBuffer(outIndex, false)
                        return luma
                    }
                    image?.close()
                    decoder.releaseOutputBuffer(outIndex, false)
                }
            }
            throw IllegalStateException("no decoded frame")
        } finally {
            try {
                codec?.stop()
            } catch (_: Exception) {
            }
            codec?.release()
            extractor.release()
        }
    }

    private companion object {
        /**
         * Pure green's luma, limited range: BT.709 puts it at 173, BT.601 at
         * 145 (and full range at 182 and 150). Only BT.601 limited, the
         * mismatch seen on Samsung, is corrected.
         */
        fun matrixFor(luma: Int): String {
            val candidates = mapOf("bt709" to 173, "bt601" to 145, "bt709full" to 182, "bt601full" to 150)
            return candidates.minByOrNull { abs(it.value - luma) }!!.key
        }

        /**
         * The inverse of the BT.601-for-BT.709 round trip, column-major:
         * #FEE036 comes back as 252,222,51 instead of 255,216,47.
         */
        val BT601_TO_709_FIX = floatArrayOf(
            0.913600f, -0.105040f, 0.009578f, 0f,
            0.078478f, 1.172167f, 0.032222f, 0f,
            0.007922f, -0.067127f, 0.958200f, 0f,
            0f, 0f, 0f, 1f,
        )
    }
}

/**
 * Shows image `i` of [dir] (`i.z`, [width] x [height] premultiplied RGBA,
 * zlib) from [timesUs]`[i]` on, with its top left at ([x], [y]) in fractions
 * of the frame. Two bitmaps alternate, so Media3 sees a new one per change.
 */
@OptIn(UnstableApi::class)
private class FrameSequenceOverlay(
    private val dir: File,
    private val timesUs: LongArray,
    private val width: Int,
    private val height: Int,
    private val x: Float,
    private val y: Float,
) : BitmapOverlay() {
    /** The first frame time asked for, to check which time base Media3 uses. */
    var firstUs: Long? = null
    private var current = -1
    private var shown = 0
    private val bitmaps = arrayOfNulls<Bitmap>(2)
    private val pixels = ByteArray(width * height * 4)
    private var settings: OverlaySettings = StaticOverlaySettings.Builder().build()

    override fun configure(videoSize: Size) {
        super.configure(videoSize)
        settings = StaticOverlaySettings.Builder()
            .setOverlayFrameAnchor(-1f, 1f)
            .setBackgroundFrameAnchor(-1f + 2f * x, 1f - 2f * y)
            .build()
    }

    override fun getOverlaySettings(presentationTimeUs: Long): OverlaySettings = settings

    override fun getBitmap(presentationTimeUs: Long): Bitmap {
        if (firstUs == null) firstUs = presentationTimeUs
        var i = timesUs.binarySearch(presentationTimeUs)
        if (i < 0) i = -i - 2
        i = i.coerceIn(0, timesUs.size - 1)
        if (i != current || bitmaps[shown] == null) {
            val slot = (shown + 1) % 2
            val bitmap = bitmaps[slot] ?: Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val inflater = Inflater()
            try {
                inflater.setInput(File(dir, "$i.z").readBytes())
                var n = 0
                while (n < pixels.size && !inflater.finished()) {
                    val read = inflater.inflate(pixels, n, pixels.size - n)
                    if (read == 0 && inflater.needsInput()) break
                    n += read
                }
            } finally {
                inflater.end()
            }
            bitmap.copyPixelsFromBuffer(ByteBuffer.wrap(pixels))
            bitmaps[slot] = bitmap
            shown = slot
            current = i
        }
        return bitmaps[shown]!!
    }

}
