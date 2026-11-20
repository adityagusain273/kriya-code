package com.kriya.editor

import android.content.Context
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

/**
 * Reports which certificate the installed APK is signed with.
 *
 * A repackaged APK has to be re-signed with a different key, so its signing
 * certificate no longer matches the one the release was built with. Only the
 * digest of the certificate leaves the platform; the certificate bytes
 * themselves never do.
 */
object IntegrityPlugin {
    private const val CHANNEL = "bcode.integrity"

    fun register(messenger: BinaryMessenger, context: Context) {
        val appContext = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "signingCertificates" -> {
                    try {
                        result.success(signingCertificates(appContext))
                    } catch (e: Exception) {
                        result.error("INTEGRITY_UNAVAILABLE", e.message, null)
                    }
                }
                "deviceId" -> {
                    try {
                        val androidId = Settings.Secure.getString(appContext.contentResolver, Settings.Secure.ANDROID_ID) ?: "unknown"
                        val brand = Build.BRAND ?: ""
                        val model = Build.MODEL ?: ""
                        val hash = sha256Hex("$androidId:$brand:$model".toByteArray())
                        val shortId = "KRIYA-" + hash.substring(0, 8).uppercase()
                        result.success(shortId)
                    } catch (e: Exception) {
                        result.error("DEVICE_ID_UNAVAILABLE", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun signingCertificates(context: Context): Map<String, Any> {
        val signatures = signatures(context)
        return mapOf(
            "signers" to signatures.map { sha256Hex(it.toByteArray()) },
            "signerCount" to signatures.size,
        )
    }

    private fun signatures(context: Context): List<Signature> {
        val pm = context.packageManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val info = pm.getPackageInfo(
                context.packageName,
                PackageManager.GET_SIGNING_CERTIFICATES,
            )
            val signingInfo = info.signingInfo ?: return emptyList()
            if (signingInfo.hasMultipleSigners()) {
                return signingInfo.apkContentsSigners.toList()
            }
            // The history holds the current certificate and, for a rotated key,
            // the ones it replaced.
            val history = try {
                signingInfo.signingCertificateHistory
            } catch (_: Exception) {
                null
            }
            return history?.toList() ?: signingInfo.apkContentsSigners.toList()
        }
        @Suppress("DEPRECATION")
        return pm.getPackageInfo(
            context.packageName,
            PackageManager.GET_SIGNATURES,
        ).signatures?.toList() ?: emptyList()
    }

    /** Uppercase hex, matching the format `package_info_plus` reports. */
    private fun sha256Hex(bytes: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
        return digest.joinToString("") { String.format("%02X", it.toInt() and 0xFF) }
    }
}
