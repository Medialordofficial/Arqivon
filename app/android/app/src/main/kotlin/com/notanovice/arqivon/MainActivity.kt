package com.notanovice.arqivon

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.notanovice.arqivon/audio_track"
    private var audioTrack: AudioTrack? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "create" -> {
                        val sampleRate = call.argument<Int>("sampleRate") ?: 24000
                        try {
                            audioTrack?.release()
                            val minBuf = AudioTrack.getMinBufferSize(
                                sampleRate,
                                AudioFormat.CHANNEL_OUT_MONO,
                                AudioFormat.ENCODING_PCM_16BIT
                            )
                            // Use 4x min buffer for smooth streaming
                            val bufSize = minBuf.coerceAtLeast(4096) * 4
                            audioTrack = AudioTrack.Builder()
                                .setAudioAttributes(
                                    AudioAttributes.Builder()
                                        .setUsage(AudioAttributes.USAGE_MEDIA)
                                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                                        .build()
                                )
                                .setAudioFormat(
                                    AudioFormat.Builder()
                                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                                        .setSampleRate(sampleRate)
                                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                                        .build()
                                )
                                .setBufferSizeInBytes(bufSize)
                                .setTransferMode(AudioTrack.MODE_STREAM)
                                .build()
                            audioTrack?.play()
                            result.success(bufSize)
                        } catch (e: Exception) {
                            result.error("CREATE_FAILED", e.message, null)
                        }
                    }
                    "write" -> {
                        val data = call.argument<ByteArray>("data")
                        if (data == null) {
                            result.error("NO_DATA", "Missing data", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val written = audioTrack?.write(data, 0, data.size) ?: -1
                            result.success(written)
                        } catch (e: Exception) {
                            result.error("WRITE_FAILED", e.message, null)
                        }
                    }
                    "stop" -> {
                        try {
                            audioTrack?.pause()
                            audioTrack?.flush()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("STOP_FAILED", e.message, null)
                        }
                    }
                    "release" -> {
                        try {
                            audioTrack?.stop()
                            audioTrack?.release()
                            audioTrack = null
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("RELEASE_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        audioTrack?.release()
        audioTrack = null
        super.onDestroy()
    }
}
