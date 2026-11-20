package com.kriya.editor

import android.os.StatFs
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Free space on a filesystem, for the preflight that guards runtime downloads.
 *
 * Dart's `dart:io` has no statvfs, so without this the app could only guess.
 * A runtime that unpacks onto a full volume leaves the app with a half-written
 * runtime and no space to write its own databases, so the check is worth a
 * platform call.
 */
object StoragePlugin {
    private const val CHANNEL = "bcode.storage"

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "freeBytes" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("EINVAL", "path is required", null)
                    } else {
                        // An unreadable or vanished path is "unknown", not zero:
                        // the caller must not read a failure as a full disk.
                        result.success(tryFreeBytes(path))
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun tryFreeBytes(path: String): Long? =
        try {
            StatFs(path).availableBytes
        } catch (_: Exception) {
            null
        }
}