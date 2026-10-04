// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

package cc.jami.simpleshottimer

import android.content.Context
import android.media.AudioManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The beep plays on the media stream (see AudioService). A muted or
        // zeroed stream means a silent start signal, so the Dart side asks
        // before every string and shows a one-line notice if needed.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cc.jami.simpleshottimer/volume")
            .setMethodCallHandler { call, result ->
                val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                when (call.method) {
                    "isMediaAudible" -> {
                        val muted = audio.isStreamMute(AudioManager.STREAM_MUSIC)
                        val volume = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
                        result.success(!muted && volume > 0)
                    }
                    "showVolumePanel" -> {
                        audio.adjustStreamVolume(
                            AudioManager.STREAM_MUSIC,
                            AudioManager.ADJUST_SAME,
                            AudioManager.FLAG_SHOW_UI
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
