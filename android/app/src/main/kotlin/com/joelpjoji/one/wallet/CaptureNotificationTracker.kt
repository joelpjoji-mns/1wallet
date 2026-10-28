package com.joelpjoji.one.wallet

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.math.abs

object CaptureNotificationTracker {
    private const val PREFS_NAME = "capture_notification_tracker"
    private const val KEY_RECENT_NOTIFICATIONS = "recent_notifications"
    private const val DEDUPE_WINDOW_MS = 120_000L // 2 minutes
    private const val CLEANUP_WINDOW_MS = 300_000L // 5 minutes
    private const val SBN_DEDUPE_WINDOW_MS = 60_000L // 1 minute

    data class NotificationRecord(
        val normalizedAmount: Long,
        val direction: String,
        val last4: String?,
        val timestamp: Long
    )

    private val recentNotifications = CopyOnWriteArrayList<NotificationRecord>()
    private val recentSbnEvents = java.util.concurrent.ConcurrentHashMap<String, Long>()

    @Synchronized
    fun shouldShowNotification(
        context: Context,
        rawAmount: String?,
        text: String,
        last4: String?
    ): Boolean {
        val now = System.currentTimeMillis()
        cleanOldRecords(context, now)

        val normalized = normalizeAmount(rawAmount) ?: return true
        val direction = detectDirection(text)

        // Check in-memory records
        for (record in recentNotifications) {
            if (now - record.timestamp <= DEDUPE_WINDOW_MS) {
                if (record.normalizedAmount == normalized) {
                    val directionsCompatible = record.direction == "unknown" ||
                            direction == "unknown" ||
                            record.direction == direction
                    val accountsCompatible = record.last4 == null ||
                            last4 == null ||
                            record.last4 == last4

                    if (directionsCompatible && accountsCompatible) {
                        // Found a matching notification shown within 2 minutes: suppress duplicate!
                        return false
                    }
                }
            }
        }

        // If not found in memory, also verify SharedPreferences in case of process recreation
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val savedJson = prefs.getString(KEY_RECENT_NOTIFICATIONS, null)
        if (savedJson != null) {
            try {
                val array = JSONArray(savedJson)
                for (i in 0 until array.length()) {
                    val obj = array.getJSONObject(i)
                    val ts = obj.optLong("ts", 0L)
                    if (now - ts <= DEDUPE_WINDOW_MS) {
                        val amt = obj.optLong("amt", -1L)
                        val dir = obj.optString("dir", "unknown")
                        val l4 = if (obj.has("l4") && !obj.isNull("l4")) obj.getString("l4") else null
                        if (amt == normalized) {
                            val directionsCompatible = dir == "unknown" || direction == "unknown" || dir == direction
                            val accountsCompatible = l4 == null || last4 == null || l4 == last4
                            if (directionsCompatible && accountsCompatible) {
                                return false
                            }
                        }
                    }
                }
            } catch (_: Exception) {}
        }

        // New notification: record it
        val newRecord = NotificationRecord(normalized, direction, last4, now)
        recentNotifications.add(newRecord)
        persistRecords(context)
        return true
    }

    @Synchronized
    fun isDuplicateStatusBarNotification(sbnKey: String, text: String): Boolean {
        val now = System.currentTimeMillis()
        // Clean old sbn events
        val it = recentSbnEvents.entries.iterator()
        while (it.hasNext()) {
            val entry = it.next()
            if (now - entry.value > SBN_DEDUPE_WINDOW_MS) {
                it.remove()
            }
        }

        val eventKey = "$sbnKey:${text.hashCode()}"
        val lastSeen = recentSbnEvents[eventKey]
        if (lastSeen != null && (now - lastSeen) <= SBN_DEDUPE_WINDOW_MS) {
            return true
        }
        recentSbnEvents[eventKey] = now
        return false
    }

    fun getNotificationId(rawAmount: String?, last4: String?): Int {
        val normalized = normalizeAmount(rawAmount)
        return if (normalized != null) {
            val key = "$normalized:${last4 ?: ""}"
            4000 + (abs(key.hashCode()) % 10000)
        } else {
            (System.currentTimeMillis() % 100000).toInt() + 4000
        }
    }

    fun normalizeAmount(raw: String?): Long? {
        if (raw.isNullOrBlank()) return null
        val digitsAndDot = raw.replace(Regex("[^0-9.]"), "")
        if (digitsAndDot.isEmpty()) return null

        val parts = digitsAndDot.split(".")
        return try {
            val whole = parts[0].toLongOrNull() ?: 0L
            val fraction = if (parts.size > 1) {
                val fracStr = parts[1].padEnd(2, '0').take(2)
                fracStr.toIntOrNull() ?: 0
            } else {
                0
            }
            whole * 100L + fraction
        } catch (_: Exception) {
            null
        }
    }

    fun detectDirection(text: String): String {
        val lower = text.lowercase()
        val creditKeywords = listOf("credited", "received", "deposited", "refund")
        val debitKeywords = listOf("debited", "spent", "paid", "withdrawn", "charged", "sent", "purchase")

        val hasCredit = creditKeywords.any { lower.contains(it) }
        val hasDebit = debitKeywords.any { lower.contains(it) }

        return when {
            hasCredit && !hasDebit -> "credit"
            hasDebit && !hasCredit -> "debit"
            else -> "unknown"
        }
    }

    private fun cleanOldRecords(context: Context, now: Long) {
        recentNotifications.removeIf { now - it.timestamp > CLEANUP_WINDOW_MS }
    }

    private fun persistRecords(context: Context) {
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val array = JSONArray()
            for (record in recentNotifications) {
                val obj = JSONObject()
                obj.put("amt", record.normalizedAmount)
                obj.put("dir", record.direction)
                if (record.last4 != null) obj.put("l4", record.last4)
                obj.put("ts", record.timestamp)
                array.put(obj)
            }
            prefs.edit().putString(KEY_RECENT_NOTIFICATIONS, array.toString()).apply()
        } catch (_: Exception) {}
    }
}
