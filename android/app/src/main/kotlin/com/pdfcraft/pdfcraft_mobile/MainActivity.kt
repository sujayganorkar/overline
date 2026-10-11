package com.pdfcraft.pdfcraft_mobile

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // First-party directory lookup, so the app does not need a plugin
        // that ships prebuilt native libraries for ABIs we do not support.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getSupportDir") {
                val dir = File(filesDir, "pdfcraft-workspace")
                if (!dir.exists() && !dir.mkdirs()) {
                    result.error("IO_ERROR", "Could not create ${dir.absolutePath}", null)
                } else {
                    result.success(dir.absolutePath)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    companion object {
        private const val CHANNEL = "com.pdfcraft.pdfcraft_mobile/paths"
    }
}
