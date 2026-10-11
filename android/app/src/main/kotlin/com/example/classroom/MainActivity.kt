package com.example.classroom

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.classroom/video_frames"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "extractFrames") {
                val videoPath = call.argument<String>("videoPath")
                val targetFps = call.argument<Double>("fps") ?: 4.0
                val maxFrames = call.argument<Int>("maxFrames") ?: 40

                if (videoPath == null) {
                    result.error("INVALID_PATH", "Video path is null", null)
                    return@setMethodCallHandler
                }

                Thread {
                    val framePaths = ArrayList<String>()
                    val retriever = MediaMetadataRetriever()
                    try {
                        retriever.setDataSource(videoPath)
                        val durationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                        val durationMs = durationStr?.toLongOrNull() ?: 0L

                        if (durationMs > 0) {
                            val intervalMs = (1000.0 / targetFps).toLong().coerceAtLeast(100L)
                            val cacheDir = File(cacheDir, "sweep_frames")
                            if (!cacheDir.exists()) cacheDir.mkdirs()

                            // Clean old cached frames
                            cacheDir.listFiles()?.forEach { it.delete() }

                            var currentTimeMs = 0L
                            var frameIndex = 0

                            while (currentTimeMs < durationMs && frameIndex < maxFrames) {
                                val timeUs = currentTimeMs * 1000L
                                val bitmap = retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                                if (bitmap != null) {
                                    val outFile = File(cacheDir, "frame_${frameIndex}.jpg")
                                    val fos = FileOutputStream(outFile)
                                    bitmap.compress(Bitmap.CompressFormat.JPEG, 85, fos)
                                    fos.flush()
                                    fos.close()

                                    // Horizon zoom crop (upper 12% to 67% where rear rows 6-12 sit)
                                    val hY = (bitmap.height * 0.12).toInt().coerceAtLeast(0)
                                    val hH = (bitmap.height * 0.55).toInt().coerceAtMost(bitmap.height - hY)
                                    if (hH > 100 && bitmap.width > 100) {
                                        try {
                                            val horizonBitmap = Bitmap.createBitmap(bitmap, 0, hY, bitmap.width, hH)
                                            val horizonFile = File(cacheDir, "frame_${frameIndex}_horizon.jpg")
                                            val hFos = FileOutputStream(horizonFile)
                                            horizonBitmap.compress(Bitmap.CompressFormat.JPEG, 85, hFos)
                                            hFos.flush()
                                            hFos.close()
                                            horizonBitmap.recycle()
                                        } catch (_: Exception) {}
                                    }

                                    bitmap.recycle()
                                    framePaths.add(outFile.absolutePath)
                                    frameIndex++
                                }
                                currentTimeMs += intervalMs
                            }
                        }
                        runOnUiThread {
                            result.success(framePaths)
                        }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("EXTRACTION_ERROR", e.message, null)
                        }
                    } finally {
                        try {
                            retriever.release()
                        } catch (_: Exception) {}
                    }
                }.start()
            } else {
                result.notImplemented()
            }
        }
    }
}
