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
    private const val MAX_EXTRACTED_BYTES = 4L * 1024 * 1024 * 1024
    private const val MAX_ARCHIVE_ENTRIES = 200000
    private const val MAX_CAPTURED_OUTPUT_BYTES = 8 * 1024 * 1024
    private val RUNTIME_ID_PATTERN = Regex("[a-z0-9][a-z0-9._-]{0,31}")

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

    // Sandbox: allowed root directories that commands can access
    private val allowedRoots = ConcurrentHashMap<String, Boolean>()

    private fun runOnMain(block: () -> Unit) {
        mainHandler.post(block)
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
                            val relativeTarget = dest.toPath()
                                .relativize(File(dest, linkName).toPath())
                                .toString()
                            Os.symlink(relativeTarget, outFile.path)
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
        timeoutMs: Long
    ): Map<String, Any> {
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

        val process = processBuilder.start()

        val stdoutFuture = ioExecutor.submit<Captured> {
            capture(process.inputStream)
        }
        val stderrFuture = ioExecutor.submit<Captured> {
            capture(process.errorStream)
        }

        val finished = process.waitFor(timeoutMs, TimeUnit.MILLISECONDS)
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
    private fun capture(stream: InputStream): Captured {
        val out = java.io.ByteArrayOutputStream()
        val buffer = ByteArray(16 * 1024)
        var total = 0
        var truncated = false
        stream.use { input ->
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
                if (read > remaining) {
                    out.write(buffer, 0, remaining)
                    total += remaining
                    truncated = true
                    break
                }
                out.write(buffer, 0, read)
                total += read
            }
        }
        return Captured(out.toString(Charsets.UTF_8.name()), truncated)
    }
}