package com.kinzo.order_v3_mobile

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.kinzo/storage")
            .setMethodCallHandler { call, result ->
                if (call.method == "saveToDownloads") {
                    val filename = call.argument<String>("filename") ?: "download"
                    val bytes = call.argument<ByteArray>("bytes")
                    val subDir = call.argument<String>("subDir") ?: "KinzoQR"
                    val mimeType = call.argument<String>("mimeType") ?: "image/jpeg"

                    if (bytes == null) {
                        result.error("INVALID_ARGS", "bytes is null", null)
                        return@setMethodCallHandler
                    }

                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            // Android 10+ — dùng MediaStore, không cần permission
                            val values = ContentValues().apply {
                                put(MediaStore.Downloads.DISPLAY_NAME, filename)
                                put(MediaStore.Downloads.MIME_TYPE, mimeType)
                                put(MediaStore.Downloads.RELATIVE_PATH, "Download/$subDir")
                            }
                            val uri = contentResolver.insert(
                                MediaStore.Downloads.EXTERNAL_CONTENT_URI, values
                            )
                            if (uri != null) {
                                contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                                result.success(true)
                            } else {
                                result.error("INSERT_FAILED", "MediaStore insert returned null", null)
                            }
                        } else {
                            // Android 9 trở xuống — ghi file trực tiếp
                            val downloadsDir = Environment.getExternalStoragePublicDirectory(
                                Environment.DIRECTORY_DOWNLOADS
                            )
                            val dir = File(downloadsDir, subDir)
                            dir.mkdirs()
                            FileOutputStream(File(dir, filename)).use { it.write(bytes) }
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.error("SAVE_FAILED", e.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }
}
