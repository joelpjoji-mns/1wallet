package com.joelpjoji.one.wallet

import android.os.Build
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher
import com.facebook.react.bridge.LifecycleEventListener
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.modules.core.DeviceEventManagerModule

private const val BACK_LAYER_EVENT = "oneWalletBackLayerBack"

class OneWalletBackLayerModule(private val reactContext: ReactApplicationContext) :
  ReactContextBaseJavaModule(reactContext),
  LifecycleEventListener {
  private var enabled = false
  private var callback: OnBackInvokedCallback? = null
  private var callbackActivity: android.app.Activity? = null

  init {
    reactContext.addLifecycleEventListener(this)
  }

  override fun getName(): String = "OneWalletBackLayer"

  @ReactMethod
  fun setEnabled(nextEnabled: Boolean) {
    enabled = nextEnabled
    updateRegistration()
  }

  @ReactMethod
  fun addListener(eventName: String) = Unit

  @ReactMethod
  fun removeListeners(count: Int) = Unit

  override fun onHostResume() {
    updateRegistration()
  }

  override fun onHostPause() {
    unregisterCallback()
  }

  override fun onHostDestroy() {
    unregisterCallback()
  }

  private fun updateRegistration() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return

    val activity = reactContext.currentActivity
    if (!enabled || activity == null) {
      unregisterCallback()
      return
    }

    if (callback != null && callbackActivity == activity) return

    unregisterCallback()

    val nextCallback = OnBackInvokedCallback {
      reactContext
        .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
        .emit(BACK_LAYER_EVENT, null)
    }

    activity.getOnBackInvokedDispatcher().registerOnBackInvokedCallback(
      OnBackInvokedDispatcher.PRIORITY_DEFAULT,
      nextCallback,
    )
    callback = nextCallback
    callbackActivity = activity
  }

  private fun unregisterCallback() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return

    val registeredCallback = callback ?: return
    callbackActivity?.getOnBackInvokedDispatcher()?.unregisterOnBackInvokedCallback(registeredCallback)
    callback = null
    callbackActivity = null
  }
}
