package com.bcode.editor

import android.content.Context
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.system.Os
import io.flutter.plugin.common.BinaryMessenger
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
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

object ExecPlugin {
    private const val CHANNEL = "bcode.exec"
    private const val TERMUX_PREFIX = "data/data/com.termux/files/usr/"
    private const val MAX_ARGV_SIZE = 256
    private const val MAX_ENV_SIZE = 65536

    private val BLOCKED_ENV_KEYS = setOf(
        "LD_PRELOAD", "LD_LIBRARY_PATH", "LD_AUDIT",
        "MALLOC_OPTIONS", "MALLOC_CONF",
        "BASH_ENV", "ENV", "CDPATH", "GLOBIGNORE", "HISTFILE",
    )

    private val executor = Executors.newSingleThreadExecutor()
    private val ioExecutor = Executors.newCachedThreadPool()
    private lateinit var appContext: Context
    private val mainHandler = Handler(Looper.getMainLooper())

    // Sandbox: allowed root directories that commands can access
    private val allowedRoots = ConcurrentHashMap<String, Boolean>()

    private fun runOnMain(block: () -> Unit) {
        mainHandler.post(block)
    }

    private fun initializeAllowedRoots() {
        allowedRoots.clear()
        // App's internal files directory (always allowed)
        allowedRoots[appContext.filesDir.canonicalPath] = true
        // App's cache directory
        allowedRoots[appContext.cacheDir.canonicalPath] = true
        // System binaries
        allowedRoots["/system/bin"] = true
        allowedRoots["/system/xbin"] = true
        // Runtimes directory
        allowedRoots[runtimesRoot().canonicalPath] = true
        // Termux prefix if available
        val termuxPrefix = "/data/data/com.termux/files/usr"
        if (File(termuxPrefix).exists()) {
            allowedRoots[termuxPrefix] = true
        }
    }

    private fun isWithinSandbox(path: String): Boolean {
        val canonical = try {
            File(path).canonicalPath
        } catch (e: Exception) {
            return false
        }
        return allowedRoots.keys.any { canonical.startsWith(it) }
    }

    private fun validateCommandPath(argv: List<String>): String? {
        if (argv.isEmpty()) return "argv is empty"
        val command = argv[0]
        val commandFile = File(command)

        // If absolute path, validate directly
        if (commandFile.isAbsolute) {
            val canonical = try {
                commandFile.canonicalPath
            } catch (e: Exception) {
                return "Cannot resolve command path"
            }
            if (!allowedRoots.keys.any { canonical.startsWith(it) }) {
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
                val canonical = try {
                    candidate.canonicalPath
                } catch (e: Exception) {
                    continue
                }
                if (allowedRoots.keys.any { canonical.startsWith(it) }) return null
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

        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasRuntime" -> {
                    val runtimeId = call.argument<String>("runtimeId") ?: ""
                    result.success(runtimeDir(runtimeId).exists())
                }
                "runtimesDir" -> {
                    result.success(runtimesRoot().absolutePath)
                }
                "extractRuntime" -> {
                    val runtimeId = call.argument<String>("runtimeId") ?: ""
                    executor.submit {
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
                            val output = exec(argv, cwd, safeEnv, timeoutMs)
                            runOnMain { result.success(output) }
                        } catch (e: Exception) {
                            runOnMain { result.error("EXEC_FAILED", e.message, null) }
                        }
                    }
                }
                "addSandboxPath" -> {
                    val path = call.argument<String>("path") ?: ""
                    if (path.isNotBlank()) {
                        try {
                            allowedRoots[File(path).canonicalPath] = true
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("EINVAL", "Invalid path: $path", null)
                        }
                    } else {
                        result.error("EINVAL", "Path is required", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun runtimesRoot(): File = File(appContext.filesDir, "runtimes")

    private fun runtimeDir(runtimeId: String): File = File(runtimesRoot(), runtimeId)

    private fun extractRuntime(runtimeId: String) {
        val dest = runtimeDir(runtimeId)
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
    }

    private fun extractDeb(deb: File, dest: File) {
        ArArchiveInputStream(FileInputStream(deb)).use { ar ->
            while (true) {
                val entry = ar.nextEntry ?: break
                val name = entry.name
                if (!name.startsWith("data.tar")) continue
                val raw: InputStream = when {
                    name.endsWith(".gz") -> GzipCompressorInputStream(ar)
                    name.endsWith(".xz") -> {
                        try {
                            XZCompressorInputStream(ar)
                        } catch (e: NoClassDefFoundError) {
                            throw UnsupportedOperationException(
                                "xz decompression not available; install xz library", e)
                        }
                    }
                    name.endsWith(".zst") -> {
                        try {
                            ZstdInputStream(ar)
                        } catch (e: NoClassDefFoundError) {
                            throw UnsupportedOperationException(
                                "zstd decompression not available; install zstd-jni library", e)
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
        TarArchiveInputStream(input).use { tar ->
            while (true) {
                val e = tar.nextTarEntry ?: break
                val rel = stripPrefix(e.name) ?: continue
                val outFile = File(dest, rel)
                if (!outFile.canonicalPath.startsWith(destCanonical)) continue
                if (e.isDirectory) {
                    outFile.mkdirs()
                    continue
                }
                outFile.parentFile?.mkdirs()
                when {
                    e.isSymbolicLink -> {
                        if (outFile.exists()) outFile.delete()
                        try {
                            Os.symlink(e.linkName, outFile.path)
                        } catch (_: Exception) {
                        }
                    }
                    e.isLink -> {
                        val linkName = stripPrefix(e.linkName) ?: continue
                        val src = File(dest, linkName)
                        if (src.exists()) {
                            src.copyTo(outFile, overwrite = true)
                            if ((e.mode and 0b001001001) != 0) outFile.setExecutable(true)
                        }
                    }
                    else -> {
                        FileOutputStream(outFile).use { tar.copyTo(it) }
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

    private fun exec(
        argv: List<String>,
        cwd: String,
        env: Map<String, String>,
        timeoutMs: Long
    ): Map<String, Any> {
        val workDir = File(cwd)
        if (!workDir.exists()) workDir.mkdirs()

        val processBuilder = ProcessBuilder(argv).directory(workDir)
        val environment = processBuilder.environment()
        val pathEntries = buildPathEntries()
        val libDirs = mutableListOf<String>()
        runtimesRoot().listFiles()?.forEach { runtime ->
            File(runtime, "lib").takeIf { it.exists() }?.let { libDirs.add(it.absolutePath) }
        }
        environment["PATH"] = pathEntries.joinToString(":")
        if (libDirs.isNotEmpty()) {
            val existing = environment["LD_LIBRARY_PATH"]
            environment["LD_LIBRARY_PATH"] =
                (libDirs + listOfNotNull(existing)).joinToString(":")
        }
        environment.putAll(env)
        environment["TMPDIR"] = workDir.absolutePath
        environment["HOME"] = workDir.absolutePath
        environment["PYTHONHOME"] = File(runtimesRoot(), "cpython").absolutePath.takeIf {
            File(it).exists()
        } ?: environment["PYTHONHOME"] ?: ""
        if (environment["PYTHONHOME"]!!.isEmpty()) environment.remove("PYTHONHOME")

        val process = processBuilder.start()

        val stdoutFuture = ioExecutor.submit<String> {
            process.inputStream.bufferedReader().use { it.readText() }
        }
        val stderrFuture = ioExecutor.submit<String> {
            process.errorStream.bufferedReader().use { it.readText() }
        }

        val finished = process.waitFor(timeoutMs, TimeUnit.MILLISECONDS)
        if (!finished) {
            process.destroyForcibly()
            return mapOf(
                "success" to false,
                "stdout" to "",
                "stderr" to "Execution timed out after ${timeoutMs}ms",
                "exitCode" to -1
            )
        }

        val stdout = try { stdoutFuture.get(5, TimeUnit.SECONDS) } catch (_: Exception) { "" }
        val stderr = try { stderrFuture.get(5, TimeUnit.SECONDS) } catch (_: Exception) { "" }
        val code = process.exitValue()
        return mapOf(
            "success" to (code == 0),
            "stdout" to stdout,
            "stderr" to stderr,
            "exitCode" to code
        )
    }
}