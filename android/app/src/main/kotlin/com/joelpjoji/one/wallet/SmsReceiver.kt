package com.joelpjoji.one.wallet

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.os.Build

class SmsReceiver : BroadcastReceiver() {
    companion object {
        private val DEFAULT_TRIGGERS = listOf(
            "debited", "credited", "spent", "paid", "received", "withdrawn",
            "deposited", "sent", "charged", "transferred", "refund"
        )
        private val DEFAULT_IGNORES = listOf(
            "otp", "code", "requested", "failed", "declined", "pending",
            "due", "statement", "bill", "reminder"
        )
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return
        val pending = goAsync()
        CaptureQueue.executor.execute {
            try { captureSms(context, intent) }
            catch (error: Exception) { android.util.Log.e("1WalletCapture", "SMS capture failed", error) }
            finally { pending.finish() }
        }
    }

    private fun captureSms(context: Context?, intent: Intent?) {
        if (context == null || intent == null || intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) {
            return
        }

        val captureConfiguration = CaptureQueue.configuration(context) ?: return
        val captureOwner = captureConfiguration.owner
        NotificationReceiver.startBackgroundWorker(context)

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        val combinedBody = StringBuilder()
        var sender = "Unknown"

        for (message in messages) {
            sender = message.displayOriginatingAddress ?: "Unknown"
            combinedBody.append(message.displayMessageBody ?: "")
        }

        val body = combinedBody.toString()
        if (body.isEmpty()) return


        val captureEnabled = captureConfiguration.settings.optBoolean("smsCaptureEnabled", false)
        if (!captureEnabled) return

        val triggers = CaptureQueue.words(captureConfiguration.settings, "smsTriggerWords", DEFAULT_TRIGGERS)
        val ignores = CaptureQueue.words(captureConfiguration.settings, "smsIgnoreWords", DEFAULT_IGNORES)
        val lowerBody = body.lowercase()

        val builtInBillIgnores = listOf(
            "bill generated", "statement generated", "bill is generated", "statement is generated",
            "bill has been generated", "statement has been generated", "bill has generated",
            "statement has generated", "statement ready", "bill ready", "bill is ready",
            "statement is ready", "total amount due", "minimum amount due", "total due",
            "min due", "payment due", "bill due", "amount due", "e-statement", "e-bill"
        )
        val matchedBillNotice = findMatchingWord(lowerBody, builtInBillIgnores)
        if (matchedBillNotice != null) {
            val amount = extractAmount(body)
            val spooled = spoolMessage(
                context,
                sender,
                body,
                amount,
                matchedBillNotice,
                isBillStatement = true, expectedOwner = captureOwner, expectedRevision = captureConfiguration.revision
            )
            val notificationShown = showBillStatementNotification(context, amount, extractLast4(body))
            appendDiagnostic(
                context,
                source = "sms",
                stage = "native-sms",
                decision = "bill-statement-notice",
                reason = "detected card bill/statement notice and spooled for card account update",
                rawText = body,
                amount = amount,
                matchedIgnoreWord = matchedBillNotice,
                notificationShown = notificationShown,
                nativeAccepted = spooled
            )
            return
        }

        val amount = extractAmount(body)
        val matchedTrigger = findMatchingWord(lowerBody, triggers)
        val matchedIgnore = findMatchingWord(lowerBody, ignores)

        // Accept only real, completed transactions: an amount AND a trigger word
        // AND no ignore word. This mirrors the Dart parser exactly, so a
        // notification is raised if and only if a review candidate is created.
        val accept = amount != null && matchedTrigger != null && matchedIgnore == null

        if (accept) {
            val last4 = extractLast4(body)
            val shouldNotify = CaptureNotificationTracker.shouldShowNotification(context, amount, body, last4)
            val spooled = spoolMessage(
                context, sender, body, amount, matchedTrigger,
                expectedOwner = captureOwner, expectedRevision = captureConfiguration.revision,
                notificationShown = shouldNotify
            )
            val notificationShown = if (spooled && shouldNotify) showNotification(context, amount, last4) else false
            appendDiagnostic(
                context,
                source = "sms",
                stage = "native-sms",
                decision = if (spooled) "accepted" else "error",
                reason = if (spooled) (if (shouldNotify) "spooled before notification" else "suppressed duplicate notification") else "spool failed",
                rawText = body,
                amount = amount,
                matchedTriggerWord = matchedTrigger,
                notificationShown = notificationShown,
                nativeAccepted = spooled
            )
        } else if (amount != null || matchedTrigger != null || matchedIgnore != null) {
            appendDiagnostic(
                context,
                source = "sms",
                stage = "native-sms",
                decision = "ignored",
                reason = nativeIgnoreReason(amount, matchedTrigger, matchedIgnore),
                rawText = body,
                amount = amount,
                matchedTriggerWord = matchedTrigger,
                matchedIgnoreWord = matchedIgnore
            )
        }
    }

    private fun findMatchingWord(lowerBody: String, words: List<String>): String? {
        for (raw in words) {
            val word = raw.trim()
            if (word.isEmpty()) continue
            val matched = when {
                word.contains(" ") -> lowerBody.contains(word)
                word.length <= 3 -> "(^|\\W)${Regex.escape(word)}($|\\W)".toRegex().containsMatchIn(lowerBody)
                else -> lowerBody.contains(word)
            }
            if (matched) return raw
        }
        return null
    }

    private fun extractAmount(body: String): String? {
        val patterns = listOf(
            Regex("(?:INR|Rs\\.?|₹|USD|\\$|GBP|£|EUR|€|AED|AUD|CAD|SGD|JPY|¥|CHF|CNY)\\s?[0-9][0-9,]*(?:\\.[0-9]{1,2})?", RegexOption.IGNORE_CASE),
            Regex("[0-9][0-9,]*(?:\\.[0-9]{1,2})?\\s?(?:INR|Rs\\.?|₹|USD|\\$|GBP|£|EUR|€|AED)", RegexOption.IGNORE_CASE),
            Regex("(?:debited|credited|spent|received|paid|withdrawn|deposited|transferred|charged|refund)\\s+(?:INR|Rs\\.?|₹|USD|\\$|GBP|£|EUR|€)?\\s?[0-9][0-9,]*(?:\\.[0-9]{1,2})?", RegexOption.IGNORE_CASE)
        )
        for (p in patterns) {
            val m = p.find(body)
            if (m != null) return m.value.trim().replace(",", "")
        }
        return null
    }

    private fun extractLast4(body: String): String? {
        val patterns = listOf(
            Regex("(?:card|acct|account|a/c|ending)\\D{0,4}(\\d{3,4})", RegexOption.IGNORE_CASE),
            Regex("[xX*]{2,}(\\d{3,4})")
        )
        for (p in patterns) {
            val m = p.find(body)
            if (m != null) return m.groupValues[1]
        }
        return null
    }

    private fun spoolMessage(
        context: Context, sender: String, body: String, amount: String?,
        matchedTrigger: String?, isBillStatement: Boolean = false, expectedOwner: String, expectedRevision: Long,
        notificationShown: Boolean = true
    ): Boolean {
        val payload = org.json.JSONObject()
        payload.put("sender", sender)
        payload.put("body", body)
        payload.put("nativeSource", "sms")
        payload.put("nativeAccepted", true)
        payload.put("notificationShown", notificationShown)
        payload.put("timestamp", java.time.Instant.now().toString())
        if (isBillStatement) payload.put("isBillStatement", true)
        if (amount != null) payload.put("nativeMatchedAmount", amount)
        if (matchedTrigger != null) payload.put("nativeMatchedTriggerWord", matchedTrigger)
        return CaptureQueue.append(context, "sms", payload, expectedOwner, expectedRevision)
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
            val reqCode = (System.currentTimeMillis() % 100000).toInt() + 1000
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

            NotificationReceiver.applyNotificationIcons(context, builder)
            builder.setContentTitle(title)
                .setContentText(text)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)

            val notificationId = CaptureNotificationTracker.getNotificationId(amount, last4)
            notificationManager.notify(notificationId, builder.build())
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
            val reqCode = (System.currentTimeMillis() % 100000).toInt() + 4000
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

            NotificationReceiver.applyNotificationIcons(context, builder)
            builder.setContentTitle(title)
                .setContentText(text)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)

            val notificationId = CaptureNotificationTracker.getNotificationId(amount, last4)
            notificationManager.notify(notificationId, builder.build())
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
            val owner = CaptureQueue.owner(context) ?: "unassigned"
            val key = "flutter.one_wallet_flutter.capture_diagnostics.$owner"
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
