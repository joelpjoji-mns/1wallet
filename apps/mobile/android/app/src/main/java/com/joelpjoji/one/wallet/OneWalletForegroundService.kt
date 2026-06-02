package com.joelpjoji.one.wallet

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log

class OneWalletForegroundService : Service() {
  override fun onCreate() {
    super.onCreate()
    promoteToForeground()
  }

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    promoteToForeground()
    return START_STICKY
  }

  override fun onBind(intent: Intent?): IBinder? = null

  override fun onTaskRemoved(rootIntent: Intent?) {
    promoteToForeground()
    super.onTaskRemoved(rootIntent)
  }

  private fun promoteToForeground() {
    runCatching {
      ensureNotificationChannel()
      val notification = buildNotification()
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        startForeground(
          NOTIFICATION_ID,
          notification,
          ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
        )
      } else {
        startForeground(NOTIFICATION_ID, notification)
      }
    }.onFailure { error ->
      Log.w(TAG, "Could not keep 1wallet foreground service active", error)
      stopSelf()
    }
  }

  private fun buildNotification(): Notification {
    val openAppIntent = Intent(this, MainActivity::class.java).apply {
      addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
    }
    val pendingIntentFlags = PendingIntent.FLAG_UPDATE_CURRENT or
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
    val openAppPendingIntent = PendingIntent.getActivity(
      this,
      0,
      openAppIntent,
      pendingIntentFlags,
    )

    val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      Notification.Builder(this, CHANNEL_ID)
    } else {
      @Suppress("DEPRECATION")
      Notification.Builder(this)
    }

    return builder
      .setSmallIcon(R.drawable.ic_stat_onewallet)
      .setContentTitle("1wallet is ready")
      .setContentText("Keeping SMS capture and quick launch active")
      .setContentIntent(openAppPendingIntent)
      .setOngoing(true)
      .setShowWhen(false)
      .setLocalOnly(true)
      .setCategory(Notification.CATEGORY_SERVICE)
      .setPriority(Notification.PRIORITY_MIN)
      .build()
  }

  private fun ensureNotificationChannel() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val notificationManager = getSystemService(NotificationManager::class.java)
    if (notificationManager.getNotificationChannel(CHANNEL_ID) != null) return
    val channel = NotificationChannel(
      CHANNEL_ID,
      "1wallet active",
      NotificationManager.IMPORTANCE_LOW,
    ).apply {
      description = "Keeps 1wallet responsive and ready for SMS capture"
      setShowBadge(false)
      lockscreenVisibility = Notification.VISIBILITY_SECRET
    }
    notificationManager.createNotificationChannel(channel)
  }

  companion object {
    private const val TAG = "OneWalletForeground"
    private const val CHANNEL_ID = "onewallet_foreground_service"
    private const val NOTIFICATION_ID = 1042

    fun start(context: Context) {
      runCatching {
        val intent = Intent(context, OneWalletForegroundService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
          context.startForegroundService(intent)
        } else {
          context.startService(intent)
        }
      }.onFailure { error ->
        Log.w(TAG, "Could not start 1wallet foreground service", error)
      }
    }
  }
}
