package com.joelpjoji.one.wallet

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.provider.Telephony

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

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        val combinedBody = StringBuilder()
        var sender = "Unknown"

        for (message in messages) {
            sender = message.displayOriginatingAddress ?: "Unknown"
            combinedBody.append(message.displayMessageBody ?: "")
        }

        val body = combinedBody.toString()
        if (body.isEmpty()) return

        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

        val captureEnabled = try {
            prefs.getBoolean("flutter.one_wallet_flutter.sms_capture_enabled", true)
        } catch (e: Exception) {
            true
        }
        if (!captureEnabled) return

        val triggers = loadWords(prefs, "flutter.one_wallet_flutter.sms_trigger_words")
        val ignores = loadWords(prefs, "flutter.one_wallet_flutter.sms_ignore_words")
        val lowerBody = body.lowercase()
        val amount = extractAmount(body)

        // Accept only real, completed transactions: an amount AND a trigger word
        // AND no ignore word. This mirrors the Dart parser exactly, so a
        // notification is raised if and only if a review candidate is created.
        val accept = amount != null &&
            containsAnyWord(lowerBody, triggers) &&
            !containsAnyWord(lowerBody, ignores)

        if (accept) {
            spoolMessage(context, sender, body)
            showNotification(context, amount, extractLast4(body))
        }
    }

    private fun loadWords(prefs: SharedPreferences, key: String): List<String> {
        val raw = try { prefs.getString(key, "") ?: "" } catch (e: Exception) { "" }
        if (raw.isEmpty()) return emptyList()
        return try {
            val arr = org.json.JSONArray(raw)
            (0 until arr.length()).map { arr.getString(it).lowercase() }
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun containsAnyWord(lowerBody: String, words: List<String>): Boolean {
        for (raw in words) {
            val word = raw.trim()
            if (word.isEmpty()) continue
            val matched = when {
                word.contains(" ") -> lowerBody.contains(word)
                word.length <= 3 -> "(^|\\W)${Regex.escape(word)}($|\\W)".toRegex().containsMatchIn(lowerBody)
                else -> lowerBody.contains(word)
            }
            if (matched) return true
        }
        return false
    }

    private fun extractAmount(body: String): String? {
        val patterns = listOf(
            Regex("(?:INR|Rs\\.?|₹|USD|\\$|GBP|£|EUR|€|AED|AUD|CAD|SGD|JPY|¥|CHF|CNY)\\s?[0-9][0-9,]*(?:\\.[0-9]{1,2})?", RegexOption.IGNORE_CASE),
            Regex("[0-9][0-9,]*(?:\\.[0-9]{1,2})?\\s?(?:INR|Rs\\.?|₹|USD|\\$|GBP|£|EUR|€|AED)", RegexOption.IGNORE_CASE)
        )
        for (p in patterns) {
            val m = p.find(body)
            if (m != null) return m.value.trim()
        }
        return null
    }

    private fun extractLast4(body: String): String? {
        val patterns = listOf(
            Regex("(?:card|acct|account|a/c|ending)\\D{0,4}(\\d{4})", RegexOption.IGNORE_CASE),
            Regex("[xX*]{2,}(\\d{4})")
        )
        for (p in patterns) {
            val m = p.find(body)
            if (m != null) return m.groupValues[1]
        }
        return null
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
        // If there's a legacy StringSet, remove it to avoid ClassCastException.
        try { prefs.edit().remove(spoolKey).apply() } catch (e: Exception) {}

        prefs.edit().putString(spoolKey, newRaw).apply()
    }

    private fun showNotification(context: Context, amount: String?, last4: String?) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = "one_wallet_capture"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(channelId, "Transaction Capture", NotificationManager.IMPORTANCE_DEFAULT)
            notificationManager.createNotificationChannel(channel)
        }

        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        launchIntent?.putExtra("flutter_route", "/review")
        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, channelId)
        } else {
            Notification.Builder(context)
        }

        val title = if (amount != null) "Transaction detected: $amount" else "Transaction detected"
        val text = if (last4 != null) {
            "Account \u2022\u2022$last4 \u00b7 Tap to review and save."
        } else {
            "Tap to review and save."
        }

        builder.setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)

        notificationManager.notify(1001, builder.build())
    }
}
