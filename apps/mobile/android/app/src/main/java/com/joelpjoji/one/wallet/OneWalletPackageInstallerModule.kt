package com.joelpjoji.one.wallet

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest

class OneWalletPackageInstallerModule(private val reactContext: ReactApplicationContext) :
  ReactContextBaseJavaModule(reactContext) {
  override fun getName(): String = "OneWalletPackageInstaller"

  @ReactMethod
  fun canRequestPackageInstalls(promise: Promise) {
    try {
      val allowed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        reactContext.packageManager.canRequestPackageInstalls()
      } else {
        true
      }
      promise.resolve(allowed)
    } catch (error: Exception) {
      promise.reject("INSTALL_PERMISSION_CHECK_FAILED", error.message, error)
    }
  }

  @ReactMethod
  fun openInstallSettings(promise: Promise) {
    try {
      val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        Intent(
          Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
          Uri.parse("package:${reactContext.packageName}"),
        )
      } else {
        Intent(Settings.ACTION_SECURITY_SETTINGS)
      }
      startActivity(intent)
      promise.resolve(null)
    } catch (error: ActivityNotFoundException) {
      promise.reject("INSTALL_SETTINGS_UNAVAILABLE", error.message, error)
    } catch (error: Exception) {
      promise.reject("INSTALL_SETTINGS_FAILED", error.message, error)
    }
  }

  @ReactMethod
  fun installApk(fileUri: String, promise: Promise) {
    try {
      val file = fileFromUri(fileUri)
      if (!file.exists() || !file.isFile) {
        promise.reject("APK_NOT_FOUND", "Downloaded update file was not found.")
        return
      }

      val contentUri = FileProvider.getUriForFile(
        reactContext,
        "${reactContext.packageName}.updateprovider",
        file,
      )
      val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
        data = contentUri
        putExtra(Intent.EXTRA_RETURN_RESULT, false)
        clipData = ClipData.newUri(reactContext.contentResolver, "1wallet update", contentUri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      }
      startActivity(intent)
      promise.resolve(null)
    } catch (error: ActivityNotFoundException) {
      promise.reject("APK_INSTALLER_UNAVAILABLE", error.message, error)
    } catch (error: IllegalArgumentException) {
      promise.reject("APK_URI_INVALID", error.message, error)
    } catch (error: Exception) {
      promise.reject("APK_INSTALL_FAILED", error.message, error)
    }
  }

  @ReactMethod
  fun sha256(fileUri: String, promise: Promise) {
    try {
      val file = fileFromUri(fileUri)
      if (!file.exists() || !file.isFile) {
        promise.reject("APK_NOT_FOUND", "Downloaded update file was not found.")
        return
      }
      val digest = MessageDigest.getInstance("SHA-256")
      val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
      FileInputStream(file).use { input ->
        while (true) {
          val read = input.read(buffer)
          if (read <= 0) break
          digest.update(buffer, 0, read)
        }
      }
      promise.resolve(digest.digest().joinToString("") { byte -> "%02x".format(byte) })
    } catch (error: Exception) {
      promise.reject("APK_HASH_FAILED", error.message, error)
    }
  }

  private fun startActivity(intent: Intent) {
    val activity = reactContext.currentActivity
    if (activity != null) {
      activity.startActivity(intent)
    } else {
      intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      reactContext.startActivity(intent)
    }
  }

  private fun fileFromUri(fileUri: String): File {
    return if (fileUri.startsWith("file://")) {
      File(Uri.parse(fileUri).path ?: throw IllegalArgumentException("Invalid file URI."))
    } else {
      File(fileUri)
    }
  }

  companion object {
    private const val DEFAULT_BUFFER_SIZE = 1024 * 1024
  }
}
