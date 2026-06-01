package com.joelpjoji.one.wallet

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.widget.RemoteViews
import com.facebook.react.ReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.uimanager.ViewManager

private const val WIDGET_PREFS = "onewallet.home.widgets"
private const val DEFAULT_BALANCE = "Open 1wallet"
private const val DEFAULT_SUBTITLE = "Your wallet is ready"
private const val DEFAULT_UPCOMING = "No planned records synced yet"
private const val DEFAULT_REVIEW = "Review queue clear"

data class OneWalletWidgetSnapshot(
  val balance: String,
  val subtitle: String,
  val upcoming: String,
  val review: String,
  val rules: String,
  val updatedAt: String,
)

object OneWalletWidgetStore {
  fun load(context: Context): OneWalletWidgetSnapshot {
    val prefs = context.getSharedPreferences(WIDGET_PREFS, Context.MODE_PRIVATE)
    return OneWalletWidgetSnapshot(
      balance = prefs.getString("balance", DEFAULT_BALANCE) ?: DEFAULT_BALANCE,
      subtitle = prefs.getString("subtitle", DEFAULT_SUBTITLE) ?: DEFAULT_SUBTITLE,
      upcoming = prefs.getString("upcoming", DEFAULT_UPCOMING) ?: DEFAULT_UPCOMING,
      review = prefs.getString("review", DEFAULT_REVIEW) ?: DEFAULT_REVIEW,
      rules = prefs.getString("rules", "No active rules") ?: "No active rules",
      updatedAt = prefs.getString("updatedAt", "") ?: "",
    )
  }

  fun save(context: Context, snapshot: OneWalletWidgetSnapshot) {
    context.getSharedPreferences(WIDGET_PREFS, Context.MODE_PRIVATE)
      .edit()
      .putString("balance", snapshot.balance)
      .putString("subtitle", snapshot.subtitle)
      .putString("upcoming", snapshot.upcoming)
      .putString("review", snapshot.review)
      .putString("rules", snapshot.rules)
      .putString("updatedAt", snapshot.updatedAt)
      .apply()
  }
}

object OneWalletWidgetUpdater {
  fun updateAll(context: Context) {
    val manager = AppWidgetManager.getInstance(context)
    updateSummary(
      context,
      manager,
      manager.getAppWidgetIds(ComponentName(context, OneWalletSummaryWidgetProvider::class.java)),
    )
    updateActions(
      context,
      manager,
      manager.getAppWidgetIds(ComponentName(context, OneWalletActionsWidgetProvider::class.java)),
    )
  }

  fun updateSummary(context: Context, manager: AppWidgetManager, ids: IntArray) {
    val snapshot = OneWalletWidgetStore.load(context)
    ids.forEach { id ->
      val views = RemoteViews(context.packageName, R.layout.onewallet_widget_summary)
      views.setTextViewText(R.id.widget_balance, snapshot.balance)
      views.setTextViewText(R.id.widget_subtitle, snapshot.subtitle)
      views.setTextViewText(R.id.widget_upcoming, snapshot.upcoming)
      views.setTextViewText(R.id.widget_review, snapshot.review)
      views.setTextViewText(R.id.widget_updated, snapshot.updatedAt)
      val homeIntent = pendingIntent(context, "onewallet:///home", 10)
      views.setOnClickPendingIntent(R.id.widget_summary_root, homeIntent)
      views.setOnClickPendingIntent(R.id.widget_summary_open, homeIntent)
      manager.updateAppWidget(id, views)
    }
  }

  fun updateActions(context: Context, manager: AppWidgetManager, ids: IntArray) {
    val snapshot = OneWalletWidgetStore.load(context)
    ids.forEach { id ->
      val views = RemoteViews(context.packageName, R.layout.onewallet_widget_actions)
      views.setTextViewText(R.id.widget_actions_balance, snapshot.balance)
      views.setTextViewText(R.id.widget_actions_rules, snapshot.rules)
      views.setOnClickPendingIntent(R.id.widget_actions_root, pendingIntent(context, "onewallet:///home", 20))
      views.setOnClickPendingIntent(R.id.widget_action_add, pendingIntent(context, "onewallet:///add", 21))
      views.setOnClickPendingIntent(
        R.id.widget_action_recurring,
        pendingIntent(context, "onewallet:///recurring", 22),
      )
      views.setOnClickPendingIntent(R.id.widget_action_rules, pendingIntent(context, "onewallet:///rules", 23))
      manager.updateAppWidget(id, views)
    }
  }

  private fun pendingIntent(context: Context, uri: String, requestCode: Int): PendingIntent {
    val flags = PendingIntent.FLAG_UPDATE_CURRENT or if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      PendingIntent.FLAG_IMMUTABLE
    } else {
      0
    }
    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(uri)).apply {
      setPackage(context.packageName)
      addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    return PendingIntent.getActivity(context, requestCode, intent, flags)
  }
}

class OneWalletSummaryWidgetProvider : AppWidgetProvider() {
  override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
    OneWalletWidgetUpdater.updateSummary(context, manager, ids)
  }

  override fun onEnabled(context: Context) {
    OneWalletWidgetUpdater.updateAll(context)
  }
}

class OneWalletActionsWidgetProvider : AppWidgetProvider() {
  override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
    OneWalletWidgetUpdater.updateActions(context, manager, ids)
  }

  override fun onEnabled(context: Context) {
    OneWalletWidgetUpdater.updateAll(context)
  }
}

class OneWalletWidgetModule(private val reactContext: ReactApplicationContext) :
  ReactContextBaseJavaModule(reactContext) {
  override fun getName(): String = "OneWalletWidget"

  @ReactMethod
  fun hasWidgets(promise: Promise) {
    val manager = AppWidgetManager.getInstance(reactContext)
    val summaryIds = manager.getAppWidgetIds(ComponentName(reactContext, OneWalletSummaryWidgetProvider::class.java))
    val actionIds = manager.getAppWidgetIds(ComponentName(reactContext, OneWalletActionsWidgetProvider::class.java))
    promise.resolve(summaryIds.isNotEmpty() || actionIds.isNotEmpty())
  }

  @ReactMethod
  fun update(payload: ReadableMap, promise: Promise) {
    val manager = AppWidgetManager.getInstance(reactContext)
    val summaryIds = manager.getAppWidgetIds(ComponentName(reactContext, OneWalletSummaryWidgetProvider::class.java))
    val actionIds = manager.getAppWidgetIds(ComponentName(reactContext, OneWalletActionsWidgetProvider::class.java))
    if (summaryIds.isEmpty() && actionIds.isEmpty()) {
      promise.resolve(null)
      return
    }

    val snapshot = OneWalletWidgetSnapshot(
      balance = payload.getString("balance") ?: DEFAULT_BALANCE,
      subtitle = payload.getString("subtitle") ?: DEFAULT_SUBTITLE,
      upcoming = payload.getString("upcoming") ?: DEFAULT_UPCOMING,
      review = payload.getString("review") ?: DEFAULT_REVIEW,
      rules = payload.getString("rules") ?: "No active rules",
      updatedAt = payload.getString("updatedAt") ?: "",
    )
    OneWalletWidgetStore.save(reactContext, snapshot)
    OneWalletWidgetUpdater.updateSummary(reactContext, manager, summaryIds)
    OneWalletWidgetUpdater.updateActions(reactContext, manager, actionIds)
    promise.resolve(null)
  }
}

class OneWalletWidgetPackage : ReactPackage {
  override fun createNativeModules(reactContext: ReactApplicationContext): MutableList<NativeModule> =
    mutableListOf(
      OneWalletWidgetModule(reactContext),
      OneWalletBackLayerModule(reactContext),
      OneWalletPackageInstallerModule(reactContext),
      OneWalletSmsCaptureModule(reactContext),
    )

  override fun createViewManagers(
    reactContext: ReactApplicationContext,
  ): MutableList<ViewManager<*, *>> = mutableListOf()
}
