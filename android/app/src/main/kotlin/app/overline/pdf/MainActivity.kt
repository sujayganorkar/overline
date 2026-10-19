package app.overline.pdf

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
        // Clean up stale incoming intent files older than 24 hours
        pruneStaleIncomingCache()

        // Extract incoming PDF from the launch intent if present
        if (pendingPdfMap == null) {
            pendingPdfMap = extractPdfFromIntent(intent)
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSupportDir" -> {
                    val dir = File(filesDir, "overline-workspace")
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

    private fun pruneStaleIncomingCache() {
        try {
            val maxAgeMs = 24 * 60 * 60 * 1000L // 24 hours
            val now = System.currentTimeMillis()
            val files = cacheDir.listFiles { file -> file.name.startsWith("incoming_") } ?: return
            for (file in files) {
                if (now - file.lastModified() > maxAgeMs) {
                    file.delete()
                }
            }
        } catch (_: Exception) {
            // Best effort cache maintenance
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
            if (uri.scheme == "content") {
                try {
                    val flags = intent.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION
                    if (flags != 0) {
                        contentResolver.takePersistableUriPermission(uri, flags)
                    }
                } catch (_: SecurityException) {
                    // Non-persistable content provider URI
                }
            }
            var rawFileName = "shared_document.pdf"
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameIndex != -1 && cursor.moveToFirst()) {
                    rawFileName = cursor.getString(nameIndex) ?: rawFileName
                }
            }
            // Sanitize file name to prevent path traversal
            val baseName = File(rawFileName).name.replace(Regex("[^a-zA-Z0-9._-]"), "_")
            val safeFileName = if (baseName.isNotEmpty()) baseName else "shared_document.pdf"

            val cacheFile = File(cacheDir, "incoming_${System.currentTimeMillis()}_$safeFileName")
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(cacheFile).use { output ->
                    input.copyTo(output)
                }
            }
            mapOf("name" to rawFileName, "path" to cacheFile.absolutePath)
        } catch (e: Exception) {
            null
        }
    }

    companion object {
        private const val CHANNEL = "app.overline.pdf/paths"
    }
}
