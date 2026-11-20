package com.kriya.editor

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.system.Os
import android.system.OsConstants
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.apache.commons.compress.archivers.ar.ArArchiveInputStream
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream
import org.apache.commons.compress.compressors.gzip.GzipCompressorInputStream
import org.apache.commons.compress.compressors.xz.XZCompressorInputStream
import com.github.luben.zstd.ZstdInputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.io.IOException
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

object ExecPlugin {
    private const val CHANNEL = "bcode.exec"
    private const val RUN_CHANNEL = "bcode.exec/stream"
    private const val TERMUX_PREFIX = "data/data/com.termux/files/usr/"
    private const val MAX_ARGV_SIZE = 256
    private const val MAX_ENV_SIZE = 65536
    // Matches the Dart-side cap in lib/core/archive_extractor.dart
    // (ArchiveExtractor.maxTotalBytes). A phone has no business unpacking 4 GiB.
    private const val MAX_EXTRACTED_BYTES = 512L * 1024 * 1024
    private const val MAX_ARCHIVE_ENTRIES = 200000
    private const val MAX_CAPTURED_OUTPUT_BYTES = 8 * 1024 * 1024
    private val RUNTIME_ID_PATTERN = Regex("[a-z0-9][a-z0-9._-]{0,31}")

    /// Per-file digest manifest written next to an extracted runtime and
    /// checked before every exec of a runtime binary. The name follows the
    /// `sha256sum` line format: `<hex> <relative-path>`.
    private const val MANIFEST_NAME = "integrity.sha256"

    /// SharedPreferences file holding the digest of each runtime's manifest.
    ///
    /// Binding the manifest to a second storage location means tampering with
    /// the runtime tree alone is detected even when the attacker regenerates
    /// the manifest to match. This is NOT cryptographically bound: an attacker
    /// who can deliberately write both the runtime tree and this prefs file
    /// (root, or code running as the app uid) can recompute both. The control
    /// catches accidental corruption and undeliberate or naive writes -- it
    /// does not stop a determined attacker with app-uid write access.
    private const val INTEGRITY_PREFS = "runtime_integrity"

    private val SYSTEM_PREFIXES = listOf(
        "/system", "/system_ext", "/apex", "/vendor", "/product", "/odm",
        "/storage", "/sdcard", "/mnt", "/data/dalvik-cache",
    )

    private val BLOCKED_ENV_KEYS = setOf(
        "LD_PRELOAD", "LD_LIBRARY_PATH", "LD_AUDIT", "LD_ORIGIN_PATH",
        "LD_CONFIG_FILE", "LD_DEBUG", "LD_DYNAMIC_WEAK",
        "DYLD_INSERT_LIBRARIES", "DYLD_LIBRARY_PATH",
        "MALLOC_OPTIONS", "MALLOC_CONF", "GLIBC_TUNABLES",
        "BASH_ENV", "ENV", "SHELLOPTS", "BASHOPTS", "PROMPT_COMMAND",
        "CDPATH", "GLOBIGNORE", "HISTFILE", "PERL5OPT", "RUBYOPT",
        "PYTHONPATH", "PYTHONSTARTUP", "PYTHONWARNINGS",
        "NODE_OPTIONS", "NODE_REPL_EXTERNAL_MODULE",
        // PATH is blocked because it is installed by exec() *after* the command
        // was validated. Letting a run config override it means the process runs
        // against a different PATH than the one the command was checked against.
        "PATH",
    )

    // Extraction and execution are deliberately separate: unpacking an OpenJDK or
    // Node tree is thousands of synchronous writes, and sharing one single-thread
    // executor meant a Run press sat queued behind it for minutes.
    private val executor = Executors.newSingleThreadExecutor()
    private val extractionExecutor = Executors.newSingleThreadExecutor()
    private val ioExecutor = Executors.newCachedThreadPool()
    private lateinit var appContext: Context
    private val mainHandler = Handler(Looper.getMainLooper())

    /// Runs currently alive, keyed by the Dart-side run id. `kill` arrives on
    /// the main thread while `exec` blocks an executor thread.
    private val activeProcesses = ConcurrentHashMap<String, Process>()
    private lateinit var runChannel: EventChannel
    // Written on the main thread when Dart subscribes, read on the exec thread.
    @Volatile private var eventSink: EventChannel.EventSink? = null

    // Sandbox: allowed root directories that commands can access
    private val allowedRoots = ConcurrentHashMap<String, Boolean>()

    // Performance caches for runtime binary and manifest integrity verification
    private val verifiedBinaries = ConcurrentHashMap<String, Long>()
    private val manifestCache = ConcurrentHashMap<String, Pair<Long, Map<String, String>>>()
    private val manifestHashCache = ConcurrentHashMap<String, Pair<Long, String>>()

    private fun runOnMain(block: () -> Unit) {
        mainHandler.post(block)
    }

    /// Sends one stdout/stderr chunk to Dart without waiting for process exit.
    private fun emit(runId: String, stream: String, data: String) {
        mainHandler.post {
            eventSink?.success(mapOf(
                "runId" to runId,
                "stream" to stream,
                "data" to data,
            ))
        }
    }

    // Roots that are always allowed because they are owned by the app or the
    // OS. setSandboxPaths must NEVER remove these, or validateCommandPath would
    // reject every bundled runtime binary.
    private val baseRoots = ConcurrentHashMap<String, Boolean>()

    private fun initializeAllowedRoots() {
        baseRoots[appContext.filesDir.canonicalPath] = true
        baseRoots[appContext.cacheDir.canonicalPath] = true
        baseRoots["/system/bin"] = true
        baseRoots["/system/xbin"] = true
        baseRoots[runtimesRoot().canonicalPath] = true
        val termuxPrefix = "/data/data/com.termux/files/usr"
        if (File(termuxPrefix).exists()) {
            baseRoots[termuxPrefix] = true
        }
        allowedRoots.clear()
        allowedRoots.putAll(baseRoots)
    }

    /**
     * Component-wise containment test.
     *
     * The previous implementation used a bare `String.startsWith`, which accepts
     * any sibling whose name merely starts with a root's basename: with
     * `/storage/emulated/0/MyProject` allowed, `/storage/emulated/0/MyProjectEvil/bin/sh`
     * also passed. Comparing against `root + separator` closes that.
     */
    private fun isWithinAnyRoot(canonical: String): Boolean =
        allowedRoots.keys.any { root ->
            canonical == root || canonical.startsWith(root + File.separator)
        }

    private fun canonicalOf(path: String): String? = try {
        File(path).canonicalPath
    } catch (e: Exception) {
        null
    }

    /// Opens Android's package installer for an artifact APK in the app cache.
    ///
    /// The path is restricted to `cache/cloud_build`, the only place the artifact
    /// unpacker writes, so this method cannot be used to expose other app files.
    private fun installApk(path: String): Boolean {
        return try {
            val file = File(path).canonicalFile
            val cacheRoot = File(appContext.cacheDir, "cloud_build").canonicalFile
            if (!file.isFile) return false
            if (!file.path.startsWith(cacheRoot.path + File.separator)) return false
            if (!file.name.endsWith(".apk")) return false
            val uri = FileProvider.getUriForFile(
                appContext,
                "${appContext.packageName}.fileprovider",
                file,
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            appContext.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun isWithinSandbox(path: String): Boolean {
        val canonical = canonicalOf(path) ?: return false
        return isWithinAnyRoot(canonical)
    }

    private fun validateCommandPath(argv: List<String>): String? {
        if (argv.isEmpty()) return "argv is empty"
        val command = argv[0]
        val commandFile = File(command)

        // If absolute path, validate directly
        if (commandFile.isAbsolute) {
            val canonical = canonicalOf(commandFile.path)
                ?: return "Cannot resolve command path"
            if (!isWithinAnyRoot(canonical)) {
                return "Command outside sandbox: $canonical"
            }
            if (!commandFile.exists()) return "Command not found: $command"
            if (!commandFile.canExecute()) return "Command not executable: $command"
            return null
        }

        // Relative command - resolve via PATH (same as exec() does)
        val pathEntries = buildPathEntries()
        for (pathDir in pathEntries) {
            val candidate = File(pathDir, command)
            if (candidate.exists() && candidate.canExecute()) {
                val canonical = canonicalOf(candidate.path) ?: continue
                if (isWithinAnyRoot(canonical)) return null
            }
        }
        return "Command not found in PATH: $command"
    }

    private fun buildPathEntries(): List<String> {
        val entries = mutableListOf<String>()
        entries.add(appContext.applicationInfo.nativeLibraryDir)
        entries.add("/system/bin")
        entries.add("/system/xbin")
        runtimesRoot().listFiles()?.forEach { runtime ->
            File(runtime, "bin").takeIf { it.exists() }?.let { entries.add(0, it.absolutePath) }
        }
        return entries
    }

    private fun validateArgv(argv: List<String>): String? {
        if (argv.size > MAX_ARGV_SIZE) return "argv exceeds maximum length ($MAX_ARGV_SIZE)"
        if (argv.isEmpty()) return "argv is empty"

        for (arg in argv) {
            if (arg.contains('\u0000')) return "Null byte in argument"
        }
        return null
    }

    private fun validateEnv(env: Map<String, String>): Map<String, String> {
        var totalSize = 0
        return env.filter { (key, value) ->
            if (key in BLOCKED_ENV_KEYS) return@filter false
            if (key.startsWith("_")) return@filter false
            totalSize += key.length + value.length + 2
            totalSize <= MAX_ENV_SIZE
        }
    }

    fun register(messenger: BinaryMessenger, context: Context) {
        appContext = context.applicationContext
        initializeAllowedRoots()

        runChannel = EventChannel(messenger, RUN_CHANNEL)
        runChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })

        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasRuntime" -> {
                    val runtimeId = call.argument<String>("runtimeId") ?: ""
                    // runtimeDir throws on malformed ids; an invalid id just has
                    // no runtime installed, so report false instead of letting
                    // the exception escape the channel handler.
                    val has = try { runtimeDir(runtimeId).exists() } catch (_: IllegalArgumentException) { false }
                    result.success(has)
                }
                "runtimesDir" -> {
                    result.success(runtimesRoot().absolutePath)
                }
                "extractRuntime" -> {
                    val runtimeId = call.argument<String>("runtimeId") ?: ""
                    extractionExecutor.submit {
                        try {
                            extractRuntime(runtimeId)
                            runOnMain { result.success(true) }
                        } catch (e: Exception) {
                            runOnMain { result.error("EXTRACT_FAILED", e.message, null) }
                        }
                    }
                }
                "exec" -> {
                    val argv = call.argument<List<String>>("argv") ?: emptyList()
                    val cwd = call.argument<String>("cwd") ?: appContext.filesDir.absolutePath
                    val env = call.argument<Map<String, String>>("env") ?: emptyMap()
                    val timeoutMs = (call.argument<Number>("timeoutMs")?.toLong()) ?: 30_000L
                    val runId = call.argument<String>("runId")

                    val validationError = validateArgv(argv)
                    if (validationError != null) {
                        result.error("EINVAL", validationError, null)
                        return@setMethodCallHandler
                    }

                    if (!isWithinSandbox(cwd)) {
                        result.error("EPERM", "Working directory outside sandbox: $cwd", null)
                        return@setMethodCallHandler
                    }

                    val cmdError = validateCommandPath(argv)
                    if (cmdError != null) {
                        result.error("EPERM", cmdError, null)
                        return@setMethodCallHandler
                    }

                    val safeEnv = validateEnv(env)

                    executor.submit {
                        try {
                            val output = exec(argv, cwd, safeEnv, timeoutMs, runId)
                            runOnMain { result.success(output) }
                        } catch (e: RuntimeIntegrityException) {
                            runOnMain { result.error("RUNTIME_INTEGRITY", e.message, null) }
                        } catch (e: Exception) {
                            runOnMain {
                                val denial = explainExecDenial(e, argv)
                                if (denial != null) {
                                    result.error("EXEC_DENIED_BY_PLATFORM", denial, null)
                                } else {
                                    result.error("EXEC_FAILED", e.message, null)
                                }
                            }
                        }
                    }
                }
                "kill" -> {
                    val runId = call.argument<String>("runId")
                    val process = runId?.let { activeProcesses.remove(it) }
                    try { process?.outputStream?.close() } catch (_: Exception) {}
                    process?.destroyForcibly()
                    result.success(process != null)
                }
                "sendStdin" -> {
                    val runId = call.argument<String>("runId")
                    val input = call.argument<String>("input") ?: ""
                    val process = runId?.let { activeProcesses[it] }
                    if (process != null) {
                        try {
                            val line = if (input.endsWith("\n")) input else "$input\n"
                            process.outputStream.write(line.toByteArray(Charsets.UTF_8))
                            process.outputStream.flush()
                            result.success(true)
                        } catch (e: IOException) {
                            android.util.Log.w("ExecPlugin", "Failed to write stdin for $runId", e)
                            result.success(false)
                        } catch (e: Exception) {
                            android.util.Log.w("ExecPlugin", "Unexpected error writing stdin for $runId", e)
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }
                "installApk" -> {
                    val path = call.argument<String>("path") ?: ""
                    result.success(installApk(path))
                }
                "setSandboxPaths" -> {
                    // Replaces the dynamic root set rather than adding to it.
                    //
                    // Roots were only ever added and never revoked, so a user who
                    // once pointed the workspace at shared storage kept that root
                    // as an exec root forever -- and any executable another app
                    // planted there became runnable. Callers must now send the
                    // full desired set each time.
                    val paths = call.argument<List<String>>("paths") ?: emptyList()
                    try {
                        val canonical = paths.mapNotNull { path ->
                            canonicalOf(path)?.takeIf { it.isNotBlank() }
                        }
                        // Drop the old dynamic roots but keep the base roots that
                        // cover the bundled runtimes, cache, files dir, and /system.
                        allowedRoots.keys.retainAll(baseRoots.keys)
                        for (path in canonical) {
                            allowedRoots[path] = true
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("EINVAL", "Invalid path: ${e.message}", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun runtimesRoot(): File = File(appContext.filesDir, "runtimes")

    private fun runtimeDir(runtimeId: String): File {
        if (!RUNTIME_ID_PATTERN.matches(runtimeId)) {
            throw IllegalArgumentException("Invalid runtimeId: $runtimeId")
        }
        val root = runtimesRoot().canonicalFile
        val dir = File(root, runtimeId).canonicalFile
        if (dir.parentFile != root) {
            throw IllegalArgumentException("runtimeId escapes the runtimes directory: $runtimeId")
        }
        return dir
    }

    private fun extractRuntime(runtimeId: String) {
        manifestCache.remove(runtimeId)
        manifestHashCache.remove(runtimeId)
        verifiedBinaries.clear()
        val dest = runtimeDir(runtimeId)
        // Fail before touching the archive when the volume cannot hold the
        // ceiling we allow, rather than dying mid-extraction with ENOSPC.
        if (dest.exists()) {
            val available = StatFs(dest.canonicalPath).availableBytes
            if (available < MAX_EXTRACTED_BYTES) {
                throw IllegalStateException(
                    "Not enough free space to extract $runtimeId " +
                        "(need ${MAX_EXTRACTED_BYTES / (1024 * 1024)} MiB, " +
                        "have ${available / (1024 * 1024)} MiB)"
                )
            }
        }
        val pkgsDir = File(dest, "pkgs")
        val debs = pkgsDir.listFiles()?.filter { it.name.endsWith(".deb") }
            ?: throw IllegalStateException("No downloaded packages for $runtimeId")
        if (debs.isEmpty()) throw IllegalStateException("No downloaded packages for $runtimeId")
        for (deb in debs.sortedBy { it.name }) {
            extractDeb(deb, dest)
        }
        File(dest, "pkgs").let { pkgs ->
            pkgs.listFiles()?.forEach { it.delete() }
            pkgs.delete()
        }
        // The manifest is written only after every file is on disk, so it
        // describes the tree as it will be executed, not an intermediate state.
        writeIntegrityManifest(dest)
    }

    /// Records the SHA-256 of every regular file under [dest] (the runtime's
    /// own directory) in `integrity.sha256`, and records the manifest's own
    /// digest in SharedPreferences.
    ///
    /// Symlinks are skipped, and symlinked directories are not descended
    /// into: their targets are regular files inside [dest] (extraction
    /// re-roots links and refuses escapes) and are hashed in their own right,
    /// so walking only real entries also makes cyclic links harmless. A stale
    /// manifest from a previous install is removed before the walk so it
    /// cannot end up listed inside its own replacement.
    ///
    /// Uses Os.lstat rather than java.nio.file, which only exists from API 26
    /// while minSdk is 24.
    private fun writeIntegrityManifest(dest: File) {
        val manifestFile = File(dest, MANIFEST_NAME)
        manifestFile.delete()
        val files = mutableListOf<File>()
        collectRegularFiles(dest, files)
        val content = files
            .map { it.relativeTo(dest).path to sha256Hex(it) }
            .sortedBy { it.first }
            .joinToString("\n") { (rel, hex) -> "$hex $rel" }
        manifestFile.writeText(if (content.isEmpty()) "" else "$content\n")
        appContext.getSharedPreferences(INTEGRITY_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(dest.name, sha256Hex(manifestFile))
            .apply()
    }

    /// Depth-first collection of real files below [dir], refusing to follow
    /// symlinks anywhere in the tree.
    private fun collectRegularFiles(dir: File, out: MutableList<File>) {
        for (child in dir.listFiles() ?: return) {
            when (entryKind(child)) {
                EntryKind.SYMLINK -> {}
                EntryKind.DIRECTORY -> collectRegularFiles(child, out)
                EntryKind.FILE -> out.add(child)
                EntryKind.OTHER -> {}
            }
        }
    }

    private enum class EntryKind { SYMLINK, DIRECTORY, FILE, OTHER }

    /// Classifies [file] without following its final component, so a link is
    /// never mistaken for the file it points at.
    private fun entryKind(file: File): EntryKind = try {
        val mode = Os.lstat(file.path).st_mode
        when (mode and OsConstants.S_IFMT) {
            OsConstants.S_IFLNK -> EntryKind.SYMLINK
            OsConstants.S_IFDIR -> EntryKind.DIRECTORY
            OsConstants.S_IFREG -> EntryKind.FILE
            else -> EntryKind.OTHER
        }
    } catch (_: Exception) {
        EntryKind.OTHER
    }

    /// Reads the manifest into a relative-path -> digest map.
    private fun readIntegrityManifest(manifestFile: File): Map<String, String> {
        val map = mutableMapOf<String, String>()
        manifestFile.useLines { lines ->
            for (line in lines) {
                if (line.isEmpty()) continue
                val hex = line.substringBefore(' ')
                val rel = line.substringAfter(' ', "")
                if (hex.length == 64 && rel.isNotEmpty()) map[rel] = hex
            }
        }
        return map
    }

    /// Throws [RuntimeIntegrityException] when the program about to be exec'd
    /// is an app-unpacked runtime binary whose bytes no longer match the
    /// manifest recorded at extraction time.
    ///
    /// Only the program itself is re-hashed per exec, not the whole tree: the
    /// manifest covers the full contents for install-time and offline checks,
    /// while per-exec hashing stays proportional to one binary.
    private fun verifyRuntimeBinary(argv: List<String>) {
        val command = argv.firstOrNull() ?: return
        val target = if (File(command).isAbsolute) {
            File(command)
        } else {
            val dir = buildPathEntries().firstOrNull { candidate ->
                File(candidate, command).exists() && File(candidate, command).canExecute()
            } ?: return
            File(dir, command)
        }
        if (isSystemPath(target.path)) return

        val rootRaw = runtimesRoot().absolutePath + File.separator
        val rootCanonical = runtimesRoot().canonicalPath + File.separator
        val canonical = canonicalOf(target.path)

        // Membership is decided on the canonical path, so equivalent spellings
        // of the data directory (/data/data/<pkg> vs /data/user/0/<pkg>) are
        // treated the same. A path that names the runtime tree but resolves
        // outside it is a re-pointed symlink, not a legitimate binary.
        if (canonical != null && canonical.startsWith(rootCanonical)) {
            verifyAgainstManifest(canonical, rootCanonical)
        } else if (target.absolutePath.startsWith(rootRaw)) {
            throw RuntimeIntegrityException(
                "Runtime binary resolves outside the runtime directory: ${target.path}"
            )
        }
    }

    /// [canonical] is a file inside the runtimes root; check it against the
    /// owning runtime's manifest and the manifest's own bound digest.
    private fun verifyAgainstManifest(canonical: String, rootCanonical: String) {
        val targetFile = File(canonical)
        val targetMtime = targetFile.lastModified()
        if (verifiedBinaries[canonical] == targetMtime) {
            return
        }

        val relToRoot = canonical.removePrefix(rootCanonical)
        val runtimeId = relToRoot.substringBefore(File.separatorChar)
        if (!RUNTIME_ID_PATTERN.matches(runtimeId)) {
            throw RuntimeIntegrityException("Invalid runtime directory: $runtimeId")
        }
        val relInRuntime = relToRoot.substringAfter(File.separatorChar)

        val dir = runtimeDir(runtimeId)
        val manifestFile = File(dir, MANIFEST_NAME)
        if (!manifestFile.isFile) {
            throw RuntimeIntegrityException(
                "No integrity manifest for runtime '$runtimeId'. " +
                    "Reinstall the runtime from the Runtimes screen."
            )
        }
        val bound = appContext.getSharedPreferences(INTEGRITY_PREFS, Context.MODE_PRIVATE)
            .getString(runtimeId, null)
            ?: throw RuntimeIntegrityException(
                "No integrity record for runtime '$runtimeId'. " +
                    "Reinstall the runtime from the Runtimes screen."
            )

        val manifestMtime = manifestFile.lastModified()
        val cachedHash = manifestHashCache[runtimeId]
        val manifestDigest = if (cachedHash != null && cachedHash.first == manifestMtime) {
            cachedHash.second
        } else {
            val h = sha256Hex(manifestFile)
            manifestHashCache[runtimeId] = Pair(manifestMtime, h)
            h
        }

        if (!manifestDigest.equals(bound, ignoreCase = true)) {
            throw RuntimeIntegrityException(
                "Runtime '$runtimeId' failed its integrity check. " +
                    "Reinstall the runtime from the Runtimes screen."
            )
        }

        val cachedMap = manifestCache[runtimeId]
        val manifestMap = if (cachedMap != null && cachedMap.first == manifestMtime) {
            cachedMap.second
        } else {
            val m = readIntegrityManifest(manifestFile)
            manifestCache[runtimeId] = Pair(manifestMtime, m)
            m
        }

        val expected = manifestMap[relInRuntime]
            ?: throw RuntimeIntegrityException(
                "No recorded digest for '$relInRuntime' in runtime '$runtimeId'. " +
                    "Reinstall the runtime from the Runtimes screen."
            )
        val actual = sha256Hex(targetFile)
        if (!actual.equals(expected, ignoreCase = true)) {
            throw RuntimeIntegrityException(
                "'$relInRuntime' in runtime '$runtimeId' was modified after installation. " +
                    "Reinstall the runtime from the Runtimes screen."
            )
        }
        verifiedBinaries[canonical] = targetMtime
    }

    private fun sha256Hex(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(file).use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read <= 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    /// Refusal to run a runtime binary whose bytes do not match the manifest
    /// recorded at extraction time. Distinct from [IllegalStateException] so
    /// the channel handler can surface a dedicated error code to Dart.
    private class RuntimeIntegrityException(message: String) : Exception(message)

    private fun extractDeb(deb: File, dest: File) {
        ArArchiveInputStream(FileInputStream(deb)).use { ar ->
            while (true) {
                val entry = ar.nextEntry ?: break
                val name = entry.name
                if (!name.startsWith("data.tar")) continue
                val raw: InputStream = when {
                    name.endsWith(".gz") -> GzipCompressorInputStream(ar)
                    name.endsWith(".xz") -> {
                        // Missing-library failures are Errors, not Exceptions; normalized so the
                        // MethodChannel result is answered instead of hanging on an escaped Error.
                        try {
                            XZCompressorInputStream(ar)
                        } catch (e: LinkageError) {
                            throw UnsupportedOperationException(
                                "xz decompression not available; install xz library", e)
                        }
                    }
                    name.endsWith(".zst") -> {
                        // The zstd native library cannot load on Android: any failure here is a
                        // platform gap, so convert it (incl. UnsatisfiedLinkError) to a clean refusal.
                        try {
                            ZstdInputStream(ar)
                        } catch (e: Throwable) {
                            throw UnsupportedOperationException(
                                "zstd decompression is not supported on this platform: " +
                                    "the zstd native library cannot load on Android", e)
                        }
                    }
                    else -> ar
                }
                extractTar(raw, dest)
                return
            }
        }
        throw IllegalStateException("No data.tar found in ${deb.name}")
    }

    private fun extractTar(input: InputStream, dest: File) {
        val destCanonical = dest.canonicalPath
        val destPrefix = destCanonical + File.separator
        var totalBytes = 0L
        var entryCount = 0

        TarArchiveInputStream(input).use { tar ->
            while (true) {
                val e = tar.nextTarEntry ?: break
                entryCount++
                if (entryCount > MAX_ARCHIVE_ENTRIES) {
                    throw IllegalStateException("Archive has too many entries")
                }

                val rel = stripPrefix(e.name) ?: continue
                if (rel.isEmpty() || rel.startsWith("/") || rel.contains("\\")) continue

                val outFile = File(dest, rel)
                // Component-wise containment. A bare startsWith accepted any entry
                // whose resolved path merely began with the destination string.
                val outCanonical = outFile.canonicalPath
                if (outCanonical != destCanonical && !outCanonical.startsWith(destPrefix)) continue

                if (e.size > MAX_EXTRACTED_BYTES - totalBytes) {
                    throw IllegalStateException("Archive expands beyond the extraction limit")
                }

                if (e.isDirectory) {
                    outFile.mkdirs()
                    continue
                }
                outFile.parentFile?.mkdirs()

                when {
                    e.isSymbolicLink -> {
                        // The target was previously passed to Os.symlink with no
                        // validation at all, absolute targets included. Re-root it
                        // inside the destination and refuse anything that leaves.
                        val linkName = stripPrefix(e.linkName)
                        if (linkName.isNullOrEmpty() || linkName.startsWith("/")) continue
                        val resolved = File(dest, linkName).canonicalPath
                        if (resolved != destCanonical && !resolved.startsWith(destPrefix)) continue
                        if (outFile.exists()) outFile.delete()
                        try {
                            // linkName is already relative to dest; nio
                            // relativize via File.toPath() is API 26+ while
                            // minSdk is 24.
                            Os.symlink(linkName, outFile.path)
                        } catch (_: Exception) {
                        }
                    }
                    e.isLink -> {
                        val linkName = stripPrefix(e.linkName) ?: continue
                        val src = File(dest, linkName)
                        // src.exists() follows symlinks, so a planted relative link
                        // could otherwise copy app-private files into the runtime
                        // tree, where the terminal and the Dart layer can read them.
                        val srcCanonical = canonicalOf(src.path) ?: continue
                        if (!srcCanonical.startsWith(destPrefix)) continue
                        if (src.exists()) {
                            src.copyTo(outFile, overwrite = true)
                            if ((e.mode and 0b001001001) != 0) outFile.setExecutable(true)
                        }
                    }
                    else -> {
                        var written = 0L
                        FileOutputStream(outFile).use { out ->
                            val buffer = ByteArray(64 * 1024)
                            while (true) {
                                val read = tar.read(buffer)
                                if (read <= 0) break
                                written += read
                                if (written > MAX_EXTRACTED_BYTES - totalBytes) {
                                    throw IllegalStateException(
                                        "Archive expands beyond the extraction limit"
                                    )
                                }
                                out.write(buffer, 0, read)
                            }
                        }
                        totalBytes += written
                        if ((e.mode and 0b001001001) != 0) outFile.setExecutable(true)
                        outFile.setLastModified(e.modTime.time)
                    }
                }
            }
        }
    }

    private fun stripPrefix(name: String): String? {
        var n = name.removePrefix("./")
        val idx = n.indexOf(TERMUX_PREFIX)
        if (idx >= 0) {
            n = n.substring(idx + TERMUX_PREFIX.length)
            if (n.isEmpty()) return null
            return n
        }
        if (n.startsWith("usr/")) return n.removePrefix("usr/")
        if (n.startsWith("data/")) return null
        return n
    }

    /**
     * Turns a kernel/SELinux refusal into something actionable.
     *
     * The overwhelmingly common cause is a shared-volume path, because
     * `/storage/emulated` is mounted `noexec`, and that mount is not something the
     * app can change.
     *
     * Returns null when the failure is not a permission refusal, so ordinary
     * failures keep their original error.
     */
    private fun explainExecDenial(e: Exception, argv: List<String>): String? {
        val text = generateSequence(e as Throwable) { it.cause }
            .mapNotNull { it.message }
            .joinToString(" | ")
        val denied = text.contains("Permission denied") ||
            text.contains("EACCES") ||
            text.contains("exec_no_trans")
        if (!denied) return null

        val onSharedVolume = argv.firstOrNull()
            ?.contains("/storage/emulated") == true

        return buildString {
            append("Android refused to execute this program.")
            if (onSharedVolume) {
                append(
                    " The program lives on shared storage, which Android mounts" +
                        " noexec. Compiled output has to be built into app storage.",
                )
            } else {
                append(
                    " It was started through the system linker, which cannot load" +
                        " this kind of binary (a static or non-PIE executable)." +
                        " If the language needs one, report it with the runtime name.",
                )
            }
        }
    }

    private fun launchArgv(argv: List<String>): List<String> {
        val target = argv.firstOrNull() ?: return argv
        if (!target.startsWith("/")) return argv
        val file = File(target)
        if (!file.isFile) return argv
        if (isSystemPath(target)) return argv

        // Compiler drivers that fork sub-tools (like clang / clang++) must retain
        // their executable path as argv[0] rather than the dynamic linker path,
        // otherwise internal invocations (-cc1) fail when passed to linker64.
        if (file.name.startsWith("clang")) {
            return argv
        }

        if (isElf(file)) return listOf(systemLinker(), target) + argv.drop(1)
        // Not an ELF, so a `#!` script: exec'ing it needs the kernel to run the
        // script itself, which is the operation the policy forbids. Hand it to the
        // system shell instead.
        return listOf("/system/bin/sh", target) + argv.drop(1)
    }

    /**
     * True for anything shipped in the OS image rather than unpacked by the app.
     *
     * Comparing against the app's own `dataDir` looks more obvious but is not
     * reliable: `/data/data/<pkg>` and `/data/user/0/<pkg>` are the same directory
     * reached by different routes, and which spelling a path arrives in depends on
     * the caller, so a prefix test silently fails and falls back to a direct exec
     * that the platform then denies. The command being run has already been
     * checked against the sandbox by [validateCommandPath] before this is reached,
     * so the only question here is "did we unpack this file ourselves".
     */
    private fun isSystemPath(target: String): Boolean =
        SYSTEM_PREFIXES.any { target == it || target.startsWith("$it/") }

    /**
     * The dynamic linker for the device's own ABI.
     *
     * `linker64` exists only on 64-bit devices; 32-bit devices ship `linker`.
     */
    private fun systemLinker(): String =
        if (Build.SUPPORTED_64_BIT_ABIS.isNotEmpty()) "/system/bin/linker64" else "/system/bin/linker"

    private fun isElf(file: File): Boolean = try {
        file.inputStream().use { input ->
            val magic = ByteArray(4)
            input.read(magic) == 4 &&
                magic[0] == 0x7F.toByte() &&
                magic[1] == 'E'.code.toByte() &&
                magic[2] == 'L'.code.toByte() &&
                magic[3] == 'F'.code.toByte()
        }
    } catch (_: Exception) {
        false
    }

    private fun exec(
        argv: List<String>,
        cwd: String,
        env: Map<String, String>,
        timeoutMs: Long,
        runId: String? = null
    ): Map<String, Any> {
        // Last gate before the bytes run: the program must still match what
        // was verified at download and extraction time. Runs on this executor
        // thread immediately before start(), so the window between the check
        // and the exec is as small as this design allows.
        verifyRuntimeBinary(argv)

        val workDir = File(cwd)
        if (!workDir.exists()) workDir.mkdirs()

        val processBuilder = ProcessBuilder(launchArgv(argv)).directory(workDir)
        val environment = processBuilder.environment()
        val pathEntries = buildPathEntries()
        val libDirs = mutableListOf<String>()
        runtimesRoot().listFiles()?.forEach { runtime ->
            File(runtime, "lib").takeIf { it.exists() }?.let { libDirs.add(it.absolutePath) }
        }
        if (libDirs.isNotEmpty()) {
            val existing = environment["LD_LIBRARY_PATH"]
            environment["LD_LIBRARY_PATH"] =
                (libDirs + listOfNotNull(existing)).joinToString(":")
        }
        // Caller-supplied env goes in first, then the mandatory entries below,
        // so nothing a run config supplies can override the validated PATH.
        environment.putAll(env)
        environment["PATH"] = pathEntries.joinToString(":")
        // HOME and TMPDIR point at app-private scratch rather than the workspace,
        // so credentials and intermediate files in HOME do not land in a
        // user-visible directory.
        val scratch = File(appContext.cacheDir, "run-scratch")
        scratch.mkdirs()
        environment["TMPDIR"] = scratch.absolutePath
        environment["HOME"] = scratch.absolutePath
        environment["PYTHONHOME"] = File(runtimesRoot(), "cpython").absolutePath.takeIf {
            File(it).exists()
        } ?: environment["PYTHONHOME"] ?: ""
        if (environment["PYTHONHOME"]!!.isEmpty()) environment.remove("PYTHONHOME")
        environment["PYTHONUNBUFFERED"] = "1"

        val process = processBuilder.start()
        if (runId != null) {
            activeProcesses[runId] = process
            // Dart subscribes to the run channel immediately before invoking
            // exec, but the native onListen lands on the main thread a moment
            // later. Waiting briefly for it avoids losing the first lines of a
            // program that exits instantly.
            val deadline = System.currentTimeMillis() + 200
            while (eventSink == null && System.currentTimeMillis() < deadline) {
                Thread.sleep(10)
            }
        }

        try {
            val stdoutFuture = ioExecutor.submit<Captured> {
                capture(process.inputStream, runId, "stdout")
            }
            val stderrFuture = ioExecutor.submit<Captured> {
                capture(process.errorStream, runId, "stderr")
            }

            // A zero timeout means "run until it exits or is stopped". The UI now
            // has a working Stop button, so a server or REPL is no longer killed
            // at 30 seconds with no way to keep it alive.
            val finished = if (timeoutMs <= 0L) {
                process.waitFor()
                true
            } else {
                process.waitFor(timeoutMs, TimeUnit.MILLISECONDS)
            }
            if (!finished) {
                process.destroyForcibly()
                // Cancel the readers too. They stay blocked on the pipe otherwise and
                // leak two threads per timed-out run.
                stdoutFuture.cancel(true)
                stderrFuture.cancel(true)
                return mapOf(
                    "success" to false,
                    "stdout" to "",
                    "stderr" to "Execution timed out after ${timeoutMs}ms",
                    "exitCode" to -1,
                    "truncated" to false
                )
            }

            val out = try { stdoutFuture.get(5, TimeUnit.SECONDS) } catch (_: Exception) {
                Captured("", false)
            }
            val err = try { stderrFuture.get(5, TimeUnit.SECONDS) } catch (_: Exception) {
                Captured("", false)
            }
            val code = process.exitValue()
            return mapOf(
                "success" to (code == 0),
                "stdout" to out.text,
                "stderr" to err.text,
                "exitCode" to code,
                "truncated" to (out.truncated || err.truncated)
            )
        } finally {
            try {
                process.outputStream.close()
            } catch (_: Exception) {}
            if (runId != null) activeProcesses.remove(runId)
        }
    }

    private class Captured(val text: String, val truncated: Boolean)

    /**
     * Reads at most [MAX_CAPTURED_OUTPUT_BYTES] from a process stream.
     *
     * The previous implementation called `readText()` with no bound, so `yes` or
     * `find /` exhausted the heap. `OutOfMemoryError` is an `Error`, not an
     * `Exception`, so the surrounding `catch (e: Exception)` did not catch it: the
     * MethodChannel result was never replied to and the Dart side only unblocked
     * on its own timeout.
     */
    private fun capture(stream: InputStream, runId: String?, kind: String): Captured {
        val out = StringBuilder()
        val reader = java.io.InputStreamReader(stream, Charsets.UTF_8)
        val buffer = CharArray(8 * 1024)
        var total = 0
        var truncated = false
        reader.use { input ->
            while (true) {
                val read = try {
                    input.read(buffer)
                } catch (e: Exception) {
                    break
                }
                if (read <= 0) break
                val remaining = MAX_CAPTURED_OUTPUT_BYTES - total
                if (remaining <= 0) {
                    truncated = true
                    break
                }
                val take = minOf(read, remaining)
                val chunk = String(buffer, 0, take)
                out.append(chunk)
                total += take
                if (runId != null) emit(runId, kind, chunk)
                if (take < read) {
                    truncated = true
                    break
                }
            }
        }
        return Captured(out.toString(), truncated)
    }
}