package com.joelpjoji.one.wallet

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.os.Build

class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null || intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) {
            return
        }

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        val combinedBody = StringBuilder()
        var sender = "Unknown"
        
        for (message in messages) {
            sender = message.displayOriginatingAddress ?: "Unknown"
            combinedBody.append(message.displayMessageBody ?: "")
        }

        val body = combinedBody.toString()
        if (body.isNotEmpty()) {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val triggerWordsStr = prefs.getString("flutter.one_wallet_flutter.sms_trigger_words", "") ?: ""
            var shouldSpool = true
            
            if (triggerWordsStr.isNotEmpty()) {
                try {
                    val jsonArray = org.json.JSONArray(triggerWordsStr)
                    var matched = false
                    val lowerBody = body.lowercase()
                    for (i in 0 until jsonArray.length()) {
                        val word = jsonArray.getString(i).lowercase()
                        if (lowerBody.contains(word)) {
                            matched = true
                            break
                        }
                    }
                    shouldSpool = matched
                } catch (e: Exception) {
                    // Ignore and spool to be safe if parsing fails
                }
            }

            if (shouldSpool) {
                spoolMessage(context, sender, body)
                showNotification(context)
            }
        }
    }

    private fun spoolMessage(context: Context, sender: String, body: String) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val spoolKey = "flutter.one_wallet_flutter.sms_spool"
        
        val prefix = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGxpc3Qu!"
        
        val existingRaw = try { prefs.getString(spoolKey, "") ?: "" } catch (e: Exception) { "" }
        val jsonArray = if (existingRaw.startsWith(prefix)) {
            val jsonStr = existingRaw.substring(prefix.length)
            try {
                org.json.JSONArray(jsonStr)
            } catch (e: Exception) {
                org.json.JSONArray()
            }
        } else {
            org.json.JSONArray()
        }
        
        val payload = org.json.JSONObject()
        payload.put("sender", sender)
        payload.put("body", body)
        
        val df = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", java.util.Locale.US)
        df.timeZone = java.util.TimeZone.getTimeZone("UTC")
        payload.put("timestamp", df.format(java.util.Date()))
        
        jsonArray.put(payload.toString())
        
        val newRaw = prefix + jsonArray.toString()
        // If there's a legacy StringSet, remove it to avoid ClassCastException
        try { prefs.edit().remove(spoolKey).apply() } catch (e: Exception) {}
        
        prefs.edit().putString(spoolKey, newRaw).apply()
    }

    private fun showNotification(context: Context) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = "one_wallet_capture"
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(channelId, "Transaction Capture", NotificationManager.IMPORTANCE_DEFAULT)
            notificationManager.createNotificationChannel(channel)
        }

        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        launchIntent?.putExtra("flutter_route", "/review")
        val pendingIntent = PendingIntent.getActivity(context, 0, launchIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, channelId)
        } else {
            Notification.Builder(context)
        }
        
        builder.setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("New Transaction Detected")
            .setContentText("A new transaction was added to your review queue.")
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)

        notificationManager.notify(1001, builder.build())
    }
}
