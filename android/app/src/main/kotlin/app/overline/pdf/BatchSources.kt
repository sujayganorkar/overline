package app.overline.pdf

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.CancellationSignal
import android.os.OperationCanceledException
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import io.flutter.plugin.common.MethodChannel
import java.io.Closeable
import java.io.File
import java.io.IOException
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicReference

/** Import only the content URIs granted by Android's document picker. The engine receives
 * private relative paths, and the provider is never asked to create or modify a document. */
internal class BatchSources(private val activity: Activity) {
    data class Source(val uri: Uri, val id: String, val name: String, val folder: Boolean)
    private val selections = mutableMapOf<String, Source>()
    private val stages = mutableMapOf<String, File>()
    private val worker = Executors.newSingleThreadExecutor()
    private var picker: MethodChannel.Result? = null
    private var pickingFolder = false
    private var copying: CancellationSignal? = null
    private val stream = AtomicReference<Closeable?>()
    private var closed = false
    private val imports get() = File(activity.filesDir.canonicalFile, "overline-workspace/imports")

    fun pick(folder: Boolean, result: MethodChannel.Result) {
        if (picker != null) {
            result.error("BUSY", "A document picker is already open.", null)
            return
        }
        val intent = if (folder) Intent(Intent.ACTION_OPEN_DOCUMENT_TREE) else
            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            }
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        pickingFolder = folder
        picker = result
        try {
            activity.startActivityForResult(intent, REQUEST)
        } catch (e: Exception) {
            picker = null
            result.error("PICK_FAILED", e.localizedMessage, null)
        }
    }

    fun receive(request: Int, resultCode: Int, intent: Intent?): Boolean {
        if (request != REQUEST) return false
        val callback = picker ?: return true
        picker = null
        if (resultCode != Activity.RESULT_OK || intent == null) {
            callback.success(emptyList<Any>())
            return true
        }
        val folder = pickingFolder
        val uris = linkedSetOf<Uri>()
        intent.data?.let { uris.add(it) }
        intent.clipData?.let { clip ->
            if (clip.itemCount > 1000) {
                callback.error("TOO_MANY", "Choose up to 1,000 files or folders.", null)
                return true
            }
            for (index in 0 until clip.itemCount) clip.getItemAt(index).uri?.let { uris.add(it) }
        }
        worker.execute {
            try {
                val selected = uris.map { uri ->
                    require(uri.scheme == "content") { "Android did not supply a document URI." }
                    val documentId = if (folder) DocumentsContract.getTreeDocumentId(uri)
                        else DocumentsContract.getDocumentId(uri)
                    val rootUri = if (folder) DocumentsContract.buildDocumentUriUsingTree(uri, documentId) else uri
                    val display = activity.contentResolver.query(rootUri, arrayOf(Document.COLUMN_DISPLAY_NAME),
                        null, null, null)?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
                    Source(uri, documentId, display ?: "Document", folder)
                }
                activity.runOnUiThread {
                    if (!closed) callback.success(selected.map { source ->
                        val token = selections.entries.firstOrNull { it.value == source }?.key
                            ?: UUID.randomUUID().toString()
                        selections[token] = source
                        mapOf("token" to token, "name" to source.name, "folder" to source.folder)
                    })
                }
            } catch (e: Exception) {
                activity.runOnUiThread { if (!closed) callback.error("PICK_FAILED", e.localizedMessage, null) }
            }
        }
        return true
    }

    fun stage(tokens: List<String>, recursive: Boolean, result: MethodChannel.Result) {
        if (copying != null || tokens.isEmpty() || tokens.size > 1000 || !selections.keys.containsAll(tokens)) {
            result.error("INVALID_SELECTION", "Choose the files or folders again.", null)
            return
        }
        val selected = tokens.map { selections.getValue(it) }
        val signal = CancellationSignal()
        copying = signal
        worker.execute {
            val token = UUID.randomUUID().toString()
            val stage = File(imports, "batch-$token")
            try {
                val base = imports
                check(base.canonicalFile == base.absoluteFile) { "Invalid import workspace." }
                check(base.isDirectory || base.mkdirs()) { "Cannot open the import workspace." }
                // A process death may leave an interrupted import. Never delete active/new stages.
                val cutoff = System.currentTimeMillis() - 24 * 60 * 60 * 1000L
                base.listFiles()?.filter { it.name.matches(STAGE_NAME) && it.lastModified() < cutoff }
                    ?.forEach { if (it.canonicalFile == it.absoluteFile) it.deleteRecursively() }
                check(stage.mkdir()) { "Cannot create a private import folder." }
                val copier = Copier(signal, recursive)
                val paths = mutableListOf<String>()
                selected.forEachIndexed { index, source ->
                    signal.throwIfCanceled()
                    val root = File(stage, index.toString())
                    check(root.mkdir()) { "Cannot create an import root." }
                    val target = child(root, source.name)
                    if (copier.copy(source.uri, source.id, source.folder, target, 0, source.folder)) {
                        paths.add("imports/${stage.name}/$index/${target.name}")
                    }
                }
                signal.throwIfCanceled()
                activity.runOnUiThread {
                    if (closed || signal.isCanceled) {
                        Thread { stage.deleteRecursively() }.start()
                        if (!closed) result.error("CANCELLED", "Folder import cancelled.", null)
                    } else {
                        stages[token] = stage
                        result.success(mapOf("token" to token, "paths" to paths))
                    }
                    copying = null
                }
            } catch (e: Exception) {
                stage.deleteRecursively()
                activity.runOnUiThread {
                    copying = null
                    if (!closed) result.error(if (signal.isCanceled || e is OperationCanceledException) "CANCELLED" else "IMPORT_FAILED",
                        if (signal.isCanceled) "Folder import cancelled." else e.localizedMessage, null)
                }
            }
        }
    }

    private inner class Copier(private val cancel: CancellationSignal, private val recursive: Boolean) {
        private val seen = mutableSetOf<Pair<String?, String>>()
        private var visited = 0
        private var totalBytes = 0L

        fun copy(grant: Uri, id: String, directory: Boolean, target: File, depth: Int, isTree: Boolean): Boolean {
            cancel.throwIfCanceled()
            check(++visited <= 10000 && depth <= 64) { "Folder selection exceeds 10,000 entries or 64 levels." }
            if (directory && depth > 0 && !recursive) return false
            if (!seen.add(Pair(grant.authority, id))) return false
            if (directory) {
                check(target.mkdir()) { "Cannot stage a selected folder." }
                val children = DocumentsContract.buildChildDocumentsUriUsingTree(grant, id)
                val columns = arrayOf(Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME, Document.COLUMN_MIME_TYPE)
                val entries = mutableListOf<Triple<String, String, Boolean>>()
                val cursor = activity.contentResolver.query(children, columns, null, null, null, cancel)
                    ?: throw IOException("Cannot list a selected folder.")
                cursor.use { c ->
                    while (c.moveToNext()) {
                        cancel.throwIfCanceled()
                        check(entries.size < 10000 - visited) { "Folder selection exceeds 10,000 entries." }
                        entries.add(Triple(c.getString(0), c.getString(1) ?: "Document", c.getString(2) == Document.MIME_TYPE_DIR))
                    }
                }
                entries.sortedWith(compareBy({ it.second }, { it.first })).forEach { (childId, name, dir) ->
                    copy(grant, childId, dir, child(target, name), depth + 1, true)
                }
            } else {
                val uri = if (isTree) DocumentsContract.buildDocumentUriUsingTree(grant, id) else grant
                val descriptor = activity.contentResolver.openAssetFileDescriptor(uri, "r", cancel)
                    ?: throw IOException("Cannot read ${target.name}.")
                descriptor.use { fd ->
                    check(fd.length < 0 || fd.length <= BYTE_LIMIT - totalBytes) { "Batch input exceeds 512 MiB." }
                    fd.createInputStream().use { input ->
                        stream.set(input)
                        try {
                            target.outputStream().buffered().use { output ->
                                val buffer = ByteArray(64 * 1024)
                                while (true) {
                                    cancel.throwIfCanceled()
                                    val n = input.read(buffer)
                                    if (n < 0) break
                                    totalBytes += n
                                    check(totalBytes <= BYTE_LIMIT) { "Batch input exceeds 512 MiB." }
                                    output.write(buffer, 0, n)
                                }
                            }
                        } finally {
                            stream.compareAndSet(input, null)
                        }
                    }
                }
                check(target.setReadOnly()) { "Cannot make the staged file read-only." }
            }
            return true
        }
    }

    fun cancel() {
        copying?.cancel()
        stream.getAndSet(null)?.let { active -> Thread { runCatching { active.close() } }.start() }
    }
    fun forget(tokens: List<String>) { tokens.forEach { selections.remove(it) } }
    fun release(token: String?) {
        val folder = stages.remove(token) ?: return
        worker.execute { folder.deleteRecursively() }
    }
    fun close() {
        closed = true
        picker = null
        cancel()
        selections.clear()
        stages.keys.toList().forEach(::release)
        worker.shutdown()
    }

    companion object {
        private const val REQUEST = 0x4B23
        private const val BYTE_LIMIT = 512L * 1024 * 1024
        private val STAGE_NAME = Regex("batch-[0-9a-f-]{36}")

        private fun child(directory: File, display: String): File {
            // Preserve the provider's Unicode and extension. No provider-controlled name
            // may introduce a path segment. Distinct entries sharing a name get suffixes.
            val clean = display.map { if (it == '/' || it == '\\' || it.code < 32) '_' else it }
                .joinToString("").let { if (it.isBlank() || it == "." || it == "..") "Document" else it }
            val dot = clean.lastIndexOf('.').takeIf { it > 0 } ?: clean.length
            var candidate = File(directory, clean)
            var n = 2
            while (candidate.exists()) {
                candidate = File(directory, "${clean.take(dot)} (${n++})${clean.drop(dot)}")
            }
            return candidate
        }
    }
}
