package com.joelpjoji.one.wallet

import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Rect
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.LayerDrawable
import android.os.Build
import android.os.Bundle
import android.view.Display
import android.view.Gravity
import android.view.View

import com.facebook.react.ReactActivity
import com.facebook.react.ReactActivityDelegate
import com.facebook.react.defaults.DefaultNewArchitectureEntryPoint.fabricEnabled
import com.facebook.react.defaults.DefaultReactActivityDelegate

import expo.modules.ReactActivityDelegateWrapper
import java.io.File
import org.json.JSONObject

class MainActivity : ReactActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    // Keep Theme.App.SplashScreen from the manifest until React draws so the
    // themed launch surface stays visible during native and Metro startup.
    applyCachedSplashTheme()
    super.onCreate(null)
    OneWalletForegroundService.start(this)
    preferHighRefreshRate()
    installDrawerGestureExclusion()
  }

  override fun onResume() {
    super.onResume()
    OneWalletForegroundService.start(this)
    preferHighRefreshRate()
  }

  /**
   * Returns the name of the main component registered from JavaScript. This is used to schedule
   * rendering of the component.
   */
  override fun getMainComponentName(): String = "main"

  /**
   * Returns the instance of the [ReactActivityDelegate]. We use [DefaultReactActivityDelegate]
   * which allows you to enable New Architecture with a single boolean flags [fabricEnabled]
   */
  override fun createReactActivityDelegate(): ReactActivityDelegate {
    return ReactActivityDelegateWrapper(
          this,
          BuildConfig.IS_NEW_ARCHITECTURE_ENABLED,
          object : DefaultReactActivityDelegate(
              this,
              mainComponentName,
              fabricEnabled
          ){})
  }

  /**
    * Align the back button behavior with Android S
    * where moving root activities to background instead of finishing activities.
    * @see <a href="https://developer.android.com/reference/android/app/Activity#onBackPressed()">onBackPressed</a>
    */
  override fun invokeDefaultOnBackPressed() {
      if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.R) {
          if (!moveTaskToBack(false)) {
              // For non-root activities, use the default implementation to finish them.
              super.invokeDefaultOnBackPressed()
          }
          return
      }

      // Use the default back button implementation on Android S
      // because it's doing more than [Activity.moveTaskToBack] in fact.
      super.invokeDefaultOnBackPressed()
  }

  private fun installDrawerGestureExclusion() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return

    val contentView = window.decorView.findViewById<View>(android.R.id.content) ?: window.decorView
    val applyExclusion = { view: View ->
      val density = resources.displayMetrics.density
      val widthPx = (DRAWER_GESTURE_EXCLUSION_WIDTH_DP * density).toInt()
      val heightPx = (DRAWER_GESTURE_EXCLUSION_HEIGHT_DP * density).toInt().coerceAtMost(view.height)
      val topPx = ((view.height - heightPx) / 2).coerceAtLeast(0)
      view.systemGestureExclusionRects = listOf(Rect(0, topPx, widthPx, topPx + heightPx))
    }

    contentView.post { applyExclusion(contentView) }
    contentView.addOnLayoutChangeListener { view, _, _, _, _, _, _, _, _ -> applyExclusion(view) }
  }

  private fun preferHighRefreshRate() {
    val attributes = window.attributes
    attributes.preferredRefreshRate = TARGET_REFRESH_RATE_HZ

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      highestRefreshMode()?.let { mode ->
        attributes.preferredDisplayModeId = mode.modeId
        attributes.preferredRefreshRate = mode.refreshRate
      }
    }

    window.attributes = attributes
  }

  private fun highestRefreshMode(): Display.Mode? {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return null

    @Suppress("DEPRECATION")
    val display = windowManager.defaultDisplay
    val currentMode = display.mode
    val currentSizeModes = display.supportedModes.filter { mode ->
      mode.physicalWidth == currentMode.physicalWidth && mode.physicalHeight == currentMode.physicalHeight
    }
    val modes = currentSizeModes.ifEmpty { display.supportedModes.toList() }

    return modes
      .filter { mode -> mode.refreshRate >= MIN_HIGH_REFRESH_RATE_HZ }
      .maxByOrNull { mode -> mode.refreshRate }
  }

  @Suppress("DEPRECATION")
  private fun applyCachedSplashTheme() {
    val mode = cachedThemePreference().takeUnless { it == "system" } ?: systemSplashMode()
    val backgroundColor = when (mode) {
      "light" -> LIGHT_SPLASH_COLOR
      "amoled" -> AMOLED_SPLASH_COLOR
      else -> DARK_SPLASH_COLOR
    }
    window.setBackgroundDrawable(splashDrawable(backgroundColor))
    window.statusBarColor = backgroundColor
    window.navigationBarColor = backgroundColor
    applyLightSystemBars(mode == "light")
  }

  private fun splashDrawable(backgroundColor: Int): LayerDrawable {
    val logo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
      resources.getDrawable(R.drawable.splashscreen_image, theme)
    } else {
      @Suppress("DEPRECATION")
      resources.getDrawable(R.drawable.splashscreen_image)
    }
    val drawable = LayerDrawable(arrayOf(ColorDrawable(backgroundColor), logo))
    drawable.setLayerGravity(1, Gravity.CENTER)
    return drawable
  }

  private fun cachedThemePreference(): String? {
    val file = File(filesDir, THEME_PREFERENCE_FILE_NAME)
    if (!file.isFile) return null
    return runCatching {
      val value = JSONObject(file.readText()).optString("theme")
      value.takeIf { it == "system" || it == "light" || it == "dark" || it == "amoled" }
    }.getOrNull()
  }

  private fun systemSplashMode(): String {
    val nightMode = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
    return if (nightMode == Configuration.UI_MODE_NIGHT_YES) "dark" else "light"
  }

  @Suppress("DEPRECATION")
  private fun applyLightSystemBars(light: Boolean) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return

    var flags = window.decorView.systemUiVisibility
    flags = if (light) {
      flags or View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
    } else {
      flags and View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR.inv()
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      flags = if (light) {
        flags or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
      } else {
        flags and View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR.inv()
      }
    }
    window.decorView.systemUiVisibility = flags
  }

  companion object {
    private const val THEME_PREFERENCE_FILE_NAME = "1wallet-theme-preference.json"
    private val LIGHT_SPLASH_COLOR = Color.WHITE
    private val DARK_SPLASH_COLOR = Color.rgb(16, 18, 20)
    private val AMOLED_SPLASH_COLOR = Color.BLACK
    private const val DRAWER_GESTURE_EXCLUSION_WIDTH_DP = 32
    private const val DRAWER_GESTURE_EXCLUSION_HEIGHT_DP = 200
    private const val MIN_HIGH_REFRESH_RATE_HZ = 90f
    private const val TARGET_REFRESH_RATE_HZ = 120f
  }
}
