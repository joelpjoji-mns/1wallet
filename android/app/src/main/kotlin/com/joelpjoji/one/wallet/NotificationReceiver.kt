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
    companion object {
        // See SmsReceiver.MAX_SPOOL_ENTRIES for rationale: bounds unbounded
        // spool growth while surfacing drops as diagnostics instead of
        // silently discarding queued captures.
        private const val MAX_SPOOL_ENTRIES = 500

        @Volatile
        var instance: NotificationReceiver? = null

        @Volatile
        private var isBackgroundWorkerRunning = false

        private val DEFAULT_PACKAGES = listOf(
            "com.chase.sig.android",
            "com.revolut.revolut",
            "com.google.android.apps.nbu.paisa.user",
            "com.google.android.apps.walletnfcrel",
            "com.venmo",
            "com.paypal.android.p2pmobile",
            "com.monzo.android",
            "com.capitalone.mobile",
            "com.amex.android.amexmobile",
            "org.westpac.bank",
            "com.commbank.netbank",
            "net.bnz.boost",
            "com.phonepe.app",
            "net.one97.paytm"
        )

        private val DEFAULT_TRIGGERS = listOf(
            "debited", "credited", "spent", "paid", "received", "withdrawn",
            "deposited", "sent", "charged", "transferred", "refund"
        )

        private val DEFAULT_IGNORES = listOf(
            "otp", "code", "requested", "failed", "declined", "pending",
            "due", "statement", "bill", "reminder"
        )

        fun startBackgroundWorker(context: Context) {
            if (isBackgroundWorkerRunning) return
            synchronized(this) {
                if (isBackgroundWorkerRunning) return
                isBackgroundWorkerRunning = true
                val appContext = context.applicationContext
                val thread = Thread {
                    while (true) {
                        try {
                            checkAppUpdates(appContext)
                        } catch (_: Exception) {
                        }
                        try {
                            // Very light background thread: checks update channel every 15 minutes
                            Thread.sleep(15 * 60 * 1000L)
                        } catch (_: InterruptedException) {
                            break
                        }
                    }
                }
                thread.isDaemon = true
                thread.name = "1wallet-light-bg-thread"
                thread.start()
            }
        }

        private fun checkAppUpdates(context: Context) {
            try {
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val projectId = prefs.getString("flutter.firebase_project_id", "wallet-1a5af")?.takeIf { it.isNotBlank() } ?: "wallet-1a5af"
                val apiKey = prefs.getString("flutter.firebase_api_key", "") ?: ""
                val queryParam = if (apiKey.isNotBlank()) "?key=$apiKey" else ""
                val url = java.net.URL("https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/appUpdates/android/channels/stable$queryParam")
                val conn = (url.openConnection() as java.net.HttpURLConnection).apply {
                    connectTimeout = 8000
                    readTimeout = 8000
                    requestMethod = "GET"
                }
                if (conn.responseCode == 200) {
                    val body = conn.inputStream.bufferedReader().use { it.readText() }
                    val json = org.json.JSONObject(body)
                    val fields = json.optJSONObject("fields") ?: return
                    val latestCode = fields.optJSONObject("latestVersionCode")?.optString("integerValue")?.toIntOrNull()
                        ?: fields.optJSONObject("latestVersionCode")?.optInt("integerValue") ?: 0
                    val latestName = fields.optJSONObject("latestVersionName")?.optString("stringValue") ?: "New version"

                    val pm = context.packageManager
                    val pInfo = pm.getPackageInfo(context.packageName, 0)
                    val currentCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        pInfo.longVersionCode.toInt()
                    } else {
                        @Suppress("DEPRECATION")
                        pInfo.versionCode
                    }

                    val lastNotified = try {
                        prefs.getLong("flutter.lastNotifiedVersionCode.stable", 0L).toInt()
                    } catch (_: Exception) {
                        try { prefs.getInt("flutter.lastNotifiedVersionCode.stable", 0) } catch (_: Exception) { 0 }
                    }

                    if (latestCode > currentCode && latestCode > lastNotified) {
                        showAppUpdateNotification(context, latestName)
                        prefs.edit().putLong("flutter.lastNotifiedVersionCode.stable", latestCode.toLong()).apply()
                    }
                }
            } catch (_: Exception) {
            }
        }

        fun showAppUpdateNotification(context: Context, versionName: String) {
            try {
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                val channelId = "app_updates"
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val channel = NotificationChannel(
                        channelId,
                        "App Updates",
                        NotificationManager.IMPORTANCE_HIGH
                    ).apply {
                        description = "Notifications for new app versions"
                    }
                    notificationManager.createNotificationChannel(channel)
                }

                val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                launchIntent?.putExtra("flutter_route", "/updates")
                val pendingIntent = PendingIntent.getActivity(
                    context,
                    201,
                    launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )

                val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    Notification.Builder(context, channelId)
                } else {
                    Notification.Builder(context)
                }

                val smallIcon = context.resources.getIdentifier("ic_launcher", "mipmap", context.packageName)
                    .takeIf { it != 0 } ?: android.R.drawable.ic_dialog_info

                builder.setSmallIcon(smallIcon)
                    .setContentTitle("Update Available")
                    .setContentText("Version $versionName is ready to install")
                    .setContentIntent(pendingIntent)
                    .setAutoCancel(true)

                notificationManager.notify(99999, builder.build())
            } catch (_: Exception) {
            }
        }
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        instance = this
        startBackgroundWorker(this)
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        if (instance == this) {
            instance = null
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        if (instance == this) {
            instance = null
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return

        val context = applicationContext
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

        // 1. Check if notification capture is enabled (defaults to true)
        val captureEnabled = try {
            if (prefs.contains("flutter.one_wallet_flutter.notification_capture_enabled")) {
                prefs.getBoolean("flutter.one_wallet_flutter.notification_capture_enabled", true)
            } else {
                true
            }
        } catch (e: Exception) {
            true
        }
        if (!captureEnabled) return

        // 2. Check if the package is in the target whitelist
        val packageName = sbn.packageName ?: return
        val targetPackages = loadList(prefs, "flutter.one_wallet_flutter.notification_target_packages", DEFAULT_PACKAGES)
        if (!targetPackages.contains(packageName.lowercase())) {
            return
        }

        // 3. Extract title and body/text
        val extras = sbn.notification.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim() ?: ""
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.trim() ?: ""

        // Deduplicate text and bigText if they overlap, and preserve full message cleanly
        val contentBody = when {
            bigText.isNotBlank() && text.isNotBlank() && bigText.contains(text) -> bigText
            text.isNotBlank() && bigText.isNotBlank() && text.contains(bigText) -> text
            bigText.isNotBlank() && text.isNotBlank() -> "$text $bigText"
            bigText.isNotBlank() -> bigText
            else -> text
        }.trim()

        val combinedText = if (title.isNotBlank()) {
            if (contentBody.isNotBlank()) "$title: $contentBody" else title
        } else {
            contentBody
        }.trim()

        if (combinedText.isEmpty()) return

        val triggers = loadList(prefs, "flutter.one_wallet_flutter.notification_trigger_words", DEFAULT_TRIGGERS)
        val ignores = loadList(prefs, "flutter.one_wallet_flutter.notification_ignore_words", DEFAULT_IGNORES)
        val lowerText = combinedText.lowercase()

        val builtInBillIgnores = listOf(
            "bill generated", "statement generated", "bill is generated", "statement is generated",
            "bill has been generated", "statement has been generated", "bill has generated",
            "statement has generated", "statement ready", "bill ready", "bill is ready",
            "statement is ready", "total amount due", "minimum amount due", "total due",
            "min due", "payment due", "bill due", "amount due", "e-statement", "e-bill"
        )
        val matchedBillNotice = findMatchingWord(lowerText, builtInBillIgnores)
        if (matchedBillNotice != null) {
            val amount = extractAmount(combinedText)
            val notificationShown = showBillStatementNotification(context, amount, extractLast4(combinedText))
            appendDiagnostic(
                context,
                source = "notification",
                stage = "native-notification",
                decision = "bill-statement-notice",
                reason = "detected card bill/statement notice instead of transaction",
                rawText = combinedText,
                amount = amount,
                matchedIgnoreWord = matchedBillNotice,
                notificationShown = notificationShown
            )
            return
        }

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

    private fun loadList(prefs: SharedPreferences, key: String, fallback: List<String> = emptyList()): List<String> {
        val raw = try { prefs.getString(key, "") ?: "" } catch (e: Exception) { "" }
        if (raw.isEmpty()) return fallback
        return try {
            val arr = org.json.JSONArray(raw)
            val list = (0 until arr.length()).map { arr.getString(it).lowercase() }.filter { it.isNotBlank() }
            if (list.isEmpty()) fallback else list
        } catch (e: Exception) {
            fallback
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

        // Bound unbounded growth: drop oldest entries (FIFO) rather than
        // growing SharedPreferences without limit, and surface the drop via
        // a diagnostic entry instead of silently discarding captures.
        var droppedCount = 0
        while (jsonArray.length() > MAX_SPOOL_ENTRIES) {
            jsonArray.remove(0)
            droppedCount++
        }

        val saved = try {
            prefs.edit().putString(spoolKey, jsonArray.toString()).commit()
        } catch (e: Exception) {
            false
        }

        if (saved && droppedCount > 0) {
            appendDiagnostic(
                context,
                source = "notification",
                stage = "native-notification",
                decision = "overflow",
                reason = "dropped $droppedCount oldest queued notification capture(s) to bound spool size at $MAX_SPOOL_ENTRIES"
            )
        }

        return saved
    }

    private fun showBillStatementNotification(context: Context, amount: String?, last4: String?): Boolean {
        return try {
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channelId = "one_wallet_capture"

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    channelId,
                    "Transaction Capture",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Notifications for detected bank transactions and statements"
                }
                notificationManager.createNotificationChannel(channel)
            }

            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
                putExtra("flutter_route", "/sync")
                addFlags(android.content.Intent.FLAG_ACTIVITY_CLEAR_TOP or android.content.Intent.FLAG_ACTIVITY_SINGLE_TOP)
                data = android.net.Uri.parse("onewallet://sync?ts=${System.currentTimeMillis()}")
            }
            val reqCode = (System.currentTimeMillis() % 100000).toInt() + 2000
            val pendingIntent = PendingIntent.getActivity(
                context,
                reqCode,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, channelId)
            } else {
                Notification.Builder(context)
            }

            val title = if (amount != null) "Statement notice: $amount" else "Bill statement detected"
            val text = if (last4 != null) {
                "Card ••$last4 · Tap to view upcoming statement."
            } else {
                "Tap to review detected statement notice."
            }

            val smallIcon = context.resources.getIdentifier("ic_launcher", "mipmap", context.packageName)
                .takeIf { it != 0 } ?: android.R.drawable.ic_dialog_info

            builder.setSmallIcon(smallIcon)
                .setContentTitle(title)
                .setContentText(text)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)

            notificationManager.notify((System.currentTimeMillis() % Int.MAX_VALUE).toInt(), builder.build())
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun showNotification(context: Context, amount: String?, last4: String?): Boolean {
        return try {
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channelId = "one_wallet_capture"

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    channelId,
                    "Transaction Capture",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Notifications for detected bank transactions and statements"
                }
                notificationManager.createNotificationChannel(channel)
            }

            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
                putExtra("flutter_route", "/review")
                addFlags(android.content.Intent.FLAG_ACTIVITY_CLEAR_TOP or android.content.Intent.FLAG_ACTIVITY_SINGLE_TOP)
                data = android.net.Uri.parse("onewallet://review?ts=${System.currentTimeMillis()}")
            }
            val reqCode = (System.currentTimeMillis() % 100000).toInt() + 3000
            val pendingIntent = PendingIntent.getActivity(
                context,
                reqCode,
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
                "Account ••$last4 · Tap to review and save."
            } else {
                "Tap to review and save."
            }

            val smallIcon = context.resources.getIdentifier("ic_launcher", "mipmap", context.packageName)
                .takeIf { it != 0 } ?: android.R.drawable.ic_dialog_info

            builder.setSmallIcon(smallIcon)
                .setContentTitle(title)
                .setContentText(text)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)

            notificationManager.notify((System.currentTimeMillis() % Int.MAX_VALUE).toInt(), builder.build())
            true
        } catch (_: Exception) {
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
