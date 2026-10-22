// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

package cc.jami.simpleshottimer

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.OpenableColumns
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

/**
 * "Or choose from Files" for the video feature: the system document picker
 * for one video, copied straight into the folder Dart names (the clip's work
 * folder), with `copyProgress` (0..1) on [channel] while it copies. The
 * document picker needs no storage permission. Cancelling replies null.
 */
class ClipFilesChannel(
    private val activity: Activity,
    private val channel: MethodChannel,
) : MethodChannel.MethodCallHandler {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pending: Pair<MethodChannel.Result, File>? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "pickVideo") return result.notImplemented()
        val dir = call.argument<String>("targetDir")
            ?: return result.error("copy_failed", "missing targetDir", null)
        if (pending != null) return result.error("busy", null, null)
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType("video/*")
        pending = Pair(result, File(dir))
        try {
            activity.startActivityForResult(intent, REQUEST_CODE)
        } catch (e: ActivityNotFoundException) {
            pending = null
            result.error("no_picker", e.message, null)
        }
    }

    /** Called from MainActivity; true when the result was this picker's. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val (result, dir) = pending ?: return true
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }
        worker.execute {
            try {
                val path = copy(uri, dir)
                main.post { result.success(path) }
            } catch (e: Throwable) {
                main.post { result.error("copy_failed", e.toString(), null) }
            }
        }
        return true
    }

    fun dispose() {
        worker.shutdown()
    }

    private fun copy(uri: Uri, dir: File): String {
        val resolver = activity.contentResolver
        var name = "clip.mp4"
        var size = -1L
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst()) {
                    cursor.getString(0)?.let { name = it.replace(Regex("[^A-Za-z0-9._-]"), "_") }
                    if (!cursor.isNull(1)) size = cursor.getLong(1)
                }
            }
        val target = File(dir, name)
        try {
            val input = resolver.openInputStream(uri) ?: throw IllegalStateException("no stream")
            input.use {
                FileOutputStream(target).use { out ->
                    val buffer = ByteArray(1 shl 16)
                    var copied = 0L
                    var lastReport = 0L
                    while (true) {
                        val n = input.read(buffer)
                        if (n < 0) break
                        out.write(buffer, 0, n)
                        copied += n
                        val now = SystemClock.elapsedRealtime()
                        if (size > 0 && now - lastReport >= 100) {
                            lastReport = now
                            val fraction = (copied.toDouble() / size).coerceIn(0.0, 1.0)
                            main.post { channel.invokeMethod("copyProgress", mapOf("fraction" to fraction)) }
                        }
                    }
                }
            }
        } catch (e: Throwable) {
            target.delete()
            throw e
        }
        return target.path
    }

    companion object {
        private const val REQUEST_CODE = 0x5371
    }
}
