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
import androidx.core.content.ContextCompat
import java.security.SecureRandom
import java.util.concurrent.Executors

object TermuxPlugin {
    private const val CHANNEL = "bcode.termux"
    private const val TERMUX_PACKAGE = "com.termux"
    private const val RUN_COMMAND_ACTION = "com.termux.RUN_COMMAND"
    private const val RUN_COMMAND_SERVICE = "com.termux.app.RunCommandService"
    private const val RESULT_ACTION = "com.bcode.editor.TERMUX_RESULT"
    private val executor = Executors.newSingleThreadExecutor()
    private lateinit var appContext: Context
    private var activityContext: android.app.Activity? = null
    private var resultReceiver: BroadcastReceiver? = null

    /// One slot per in-flight command keyed by request_id. A single slot was
    /// overwritten by every concurrent runCommand, and the receiver ignored
    /// request_id, so a stale broadcast could deliver one command's output to
    /// another. Termux may also deliver stdout/stderr bundles of arbitrary
    /// size, which are capped before they enter the Dart channel.
    ///
    /// request_id is drawn from SecureRandom rather than a millisecond
    /// timestamp: the old value was sweepable by any app on the device, which
    /// could forge a result for a command still in flight. The broadcast
    /// action also carries a random per-registration token, so a forged
    /// broadcast needs both the token and a live id to land.
    private val pendingResults = java.util.concurrent.ConcurrentHashMap<Int, MethodChannel.Result>()
    private const val MAX_RESULT_BYTES = 1_048_576
    private val secureRandom = SecureRandom()

    /// The action the result receiver is currently registered for. Regenerated
    /// every time the receiver is (re)registered so a token that was ever live
    /// cannot be replayed against a later session of the receiver.
    @Volatile private var resultAction: String? = null

    private fun currentResultAction(): String {
        resultAction?.let { return it }
        val token = ByteArray(16).joinToString("") { "%02x".format(it) }
        val action = "$RESULT_ACTION.$token"
        resultAction = action
        return action
    }

    private fun bounded(text: String?): String {
        if (text == null) return ""
        return if (text.length > MAX_RESULT_BYTES) text.substring(0, MAX_RESULT_BYTES) else text
    }
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile private var permissionLatch = java.util.concurrent.CountDownLatch(0)
    @Volatile private var permissionGrantedForUi: Boolean = false

    private fun runOnMain(block: () -> Unit) {
        mainHandler.post(block)
    }

    /// Tries to locate the launching activity so a dangerous runtime permission
    /// can only be requested when we actually have an activity foreground.
    fun attachActivity(activity: android.app.Activity) {
        activityContext = activity
    }

    fun onRequestPermissionsResult(grantResults: IntArray) {
        permissionGrantedForUi = grantResults.isNotEmpty() &&
            grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED
        val latch = permissionLatch
        if (latch != null) {
            try { latch.countDown() } catch (_: Exception) {}
        }
    }

    /// Asks the user to grant the RUN_COMMAND permission, blocking the calling
    /// thread until the dialog is answered (or a minute elapses). The result of
    /// the request is read off `permissionGrantedForUi` afterwards.
    fun requestTryGrantedPermission(): Boolean {
        val activity = activityContext ?: return isTermuxAllowed()
        if (isTermuxAllowed()) return true
        permissionLatch = java.util.concurrent.CountDownLatch(1)
        permissionGrantedForUi = false
        mainHandler.post {
            try {
                activity.requestPermissions(
                    arrayOf("com.termux.permission.RUN_COMMAND"),
                    9913
                )
            } catch (e: Exception) {
                permissionGrantedForUi = false
                try { permissionLatch.countDown() } catch (_: Exception) {}
            }
        }
        val ok = try {
            permissionLatch.await(60, java.util.concurrent.TimeUnit.SECONDS)
        } catch (_: InterruptedException) {
            false
        }
        return ok && permissionGrantedForUi
    }

    fun register(messenger: BinaryMessenger, context: Context) {
        appContext = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isInstalled" -> {
                    result.success(isTermuxInstalled())
                }
                "openTermux" -> {
                    val launchIntent = appContext.packageManager.getLaunchIntentForPackage(TERMUX_PACKAGE)
                    if (launchIntent != null) {
                        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        appContext.startActivity(launchIntent)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "isAllowed" -> {
                    if (isTermuxAllowed()) {
                        result.success(true)
                    } else {
                        // The grant wait must NOT run on the main thread, otherwise
                        // the permission dialog it tries to show can never render:
                        // the blocking await holds the main thread hostage.
                        executor.submit {
                            result.success(requestTryGrantedPermission())
                        }
                    }
                }
                "runCommand" -> {
                    val command = call.argument<String>("command") ?: ""
                    val args = call.argument<List<String>>("args") ?: emptyList()
                    val stdin = call.argument<String>("stdin")
                    val workDir = call.argument<String>("workDir")
                    val useResult = call.argument<Boolean>("useResult") ?: false
                    runTermuxCommand(command, args, stdin, workDir, useResult, result)
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
            var requestId: Int? = null
            try {
                val intent = createRunIntent(command, args.toTypedArray(), stdin, workDir)

                if (useResult) {
                    // Unpredictable correlation value: a timestamp is sweepable,
                    // a SecureRandom draw is not.
                    requestId = secureRandom.nextInt(Int.MAX_VALUE) + 1
                    val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
                    } else {
                        PendingIntent.FLAG_UPDATE_CURRENT
                    }
                    // The result intent targets this app's package explicitly, so
                    // the broadcast the PendingIntent fires can only land here.
                    // Termux needs the PendingIntent mutable to fill in the
                    // stdout/stderr/exit_code extras; fill-in cannot replace the
                    // action, package or request_id already set below.
                    val resultIntent = Intent(currentResultAction()).apply {
                        putExtra("request_id", requestId)
                        setPackage(appContext.packageName)
                    }
                    val pendingIntent = PendingIntent.getBroadcast(
                        appContext, requestId, resultIntent, flags
                    )
                    intent.putExtra("com.termux.RUN_COMMAND_PENDING_INTENT", pendingIntent)

                    pendingResults[requestId] = result
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
                requestId?.let { pendingResults.remove(it) }
                runOnMain { result.error("TERMUX_ERROR", e.message, null) }
            }
        }
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
                val res = pendingResults.remove(requestId) ?: return
                val bundle = intent.getBundleExtra("result") ?: intent.extras
                val exitCode = if (bundle?.containsKey("exitCode") == true) {
                    bundle.getInt("exitCode", -1)
                } else if (bundle?.containsKey("exit_code") == true) {
                    bundle.getInt("exit_code", -1)
                } else {
                    intent.getIntExtra("exitCode", intent.getIntExtra("exit_code", -1))
                }
                val stdout = bounded(bundle?.getString("stdout") ?: intent.getStringExtra("stdout"))
                val rawStderr = bundle?.getString("stderr")
                    ?: bundle?.getString("errmsg")
                    ?: intent.getStringExtra("stderr")
                    ?: intent.getStringExtra("errmsg")
                val stderr = bounded(rawStderr)

                runOnMain {
                    res.success(mapOf(
                        "success" to (exitCode == 0),
                        "stdout" to stdout,
                        "stderr" to stderr,
                        "exitCode" to exitCode
                    ))
                }
                if (pendingResults.isEmpty()) {
                    runOnMain { unregister() }
                }
            }
        }
        // RECEIVER_NOT_EXPORTED on every API level the app supports. The
        // platform only started honouring the flag on API 31 and only requires
        // it on 33+, but ContextCompat forwards it to the framework's flags
        // overload on 26+ and falls back to the legacy overload below that,
        // where the unpredictable action token above is what stands between a
        // forged broadcast and this receiver.
        val filter = IntentFilter(currentResultAction())
        ContextCompat.registerReceiver(
            appContext, resultReceiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED
        )
    }

    fun unregister() {
        resultReceiver?.let {
            try { appContext.unregisterReceiver(it) } catch (_: Exception) {}
        }
        resultReceiver = null
        // Retire the action with the receiver so the next registration is not
        // reachable by broadcasts crafted against the old token.
        resultAction = null
    }
}
