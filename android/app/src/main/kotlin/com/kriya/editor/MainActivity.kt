package com.kriya.editor

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.provider.Settings
import android.webkit.MimeTypeMap
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val safChannelName = "bcode.saf"
    private val importRequestCode = 4001
    private val exportRequestCode = 4002
    private val storagePermissionRequestCode = 4003
    private val importFolderRequestCode = 4004

    private var safChannel: MethodChannel? = null
    private var pendingImport: MethodChannel.Result? = null
    private var pendingImportFolder: MethodChannel.Result? = null
    private var pendingExport: MethodChannel.Result? = null
    private var pendingStoragePermission: MethodChannel.Result? = null
    private var exportTargetPath: String? = null

    /**
     * Ceilings on a folder import.
     *
     * A whole project is copied in one go, so without these a single tap on a
     * mis-picked folder could fill the device. They sit above what a real source tree
     * needs and below what a shared-storage dump would reach.
     */
    private val maxImportFiles = 20000
    private val maxImportBytes = 512L * 1024 * 1024
    private val maxImportDepth = 32

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ExecPlugin.register(flutterEngine.dartExecutor.binaryMessenger, this)
        TermuxPlugin.register(flutterEngine.dartExecutor.binaryMessenger, this)
        TermuxPlugin.attachActivity(this)
        IntegrityPlugin.register(flutterEngine.dartExecutor.binaryMessenger, this)
        StoragePlugin.register(flutterEngine.dartExecutor.binaryMessenger)
        registerSafChannel(flutterEngine.dartExecutor.binaryMessenger)
    }

    /**
     * The Dart-side workspace root.
     *
     * This used to be `File(filesDir, "app_flutter/projects")`, which is NOT where
     * Dart looks. `path_provider`'s `getApplicationDocumentsDirectory()` resolves
     * `getDir("flutter", MODE_PRIVATE)`, i.e. `<dataDir>/app_flutter`. `filesDir`
     * is `<dataDir>/files`. Imported files therefore landed in a directory the
     * file explorer never listed.
     *
     * The private location stays the fallback. A build that targets SDK <= 28
     * reaches `sharedWorkspaceDir()` below, because Termux and the editor need to
     * agree on one plain filesystem path rather than a per-app content:// URI.
     */
    private fun projectsDir(): File {
        val dir = sharedWorkspaceDir() ?: File(dataDir, "app_flutter/projects")
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    /**
     * `/storage/emulated/0/BCode`, or null when this build has not been granted
     * access to the shared volume.
     */
    private fun sharedWorkspaceDir(): File? {
        if (!hasSharedStorageAccess()) return null
        val dir = File(Environment.getExternalStorageDirectory(), "BCode")
        if (!dir.exists() && !dir.mkdirs()) return null
        return dir
    }

    private fun targetSdkVersion(): Int =
        packageManager.getPackageInfo(packageName, 0).applicationInfo?.targetSdkVersion
            ?: Build.VERSION_CODES.P

    private fun registerSafChannel(messenger: BinaryMessenger) {
        val channel = MethodChannel(messenger, safChannelName)
        safChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                // Shared storage is opt-in, so the normal answer is "no". On a
                // build that targets SDK <= 28 the legacy install-time grant is all
                // that is needed and it can be asked for as a dialog; on a modern
                // build it needs All-files access, which can only be granted on a
                // system settings screen, so the caller sends the user there.
                "requestStoragePermission" -> {
                    if (hasLegacyStoragePermission()) {
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }

                // Lets the caller show accurate UI: whether the app may use the
                // shared volume, and whether a modern build needs All-files access
                // rather than the plain storage permission.
                "sharedWorkspaceStatus" -> {
                    result.success(
                        mapOf(
                            "granted" to hasSharedStorageAccess(),
                            "needsAllFiles" to (targetSdkVersion() > Build.VERSION_CODES.Q),
                            "path" to sharedWorkspaceDir()?.absolutePath,
                        )
                    )
                }

                "openAllFilesAccessSettings" -> {
                    val opened = openAllFilesAccessSettings()
                    result.success(opened)
                }

                "sharedWorkspacePath" ->
                    result.success(sharedWorkspaceDir()?.absolutePath)

                "importFile" -> {
                    pendingImport = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                    }
                    startActivityForResult(intent, importRequestCode)
                }

                /**
                 * Copies a whole project folder off the device and into the workspace.
                 *
                 * The editor's filesystem layer is built around one plain directory
                 * tree, and every other feature — run configs, the live server, git,
                 * Termux — assumes paths under that root. Opening the picked tree in
                 * place would mean a second `FsService` backed by `content://` URIs,
                 * which none of those could use. So the folder is copied in, exactly
                 * as `importFile` copies in a single file, and the user gets a real
                 * project to work on. Edits land in the copy; pointing the editor at
                 * files that other apps can also reach is what the shared folder in
                 * Settings is for.
                 */
                "importFolder" -> {
                    pendingImportFolder = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                        addFlags(
                            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
                        )
                    }
                    try {
                        startActivityForResult(intent, importFolderRequestCode)
                    } catch (e: Exception) {
                        pendingImportFolder = null
                        result.error(
                            "NO_PICKER",
                            "This device has no folder picker.",
                            null
                        )
                    }
                }

                "exportFile" -> {
                    val path = call.argument<String>("path")
                    val suggestedName = call.argument<String>("suggestedName") ?: "file.txt"
                    if (path == null) {
                        result.error("EINVAL", "path is required", null)
                    } else if (!isInsideWorkspace(path)) {
                        // Without this, any Dart-side caller could name the token
                        // store or the secure-storage blob and have it streamed
                        // into a user-visible document.
                        result.error(
                            "EPERM",
                            "Refusing to export a file outside the workspace.",
                            null
                        )
                    } else {
                        pendingExport = result
                        exportTargetPath = path
                        // A fixed text/plain made the picker append ".txt" to
                        // every exported .py/.js/.kt file. Ask for the real
                        // type, and use octet-stream when Android has no
                        // mapping, which keeps the original name.
                        val extension =
                            suggestedName.substringAfterLast('.', "").lowercase()
                        val mime =
                            MimeTypeMap.getSingleton()
                                .getMimeTypeFromExtension(extension)
                                ?: "application/octet-stream"
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = mime
                            putExtra(Intent.EXTRA_TITLE, suggestedName)
                        }
                        startActivityForResult(intent, exportRequestCode)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun isInsideWorkspace(path: String): Boolean {
        return try {
            val root = projectsDir().canonicalFile
            val target = File(path).canonicalFile
            target == root || target.path.startsWith(root.path + File.separator)
        } catch (e: Exception) {
            false
        }
    }

    /** DISPLAY_NAME for [uri], or null when the provider does not offer one. */
    /**
     * Display name of the folder a tree picker returned.
     *
     * A tree URI does not itself carry `DISPLAY_NAME` — querying it directly answers
     * null, which is why the imported folder was being called "project" instead of its
     * real name. The name lives on the tree's own document, reached through its id.
     */
    private fun queryTreeDisplayName(treeUri: Uri): String? {
        return try {
            val documentId = DocumentsContract.getTreeDocumentId(treeUri)
            queryDisplayName(
                DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)
            )
        } catch (e: Exception) {
            null
        }
    }

    private fun queryDisplayName(uri: Uri): String? {
        return try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0 && cursor.moveToFirst()) cursor.getString(index) else null
                }
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Resolves a display name for a picked document.
     *
     * `Uri.lastPathSegment` is a document id such as `primary:Download/foo.py`
     * or `msf:1234`, not a file name. A `/` in it makes `File(dir, name)` point
     * at a non-existent subdirectory, and a `..` segment from a hostile
     * `DocumentsProvider` would be honoured verbatim.
     */
    private fun displayNameFor(uri: Uri, fallback: String): String {
        val raw = queryDisplayName(uri) ?: uri.lastPathSegment ?: fallback
        val base = File(raw.replace('\\', '/')).name
        val cleaned = base
            .replace(Regex("[^A-Za-z0-9._-]"), "_")
            .trimStart('.')
            .ifEmpty { fallback }

        return if (cleaned.length > 120) cleaned.takeLast(120) else cleaned
    }

    private fun uniqueDestination(dir: File, name: String): File {
        var dest = File(dir, name)
        if (!dest.exists()) return dest
        val base = name.substringBeforeLast('.', name)
        val ext = name.substringAfterLast('.', "")
        var counter = 1
        while (dest.exists()) {
            val candidate = if (ext.isEmpty()) "${base}_${counter++}" else "${base}_${counter++}.$ext"
            dest = File(dir, candidate)
        }
        return dest
    }

    /**
     * Keeps a single path component usable as a name.
     *
     * Deliberately more permissive than [displayNameFor]: a project tree is full of
     * names this editor should not mangle (`Ünicode.kt`, `my file (1).txt`), and the
     * only things that actually matter are that the result cannot climb out of its
     * parent and cannot contain a NUL.
     */
    private fun safeEntryName(raw: String): String? {
        val base = raw.replace('\\', '/').substringAfterLast('/')
        if (base.isEmpty() || base == "." || base == "..") return null
        if (base.any { it == '\u0000' }) return null
        return if (base.length > 200) base.takeLast(200) else base
    }

    /**
     * Copies the tree behind [treeUri] into [dest], breadth-first.
     *
     * Breadth-first with an explicit queue rather than recursion: a deep tree must not
     * be able to exhaust the stack, and it makes the depth ceiling a property of the
     * queue entry instead of a call-depth check.
     */
    private fun copyTree(
        treeUri: Uri,
        dest: File,
        label: String,
        onProgress: (Int, Long) -> Unit,
    ): Triple<Int, Long, Boolean> {
        val rootId = DocumentsContract.getTreeDocumentId(treeUri)
        var files = 0
        var bytes = 0L
        var truncated = false

        if (!dest.exists() && !dest.mkdirs()) {
            throw IllegalStateException("Could not create ${dest.name}")
        }

        // The third element is the depth below [dest], which is what the ceiling is
        // measured against. Counting from the filesystem root would make the limit
        // depend on where the app happens to be installed.
        val queue = ArrayDeque<Triple<String, File, Int>>()
        queue.add(Triple(rootId, dest, 0))

        while (queue.isNotEmpty()) {
            val (parentId, parentDir, depth) = queue.removeFirst()
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
                treeUri,
                parentId
            )
            contentResolver.query(
                childrenUri,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                ),
                null,
                null,
                null
            )?.use { cursor ->
                val idIdx =
                    cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                val nameIdx = cursor
                    .getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                val mimeIdx =
                    cursor.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)

                while (cursor.moveToNext()) {
                    if (files >= maxImportFiles || bytes >= maxImportBytes) {
                        truncated = true
                        break
                    }
                    if (idIdx < 0 || nameIdx < 0 || mimeIdx < 0) continue

                    val childId = cursor.getString(idIdx) ?: continue
                    val rawName = cursor.getString(nameIdx) ?: continue
                    val mime = cursor.getString(mimeIdx)
                        ?: "application/octet-stream"
                    val name = safeEntryName(rawName) ?: continue

                    val childUri =
                        DocumentsContract.buildDocumentUriUsingTree(treeUri, childId)

                    if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                        val childDir = File(parentDir, name)
                        if (!childDir.isDirectory && !childDir.mkdirs()) continue
                        if (depth + 1 <= maxImportDepth) {
                            queue.add(Triple(childId, childDir, depth + 1))
                        }
                        continue
                    }

                    val out = File(parentDir, name)
                    val input = contentResolver.openInputStream(childUri)
                    if (input == null) continue
                    var copied = 0L
                    input.use { source ->
                        out.outputStream().use { sink ->
                            copied = source.copyTo(sink)
                        }
                    }
                    bytes += copied
                    files++
                    if (files % 24 == 0) onProgress(files, bytes)
                }
            }
            if (truncated) break
        }

        onProgress(files, bytes)
        return Triple(files, bytes, truncated)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            9913 -> TermuxPlugin.onRequestPermissionsResult(grantResults)
            storagePermissionRequestCode -> {
                val result = pendingStoragePermission
                pendingStoragePermission = null
                result?.success(
                    grantResults.isNotEmpty() &&
                        grantResults[0] == PackageManager.PERMISSION_GRANTED &&
                        hasLegacyStoragePermission(),
                )
            }
        }
    }

    private fun hasLegacyStoragePermission(): Boolean =
        ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.READ_EXTERNAL_STORAGE,
        ) == PackageManager.PERMISSION_GRANTED

    /**
     * Whether this build is allowed to use the shared volume right now.
     *
     * Two different grants lead to the same capability depending on targetSdk: a
     * build targeting SDK <= 28 gets it from the install-time storage permission,
     * while a modern build needs All-files access, which the user grants on a
     * system screen and which is revocable at any time.
     */
    private fun hasSharedStorageAccess(): Boolean =
        if (targetSdkVersion() > Build.VERSION_CODES.Q) {
            Environment.isExternalStorageManager()
        } else {
            hasLegacyStoragePermission()
        }

    /** Sends the user to the system screen where All-files access is granted. */
    private fun openAllFilesAccessSettings(): Boolean {
        val direct = Intent(
            Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
            Uri.parse("package:$packageName"),
        )
        if (safeStart(direct)) return true
        return safeStart(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
    }

    private fun safeStart(intent: Intent): Boolean = try {
        startActivity(intent)
        true
    } catch (_: Exception) {
        false
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            importRequestCode -> {
                val result = pendingImport
                pendingImport = null
                val uri: Uri? = if (resultCode == RESULT_OK) data?.data else null
                if (uri == null || result == null) {
                    result?.success(null)
                    return
                }
                try {
                    val input = contentResolver.openInputStream(uri)
                    if (input == null) {
                        result.error("IMPORT_FAILED", "Cannot open input stream", null)
                        return
                    }
                    val dir = projectsDir()
                    val dest = uniqueDestination(dir, displayNameFor(uri, "imported.txt"))
                    input.use { stream ->
                        dest.outputStream().use { output -> stream.copyTo(output) }
                    }
                    result.success(dest.absolutePath)
                } catch (e: Exception) {
                    result.error("IMPORT_FAILED", e.message, null)
                }
            }

            importFolderRequestCode -> {
                val result = pendingImportFolder
                pendingImportFolder = null
                val uri: Uri? = if (resultCode == RESULT_OK) data?.data else null
                if (uri == null || result == null) {
                    result?.success(null)
                    return
                }

                // Held for the duration of the copy so the grant survives the process
                // being killed mid-import. Best effort: some providers refuse.
                try {
                    contentResolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION
                    )
                } catch (_: Exception) {
                }

                val label = safeEntryName(queryTreeDisplayName(uri) ?: "") ?: "project"

                val dest = uniqueDestination(projectsDir(), label)

                // Off the main thread, and mandatory rather than tidy: copying a real
                // project is seconds to minutes of blocking I/O, and doing it in
                // onActivityResult is what produces an ANR dialog with no way out.
                Thread {
                    try {
                        val stats = copyTree(uri, dest, label) { files, bytes ->
                            runOnUiThread {
                                safChannel?.invokeMethod(
                                    "importProgress",
                                    mapOf(
                                        "name" to label,
                                        "files" to files,
                                        "bytes" to bytes
                                    )
                                )
                            }
                        }
                        runOnUiThread {
                            result.success(
                                mapOf(
                                    "path" to dest.absolutePath,
                                    "files" to stats.first,
                                    "bytes" to stats.second,
                                    "truncated" to stats.third
                                )
                            )
                        }
                    } catch (e: Exception) {
                        // A failed import must not leave debris that looks like a
                        // project the user can open.
                        try {
                            if (dest.exists()) dest.deleteRecursively()
                        } catch (_: Exception) {
                        }
                        runOnUiThread {
                            result.error(
                                "IMPORT_FAILED",
                                e.message ?: "Could not read that folder.",
                                null
                            )
                        }
                    }
                }.start()
            }

            exportRequestCode -> {
                val result = pendingExport
                val source = exportTargetPath
                pendingExport = null
                exportTargetPath = null
                val uri: Uri? = if (resultCode == RESULT_OK) data?.data else null
                if (uri == null || result == null || source == null) {
                    result?.success(false)
                    return
                }
                if (!isInsideWorkspace(source)) {
                    result.error("EPERM", "Refusing to export a file outside the workspace.", null)
                    return
                }
                try {
                    val output = contentResolver.openOutputStream(uri)
                    if (output == null) {
                        result.error("EXPORT_FAILED", "Cannot open output stream", null)
                        return
                    }
                    File(source).inputStream().use { input ->
                        output.use { out -> input.copyTo(out) }
                    }
                    result.success(true)
                } catch (e: Exception) {
                    result.error("EXPORT_FAILED", e.message, null)
                }
            }
        }
    }
}