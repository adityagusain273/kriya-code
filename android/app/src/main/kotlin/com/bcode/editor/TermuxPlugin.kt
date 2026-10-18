package com.bcode.editor

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import android.os.Handler
import android.os.Looper
import java.util.concurrent.Executors

object TermuxPlugin {
    private const val CHANNEL = "bcode.termux"
    private const val TERMUX_PACKAGE = "com.termux"
    private const val RUN_COMMAND_ACTION = "com.termux.RUN_COMMAND"
    private const val RUN_COMMAND_SERVICE = "com.termux.app.RunCommandService"
    private const val RESULT_ACTION = "com.bcode.editor.TERMUX_RESULT"
    private val executor = Executors.newSingleThreadExecutor()
    private lateinit var appContext: Context
    private var resultReceiver: BroadcastReceiver? = null
    private var pendingResult: MethodChannel.Result? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private fun runOnMain(block: () -> Unit) {
        mainHandler.post(block)
    }

    fun register(messenger: BinaryMessenger, context: Context) {
        appContext = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isInstalled" -> {
                    result.success(isTermuxInstalled())
                }
                "isAllowed" -> {
                    result.success(isTermuxAllowed())
                }
                "runCommand" -> {
                    val command = call.argument<String>("command") ?: ""
                    val args = call.argument<List<String>>("args") ?: emptyList()
                    val stdin = call.argument<String>("stdin")
                    val workDir = call.argument<String>("workDir")
                    val useResult = call.argument<Boolean>("useResult") ?: false
                    runTermuxCommand(command, args, stdin, workDir, useResult, result)
                }
                "runScript" -> {
                    val script = call.argument<String>("script") ?: ""
                    val workDir = call.argument<String>("workDir")
                    val useResult = call.argument<Boolean>("useResult") ?: false
                    runTermuxScript(script, workDir, useResult, result)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isTermuxInstalled(): Boolean {
        return try {
            appContext.packageManager.getPackageInfo(TERMUX_PACKAGE, 0)
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }

    private fun isTermuxAllowed(): Boolean {
        if (!isTermuxInstalled()) return false
        return try {
            appContext.checkSelfPermission("com.termux.permission.RUN_COMMAND") == PackageManager.PERMISSION_GRANTED
        } catch (_: Exception) {
            false
        }
    }

    private fun runTermuxCommand(
        command: String,
        args: List<String>,
        stdin: String?,
        workDir: String?,
        useResult: Boolean,
        result: MethodChannel.Result
    ) {
        if (!isTermuxInstalled()) {
            result.error("TERMUX_NOT_INSTALLED", "Termux is not installed on this device", null)
            return
        }

        executor.submit {
            try {
                val intent = createRunIntent(command, args.toTypedArray(), stdin, workDir)

                if (useResult) {
                    val requestId = System.currentTimeMillis().toInt()
                    val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
                    } else {
                        PendingIntent.FLAG_UPDATE_CURRENT
                    }
                    val resultIntent = Intent(RESULT_ACTION).apply {
                        putExtra("request_id", requestId)
                        setPackage(appContext.packageName)
                    }
                    val pendingIntent = PendingIntent.getBroadcast(
                        appContext, requestId, resultIntent, flags
                    )
                    intent.putExtra("com.termux.RUN_COMMAND_PENDING_INTENT", pendingIntent)

                    pendingResult = result
                    registerResultReceiver()
                }

                appContext.startService(intent)

                if (!useResult) {
                    runOnMain {
                        result.success(mapOf(
                            "success" to true,
                            "stdout" to "",
                            "stderr" to "",
                            "exitCode" to 0
                        ))
                    }
                }
            } catch (e: Exception) {
                runOnMain { result.error("TERMUX_ERROR", e.message, null) }
            }
        }
    }

    private fun runTermuxScript(
        script: String,
        workDir: String?,
        useResult: Boolean,
        result: MethodChannel.Result
    ) {
        runTermuxCommand(
            command = "/data/data/com.termux/files/usr/bin/bash",
            args = listOf("-c", script),
            stdin = null,
            workDir = workDir,
            useResult = useResult,
            result = result
        )
    }

    private fun createRunIntent(
        command: String,
        args: Array<String>?,
        stdin: String?,
        workDir: String?
    ): Intent {
        return Intent().apply {
            setClassName(TERMUX_PACKAGE, RUN_COMMAND_SERVICE)
            action = RUN_COMMAND_ACTION
            putExtra("com.termux.RUN_COMMAND_PATH", command)
            if (args != null && args.isNotEmpty()) {
                putExtra("com.termux.RUN_COMMAND_ARGUMENTS", args)
            }
            if (stdin != null) {
                putExtra("com.termux.RUN_COMMAND_STDIN", stdin)
            }
            if (workDir != null) {
                putExtra("com.termux.RUN_COMMAND_WORKDIR", workDir)
            }
            putExtra("com.termux.RUN_COMMAND_BACKGROUND", true)
        }
    }

    private fun registerResultReceiver() {
        if (resultReceiver != null) return
        resultReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val requestId = intent.getIntExtra("request_id", -1)
                val exitCode = intent.getIntExtra("exit_code", -1)
                val stdout = intent.getStringExtra("stdout") ?: ""
                val stderr = intent.getStringExtra("stderr") ?: ""

                runOnMain {
                    pendingResult?.success(mapOf(
                        "success" to (exitCode == 0),
                        "stdout" to stdout,
                        "stderr" to stderr,
                        "exitCode" to exitCode
                    ))
                    pendingResult = null
                }
            }
        }
        val filter = IntentFilter(RESULT_ACTION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            appContext.registerReceiver(resultReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            appContext.registerReceiver(resultReceiver, filter)
        }
    }

    fun unregister() {
        resultReceiver?.let {
            try { appContext.unregisterReceiver(it) } catch (_: Exception) {}
        }
        resultReceiver = null
    }
}
