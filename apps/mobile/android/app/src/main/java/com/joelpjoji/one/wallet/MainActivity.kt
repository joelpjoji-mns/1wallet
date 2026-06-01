package com.joelpjoji.one.wallet

import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.view.Display
import android.view.View

import com.facebook.react.ReactActivity
import com.facebook.react.ReactActivityDelegate
import com.facebook.react.defaults.DefaultNewArchitectureEntryPoint.fabricEnabled
import com.facebook.react.defaults.DefaultReactActivityDelegate

import expo.modules.ReactActivityDelegateWrapper

class MainActivity : ReactActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    // Keep Theme.App.SplashScreen from the manifest until React draws so the
    // themed launch surface stays visible during native and Metro startup.
    super.onCreate(null)
    preferHighRefreshRate()
    installDrawerGestureExclusion()
  }

  override fun onResume() {
    super.onResume()
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

  companion object {
    private const val DRAWER_GESTURE_EXCLUSION_WIDTH_DP = 32
    private const val DRAWER_GESTURE_EXCLUSION_HEIGHT_DP = 200
    private const val MIN_HIGH_REFRESH_RATE_HZ = 90f
    private const val TARGET_REFRESH_RATE_HZ = 120f
  }
}
