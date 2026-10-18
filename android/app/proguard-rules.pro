# B Code — R8 / ProGuard rules
#
# Scope note: the Flutter Gradle plugin injects the engine's own consumer rules
# automatically. This file must only cover the app's own code plus the third-party
# libraries that genuinely require it.
#
# Do NOT add broad keeps such as `-keep class android.** { *; }` or
# `-keep class org.chromium.** { *; }`. Those retain the entire framework and
# defeat shrinking, which is what makes a minified build large and slow to verify.

# ---------------------------------------------------------------------------
# App code
# ---------------------------------------------------------------------------
# MainActivity is referenced from the manifest, so R8 keeps it. The plugin classes
# are only reached reflectively by the Flutter engine's generated registrant.
-keep class com.bcode.editor.** { *; }

# Keep annotations + generic signatures. Required by anything that reflects on
# types (commons-compress codecs, JCE provider lookup, Flutter plugin registration).
-keepattributes Signature,InnerClasses,EnclosingMethod,*Annotation*,RuntimeVisibleAnnotations,AnnotationDefault

# ---------------------------------------------------------------------------
# Archive extraction (runtime .deb / .tar.xz unpacking)
# ---------------------------------------------------------------------------
-keep class org.apache.commons.compress.** { *; }
-keep class org.tukaani.xz.** { *; }
-dontwarn org.apache.commons.compress.**
-dontwarn org.tukaani.xz.**
# commons-compress resolves optional codecs through the ServiceLoader.
-keep class * implements org.apache.commons.compress.Compressor { *; }
-keep class * implements org.apache.commons.compress.ArchiveCompressor { *; }
-keep class * implements org.apache.commons.compress.Decompressor { *; }
-keep class * implements org.apache.commons.compress.ArchiveDecompressor { *; }

# ---------------------------------------------------------------------------
# zstd-jni: loads its native library and JNI-registers entry points.
# ---------------------------------------------------------------------------
-keep class com.github.luben.zstd.** { *; }
-dontwarn com.github.luben.zstd.**
-keepclasseswithmembernames class * {
    native <methods>;
}

# ---------------------------------------------------------------------------
# Secrets storage
# ---------------------------------------------------------------------------
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keepclassmembers class * extends javax.crypto.SecretKey { *; }
-keepclassmembers class * extends java.security.Key { *; }

# ---------------------------------------------------------------------------
# RASP (flutter_secure_app): native method resolution by name.
# ---------------------------------------------------------------------------
-keep class com.flutter_secure_app.** { *; }
-dontwarn com.flutter_secure_app.**

# ---------------------------------------------------------------------------
# TLS
# ---------------------------------------------------------------------------
-keep class io.github.http_certificate_pinning.** { *; }
-dontwarn io.github.http_certificate_pinning.**

# ---------------------------------------------------------------------------
# Device / app info plugins
# ---------------------------------------------------------------------------
-keep class dev.fluttercommunity.plus.packageinfo.** { *; }
-keep class dev.fluttercommunity.plus.deviceinfo.** { *; }

# ---------------------------------------------------------------------------
# Log reduction
# ---------------------------------------------------------------------------
# Keep warnings and errors: the exec sandbox and the runtime downloader log
# refusals at warning level, and silently dropping those would hide security
# decisions from anyone debugging on-device.
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
}

# ---------------------------------------------------------------------------
# Symbolication
# ---------------------------------------------------------------------------
# Keep line numbers so release crash reports are actionable; hide the original
# source file name.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
