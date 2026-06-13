import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningProperties = Properties()
val releaseSigningPropertiesFile = File(project.rootDir, "release-signing.properties.local")
if (releaseSigningPropertiesFile.exists()) {
    releaseSigningPropertiesFile.inputStream().use { releaseSigningProperties.load(it) }
}

fun releaseProperty(name: String): String? =
    (findProperty(name) as String? ?: System.getenv(name) ?: releaseSigningProperties.getProperty(name))
        ?.trim()
        ?.takeIf { it.isNotEmpty() }

val releaseStoreFilePath = releaseProperty("ONEWALLET_RELEASE_STORE_FILE")
val releaseStorePassword = releaseProperty("ONEWALLET_RELEASE_STORE_PASSWORD")
val releaseKeyAlias = releaseProperty("ONEWALLET_RELEASE_KEY_ALIAS")
val releaseKeyPassword = releaseProperty("ONEWALLET_RELEASE_KEY_PASSWORD")
val releaseSigningReady =
    releaseStoreFilePath != null &&
        releaseStorePassword != null &&
        releaseKeyAlias != null &&
        releaseKeyPassword != null

fun resolveReleaseFile(path: String): File {
    val candidate = File(path)
    return if (candidate.isAbsolute) candidate else File(project.rootDir, path)
}

android {
    namespace = "com.joelpjoji.one.wallet"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    signingConfigs {
        if (releaseSigningReady) {
            create("oneWalletRelease") {
                storeFile = resolveReleaseFile(releaseStoreFilePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.joelpjoji.one.wallet"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            signingConfig = signingConfigs.getByName(
                if (releaseSigningReady) "oneWalletRelease" else "debug",
            )
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
