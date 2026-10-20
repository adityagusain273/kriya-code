import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// When true, a release build without a usable key is signed with the debug key.
// Intended only for local sideload testing. Never enable for a distributed build.
val allowDebugKeyForRelease = (project.findProperty("bcode.sideload") as String?)?.toBoolean() ?: false

// targetSdk: 36 by default so every store that pays per download will accept
// the APK (Google Play requires new apps and updates to target a recent API).
//
// Execution still works at a modern targetSdk, but not by exec'ing the runtime
// directly. Android denies `execute` on files an app unpacked into its own
// storage, and `/storage/emulated` is mounted `noexec`, so a direct
// `execve()` of a downloaded interpreter fails with EACCES. Instead every
// app-owned program is started through the system dynamic linker
// (`/system/bin/linker64 <program>`), which the app may execute; the linker
// then maps the program, an operation the policy permits, and LD_LIBRARY_PATH
// still resolves the runtime's own libraries. ExecPlugin implements this.
//
// The escape hatches, for reference:
//   -Pbcode.targetSdk=28 also works, via the legacy `untrusted_app_28` domain.
//   -Pbcode.targetSdk=35 does too; nothing about the mechanism needs 36.
val targetSdkOverride = (project.findProperty("bcode.targetSdk") as String?)?.toIntOrNull()
val resolvedTargetSdk = targetSdkOverride ?: 36

val missingKeystoreEntries = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    .filter { (keystoreProperties[it] as String?).isNullOrBlank() }

val storeFileRef = (keystoreProperties["storeFile"] as String?)
    ?.takeIf { it.isNotBlank() }
    ?.let { file(it) }

val storeFileMissing = storeFileRef != null && !storeFileRef.exists()
val storeFileUnresolved = storeFileRef == null && missingKeystoreEntries.none { it == "storeFile" }

if (!allowDebugKeyForRelease &&
    (missingKeystoreEntries.isNotEmpty() || storeFileMissing || storeFileUnresolved)
) {
    throw GradleException(
        buildString {
            appendLine("Refusing to build a release APK without a usable release signing key.")
            appendLine()
            if (missingKeystoreEntries.isNotEmpty()) {
                appendLine("android/key.properties is missing entries: ${missingKeystoreEntries.joinToString(", ")}")
            }
            if (!keystorePropertiesFile.exists()) {
                appendLine("android/key.properties does not exist.")
            }
            if (storeFileMissing) {
                appendLine("storeFile points at '${storeFileRef!!.path}', which does not exist.")
            }
            if (storeFileUnresolved) {
                appendLine("storeFile is not set to a usable path.")
            }
            appendLine()
            appendLine("Fix it properly:")
            appendLine("  1. keytool -genkey -v -keystore ~/bcode-release.jks -keyalg RSA \\")
            appendLine("       -keysize 4096 -validity 10000 -alias bcode")
            appendLine("  2. cp key.properties.example android/key.properties")
            appendLine("  3. Fill in storeFile / storePassword / keyAlias / keyPassword")
            appendLine("  4. flutter build apk --release")
            appendLine()
            appendLine("For a throwaway local sideload test only, opt in explicitly with:")
            appendLine("  flutter build apk --release -Pbcode.sideload=true")
        }
    )
}

android {
    namespace = "com.bcode.editor"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.bcode.editor"
        minSdk = 24
        targetSdk = resolvedTargetSdk
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    packagingOptions {
        // Exclusions removed to allow x86_64 emulator support
    }

    signingConfigs {
        create("release") {
            val storeFilePath = keystoreProperties["storeFile"] as String?
            if (storeFilePath != null) {
                storeFile = file(storeFilePath)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            val releaseSigning = signingConfigs.getByName("release")
            signingConfig = if (releaseSigning.storeFile != null) {
                releaseSigning
            } else {
                if (!allowDebugKeyForRelease) {
                    throw GradleException("Release signing key unavailable and bcode.sideload is not set.")
                }
                logger.warn(
                    "bcode WARNING: signing the release build with the DEBUG key. " +
                        "This build can be overwritten by anyone and must never be distributed."
                )
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            ndk {
                debugSymbolLevel = "SYMBOL_TABLE"
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("org.apache.commons:commons-compress:1.27.1")
    implementation("org.tukaani:xz:1.10")
    implementation("com.github.luben:zstd-jni:1.5.6-8")
}
