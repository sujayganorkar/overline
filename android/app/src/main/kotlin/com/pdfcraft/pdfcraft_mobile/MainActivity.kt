package com.pdfcraft.pdfcraft_mobile

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private var pendingPdfMap: Map<String, String>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Extract incoming PDF from the launch intent if present
        if (pendingPdfMap == null) {
            pendingPdfMap = extractPdfFromIntent(intent)
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSupportDir" -> {
                    val dir = File(filesDir, "pdfcraft-workspace")
                    if (!dir.exists() && !dir.mkdirs()) {
                        result.error("IO_ERROR", "Could not create ${dir.absolutePath}", null)
                    } else {
                        result.success(dir.absolutePath)
                    }
                }
                "getInitialPdf" -> {
                    val pdf = pendingPdfMap
                    pendingPdfMap = null
                    result.success(pdf)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val pdf = extractPdfFromIntent(intent)
        if (pdf != null) {
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, CHANNEL).invokeMethod("onPdfReceived", pdf)
            } ?: run {
                pendingPdfMap = pdf
            }
        }
    }

    private fun extractPdfFromIntent(intent: Intent?): Map<String, String>? {
        if (intent == null) return null
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
            }
            else -> null
        }
        if (uri == null) return null

        return try {
            var fileName = "shared_document.pdf"
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameIndex != -1 && cursor.moveToFirst()) {
                    fileName = cursor.getString(nameIndex) ?: fileName
                }
            }
            val cacheFile = File(cacheDir, "incoming_${System.currentTimeMillis()}_$fileName")
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(cacheFile).use { output ->
                    input.copyTo(output)
                }
            }
            mapOf("name" to fileName, "path" to cacheFile.absolutePath)
        } catch (e: Exception) {
            null
        }
    }

    companion object {
        private const val CHANNEL = "com.pdfcraft.pdfcraft_mobile/paths"
    }
}
