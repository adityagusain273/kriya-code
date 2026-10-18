package com.bcode.editor

import android.content.Intent
import android.net.Uri
import android.os.Environment
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val safChannelName = "bcode.saf"
    private val importRequestCode = 4001
    private val exportRequestCode = 4002
    private val pickDirectoryRequestCode = 4004

    private var pendingImport: MethodChannel.Result? = null
    private var pendingExport: MethodChannel.Result? = null
    private var pendingPickDirectory: MethodChannel.Result? = null
    private var exportTargetPath: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ExecPlugin.register(flutterEngine.dartExecutor.binaryMessenger, this)
        TermuxPlugin.register(flutterEngine.dartExecutor.binaryMessenger, this)
        registerSafChannel(flutterEngine.dartExecutor.binaryMessenger)
        registerStorageChannel(flutterEngine.dartExecutor.binaryMessenger)
    }

    private fun registerStorageChannel(messenger: BinaryMessenger) {
        MethodChannel(messenger, "bcode.storage").setMethodCallHandler { call, result ->
            when (call.method) {
                "getExternalStorageDirectory" -> {
                    val path = Environment.getExternalStorageDirectory().absolutePath
                    result.success(path)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun projectsDir(): File {
        val dir = File(filesDir, "app_flutter/projects")
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    private fun registerSafChannel(messenger: BinaryMessenger) {
        MethodChannel(messenger, safChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestStoragePermission" -> {
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                        if (!android.os.Environment.isExternalStorageManager()) {
                            val intent = Intent(android.provider.Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                            intent.data = Uri.parse("package:" + context.packageName)
                            startActivity(intent)
                            result.success(false)
                        } else {
                            result.success(true)
                        }
                    } else {
                        if (checkSelfPermission(android.Manifest.permission.READ_EXTERNAL_STORAGE) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                            requestPermissions(arrayOf(android.Manifest.permission.READ_EXTERNAL_STORAGE, android.Manifest.permission.WRITE_EXTERNAL_STORAGE), 4003)
                            result.success(false)
                        } else {
                            result.success(true)
                        }
                    }
                }
                "importFile" -> {
                    pendingImport = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                    }
                    startActivityForResult(intent, importRequestCode)
                }
                "exportFile" -> {
                    val path = call.argument<String>("path")
                    val suggestedName = call.argument<String>("suggestedName") ?: "file.txt"
                    if (path == null) {
                        result.error("EINVAL", "path is required", null)
                    } else {
                        pendingExport = result
                        exportTargetPath = path
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TITLE, suggestedName)
                        }
                        startActivityForResult(intent, exportRequestCode)
                    }
                }
                "pickDirectory" -> {
                    pendingPickDirectory = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                    startActivityForResult(intent, pickDirectoryRequestCode)
                }
                else -> result.notImplemented()
            }
        }
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
                    input.use { stream ->
                        val name = uri.lastPathSegment ?: "imported.txt"
                        var dest = File(projectsDir(), name)
                        if (dest.exists()) {
                            val base = name.substringBeforeLast('.')
                            val ext = name.substringAfterLast('.', "")
                            var counter = 1
                            while (dest.exists()) {
                                dest = File(projectsDir(), if (ext.isEmpty()) "${base}_${counter++}" else "${base}_${counter++}.$ext")
                            }
                        }
                        dest.outputStream().use { output -> stream.copyTo(output) }
                        result.success(dest.name)
                    }
                } catch (e: Exception) {
                    result.error("IMPORT_FAILED", e.message, null)
                }
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
            pickDirectoryRequestCode -> {
                val result = pendingPickDirectory
                pendingPickDirectory = null
                val uri: Uri? = if (resultCode == RESULT_OK) data?.data else null
                if (uri == null || result == null) {
                    result?.success(null)
                    return
                }
                try {
                    val takeFlags: Int = Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    contentResolver.takePersistableUriPermission(uri, takeFlags)

                    // Convert URI to absolute path
                    val path = uri.path
                    if (path != null && path.contains(":")) {
                        val split = path.split(":")
                        val type = split[0]
                        val relativePath = if (split.size > 1) split[1] else ""
                        
                        var absPath = "/storage/emulated/0"
                        if (type.contains("primary")) {
                            absPath = "/storage/emulated/0/$relativePath"
                        } else {
                            // Basic fallback for SD cards
                            absPath = "/storage/${type.substringAfterLast("/")}/$relativePath"
                        }
                        
                        // Clean up trailing slash just in case
                        if (absPath.endsWith("/")) {
                            absPath = absPath.dropLast(1)
                        }
                        result.success(absPath)
                    } else {
                        result.success(null)
                    }
                } catch (e: Exception) {
                    result.error("PICK_DIR_FAILED", e.message, null)
                }
            }
        }
    }
}
