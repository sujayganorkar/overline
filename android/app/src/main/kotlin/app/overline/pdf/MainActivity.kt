package app.overline.pdf

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.print.PrintAttributes
import android.system.Os
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val batchSources by lazy { BatchSources(this) }
    private var pendingPdfMap: Map<String, String>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ocrModels = File(noBackupFilesDir, "ocr-a917b23d-86c145c2")
        Os.setenv("PDFCRAFT_MODELS", ocrModels.absolutePath, true)
        // Clean up stale incoming intent files older than 24 hours
        pruneStaleIncomingCache()

        // Extract incoming PDF from the launch intent if present
        if (pendingPdfMap == null) {
            pendingPdfMap = extractPdfFromIntent(intent)
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getOcrModelDir" -> result.success(ocrModels.absolutePath)
                "getStandardPaperSizes" -> {
                    val type = PrintAttributes.MediaSize::class.java
                    val papers = type.fields.filter { it.type == type }.mapNotNull { field ->
                        val size = field.get(null) as PrintAttributes.MediaSize
                        if (size == PrintAttributes.MediaSize.UNKNOWN_PORTRAIT ||
                            size == PrintAttributes.MediaSize.UNKNOWN_LANDSCAPE) null
                        else mapOf(
                            "name" to size.getLabel(packageManager).toString(),
                            "width_pt" to size.widthMils * 0.072,
                            "height_pt" to size.heightMils * 0.072
                        )
                    }.sortedBy { it["name"].toString() }
                    result.success(papers)
                }
                "pickBatchSources" -> batchSources.pick(call.argument<Boolean>("folder") == true, result)
                "stageBatchSources" -> batchSources.stage(call.argument<List<String>>("tokens").orEmpty(),
                    call.argument<Boolean>("recursive") == true, result)
                "cancelBatchImport" -> { batchSources.cancel(); result.success(null) }
                "forgetBatchSources" -> { batchSources.forget(call.argument<List<String>>("tokens").orEmpty()); result.success(null) }
                "releaseBatchStage" -> { batchSources.release(call.argument<String>("token")); result.success(null) }
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
                "openUrl" -> {
                    val url = call.argument<String>("url")
                    if (url != null) {
                        try {
                            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("LAUNCH_FAILED", e.message, null)
                        }
                    } else {
                        result.error("INVALID_URL", "URL is null", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (!batchSources.receive(requestCode, resultCode, data)) super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        batchSources.close()
        super.onDestroy()
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
