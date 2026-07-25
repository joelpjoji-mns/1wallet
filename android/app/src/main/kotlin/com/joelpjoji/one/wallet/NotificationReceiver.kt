package com.joelpjoji.one.wallet

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.content.Context
import android.content.SharedPreferences
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.os.Build

class NotificationReceiver : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return

        val context = applicationContext
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

        // 1. Check if notification capture is enabled
        val captureEnabled = try {
            prefs.getBoolean("flutter.one_wallet_flutter.notification_capture_enabled", false)
        } catch (e: Exception) {
            false
        }
        if (!captureEnabled) return

        // 2. Check if the package is in the target whitelist
        val packageName = sbn.packageName ?: return
        val targetPackages = loadList(prefs, "flutter.one_wallet_flutter.notification_target_packages")
        if (!targetPackages.contains(packageName.lowercase())) {
            return
        }

        // 3. Extract title and body/text
        val extras = sbn.notification.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""

        // Combine them to parse
        val combinedText = "$title $text $bigText".trim()
        if (combinedText.isEmpty()) return

        val triggers = loadList(prefs, "flutter.one_wallet_flutter.notification_trigger_words")
        val ignores = loadList(prefs, "flutter.one_wallet_flutter.notification_ignore_words")
        val lowerText = combinedText.lowercase()
        val amount = extractAmount(combinedText)
        val matchedTrigger = findMatchingWord(lowerText, triggers)
        val matchedIgnore = findMatchingWord(lowerText, ignores)

        // 4. Accept only real transactions (same rules as SMS)
        val accept = amount != null && matchedTrigger != null && matchedIgnore == null

        if (accept) {
            val spooled = spoolMessage(context, title.ifEmpty { "Notification" }, combinedText, amount, matchedTrigger)
            val notificationShown = if (spooled) showNotification(context, amount, extractLast4(combinedText)) else false
            appendDiagnostic(
                context,
                source = "notification",
                stage = "native-notification",
                decision = if (spooled) "accepted" else "error",
                reason = if (spooled) "spooled before notification" else "spool failed",
                rawText = combinedText,
                amount = amount,
                matchedTriggerWord = matchedTrigger,
                notificationShown = notificationShown,
                nativeAccepted = spooled
            )
        } else if (amount != null || matchedTrigger != null || matchedIgnore != null) {
            appendDiagnostic(
                context,
                source = "notification",
                stage = "native-notification",
                decision = "ignored",
                reason = nativeIgnoreReason(amount, matchedTrigger, matchedIgnore),
                rawText = combinedText,
                amount = amount,
                matchedTriggerWord = matchedTrigger,
                matchedIgnoreWord = matchedIgnore
            )
        }
    }

    private fun loadList(prefs: SharedPreferences, key: String): List<String> {
        val raw = try { prefs.getString(key, "") ?: "" } catch (e: Exception) { "" }
        if (raw.isEmpty()) return emptyList()
        return try {
            val arr = org.json.JSONArray(raw)
            (0 until arr.length()).map { arr.getString(it).lowercase() }
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun containsAnyWord(lowerText: String, words: List<String>): Boolean {
        return findMatchingWord(lowerText, words) != null
    }

    private fun findMatchingWord(lowerText: String, words: List<String>): String? {
        for (raw in words) {
            val word = raw.trim()
            if (word.isEmpty()) continue
            val matched = when {
                word.contains(" ") -> lowerText.contains(word)
                word.length <= 3 -> "(^|\\W)${Regex.escape(word)}($|\\W)".toRegex().containsMatchIn(lowerText)
                else -> lowerText.contains(word)
            }
            if (matched) return raw
        }
        return null
    }

    private fun extractAmount(text: String): String? {
        val patterns = listOf(
            Regex("(?:INR|Rs\\.?|₹|USD|\\$|GBP|£|EUR|€|AED|AUD|CAD|SGD|JPY|¥|CHF|CNY)\\s?[0-9][0-9,]*(?:\\.[0-9]{1,2})?", RegexOption.IGNORE_CASE),
            Regex("[0-9][0-9,]*(?:\\.[0-9]{1,2})?\\s?(?:INR|Rs\\.?|₹|USD|\\$|GBP|£|EUR|€|AED)", RegexOption.IGNORE_CASE),
            Regex("(?:debited|credited|spent|received|paid|withdrawn|deposited|transferred|charged|refund)\\s+(?:INR|Rs\\.?|₹|USD|\\$|GBP|£|EUR|€)?\\s?[0-9][0-9,]*(?:\\.[0-9]{1,2})?", RegexOption.IGNORE_CASE)
        )
        for (p in patterns) {
            val m = p.find(text)
            if (m != null) return m.value.trim()
        }
        return null
    }

    private fun extractLast4(text: String): String? {
        val patterns = listOf(
            Regex("(?:card|acct|account|a/c|ending)\\D{0,4}(\\d{3,4})", RegexOption.IGNORE_CASE),
            Regex("[xX*]{2,}(\\d{3,4})")
        )
        for (p in patterns) {
            val m = p.find(text)
            if (m != null) return m.groupValues[1]
        }
        return null
    }

    private fun spoolMessage(context: Context, sender: String, body: String, amount: String?, matchedTrigger: String?): Boolean {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val spoolKey = "flutter.one_wallet_flutter.notification_spool"

        val existingRaw = try { prefs.getString(spoolKey, "") ?: "" } catch (e: Exception) { "" }
        val jsonArray = if (existingRaw.isNotEmpty()) {
            try {
                org.json.JSONArray(existingRaw)
            } catch (e: Exception) {
                org.json.JSONArray()
            }
        } else {
            org.json.JSONArray()
        }

        val payload = org.json.JSONObject()
        payload.put("sender", sender)
        payload.put("body", body)
        payload.put("nativeSource", "notification")
        payload.put("nativeAccepted", true)
        payload.put("notificationShown", true)
        if (amount != null) payload.put("nativeMatchedAmount", amount)
        if (matchedTrigger != null) payload.put("nativeMatchedTriggerWord", matchedTrigger)

        val df = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", java.util.Locale.US)
        df.timeZone = java.util.TimeZone.getTimeZone("UTC")
        payload.put("timestamp", df.format(java.util.Date()))

        jsonArray.put(payload.toString())

        return try {
            prefs.edit().putString(spoolKey, jsonArray.toString()).commit()
        } catch (e: Exception) {
            false
        }
    }

    private fun showNotification(context: Context, amount: String?, last4: String?): Boolean {
        return try {
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

        notificationManager.notify((System.currentTimeMillis() % Int.MAX_VALUE).toInt(), builder.build())
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun nativeIgnoreReason(amount: String?, matchedTrigger: String?, matchedIgnore: String?): String {
        if (matchedIgnore != null) return "matched ignore word"
        if (amount == null) return "missing amount"
        if (matchedTrigger == null) return "missing trigger word"
        return "ignored"
    }

    private fun appendDiagnostic(
        context: Context,
        source: String,
        stage: String,
        decision: String,
        reason: String? = null,
        rawText: String? = null,
        amount: String? = null,
        matchedTriggerWord: String? = null,
        matchedIgnoreWord: String? = null,
        notificationShown: Boolean = false,
        nativeAccepted: Boolean = false
    ) {
        try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val key = "flutter.one_wallet_flutter.capture_diagnostics"
            val existingRaw = try { prefs.getString(key, "") ?: "" } catch (e: Exception) { "" }
            val existing = if (existingRaw.isNotEmpty()) {
                try { org.json.JSONArray(existingRaw) } catch (e: Exception) { org.json.JSONArray() }
            } else {
                org.json.JSONArray()
            }
            val payload = org.json.JSONObject()
            payload.put("id", "native-${System.currentTimeMillis()}")
            payload.put("timestamp", java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", java.util.Locale.US).apply {
                timeZone = java.util.TimeZone.getTimeZone("UTC")
            }.format(java.util.Date()))
            payload.put("source", source)
            payload.put("stage", stage)
            payload.put("decision", decision)
            if (reason != null) payload.put("reason", reason)
            if (rawText != null) payload.put("rawText", rawText)
            if (amount != null) payload.put("nativeMatchedAmount", amount)
            if (matchedTriggerWord != null) payload.put("matchedTriggerWord", matchedTriggerWord)
            if (matchedIgnoreWord != null) payload.put("matchedIgnoreWord", matchedIgnoreWord)
            payload.put("notificationShown", notificationShown)
            payload.put("nativeAccepted", nativeAccepted)

            val next = org.json.JSONArray()
            next.put(payload.toString())
            val keep = kotlin.math.min(existing.length(), 149)
            for (i in 0 until keep) next.put(existing.get(i))
            prefs.edit().putString(key, next.toString()).apply()
        } catch (_: Exception) {
        }
    }
}
