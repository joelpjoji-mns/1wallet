package com.joelpjoji.one.wallet

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import com.facebook.react.HeadlessJsTaskService
import com.facebook.react.bridge.Arguments
import com.facebook.react.jstasks.HeadlessJsTaskConfig
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.ReadableArray
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.bridge.ReadableType
import java.util.Locale

private const val SMS_CAPTURE_PREFS = "onewallet.sms.capture"
private const val SMS_HEADLESS_TIMEOUT_MS = 12000L

private val DEFAULT_SMS_TRIGGER_KEYWORDS = listOf(
  "credited",
  "debited",
  "credit",
  "debit",
  "paid",
  "spent",
  "purchase",
  "received",
  "refund",
  "cashback",
  "withdrawn",
  "charged",
  "deducted",
  "auto debit",
  "upi",
  "imps",
  "neft",
  "rtgs",
  "pos",
  "atm",
  "card transaction",
  "inr",
  "rs",
  "gbp",
  "usd",
)

private val SECURITY_SMS_TERMS = listOf(
  "otp",
  "one time password",
  "verification code",
  "security code",
  "password",
  "login code",
)

private val BALANCE_ONLY_TERMS = listOf(
  "available balance",
  "avl bal",
  "current balance",
  "balance is",
)

private val BALANCE_TRANSACTION_TERMS = listOf(
  "credited",
  "debited",
  "paid",
  "spent",
  "purchase",
  "received",
  "refund",
  "cashback",
  "withdrawn",
  "charged",
  "deducted",
)

data class OneWalletSmsCapturePreferences(
  val enabled: Boolean,
  val smsEnabled: Boolean,
  val backgroundEnabled: Boolean,
  val triggerKeywords: List<String>,
  val ignoredSenderIds: List<String>,
)

object OneWalletSmsCaptureStore {
  fun load(context: Context): OneWalletSmsCapturePreferences {
    val prefs = context.getSharedPreferences(SMS_CAPTURE_PREFS, Context.MODE_PRIVATE)
    return OneWalletSmsCapturePreferences(
      enabled = prefs.getBoolean("enabled", false),
      smsEnabled = prefs.getBoolean("smsEnabled", false),
      backgroundEnabled = prefs.getBoolean("backgroundEnabled", false),
      triggerKeywords = prefs.getStringSet("triggerKeywords", DEFAULT_SMS_TRIGGER_KEYWORDS.toSet())
        ?.toList()
        ?.filter { it.isNotBlank() }
        ?: DEFAULT_SMS_TRIGGER_KEYWORDS,
      ignoredSenderIds = prefs.getStringSet("ignoredSenderIds", emptySet())
        ?.toList()
        ?.filter { it.isNotBlank() }
        ?: emptyList(),
    )
  }

  fun save(context: Context, preferences: OneWalletSmsCapturePreferences) {
    context.getSharedPreferences(SMS_CAPTURE_PREFS, Context.MODE_PRIVATE)
      .edit()
      .putBoolean("enabled", preferences.enabled)
      .putBoolean("smsEnabled", preferences.smsEnabled)
      .putBoolean("backgroundEnabled", preferences.backgroundEnabled)
      .putStringSet("triggerKeywords", preferences.triggerKeywords.map(::normalizeKeyword).filter { it.length >= 2 }.toSet())
      .putStringSet("ignoredSenderIds", preferences.ignoredSenderIds.map(::normalizeSenderId).filter { it.isNotBlank() }.toSet())
      .apply()
  }
}

object OneWalletSmsCaptureGate {
  fun shouldStartHeadless(context: Context, sender: String?, body: String): Boolean {
    val preferences = OneWalletSmsCaptureStore.load(context)
    if (!preferences.enabled || !preferences.smsEnabled || !preferences.backgroundEnabled) return false

    val normalizedSender = normalizeSenderId(sender.orEmpty())
    if (normalizedSender.isNotBlank()) {
      val ignoredSenders = preferences.ignoredSenderIds.map(::normalizeSenderId).filter { it.isNotBlank() }
      if (ignoredSenders.any { normalizedSender.contains(it) }) return false
    }

    val rawText = body.trim()
    if (rawText.isBlank()) return false

    val normalizedText = normalizeSearchText(rawText)
    if (containsAny(normalizedText, SECURITY_SMS_TERMS)) return false
    if (looksBalanceOnly(normalizedText)) return false

    val keywords = preferences.triggerKeywords.ifEmpty { DEFAULT_SMS_TRIGGER_KEYWORDS }
    return keywords.any { keyword -> keywordMatches(rawText, normalizedText, keyword) }
  }
}

class OneWalletSmsReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

    val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
    if (messages.isEmpty()) return

    val body = messages.joinToString(separator = "") { message -> message.messageBody ?: "" }.trim()
    if (body.isEmpty()) return

    val sender = messages.firstOrNull()?.originatingAddress
    if (!OneWalletSmsCaptureGate.shouldStartHeadless(context, sender, body)) return

    val receivedAt = messages
      .map { message -> message.timestampMillis }
      .filter { timestamp -> timestamp > 0L }
      .minOrNull() ?: System.currentTimeMillis()

    val serviceIntent = Intent(context, OneWalletSmsHeadlessService::class.java).apply {
      putExtra("sender", sender)
      putExtra("body", body)
      putExtra("receivedAt", receivedAt.toDouble())
    }
    context.startService(serviceIntent)
    HeadlessJsTaskService.acquireWakeLockNow(context)
  }
}

class OneWalletSmsHeadlessService : HeadlessJsTaskService() {
  override fun getTaskConfig(intent: Intent?): HeadlessJsTaskConfig? {
    val extras = intent?.extras ?: return null
    return HeadlessJsTaskConfig(
      "OneWalletSmsReceived",
      Arguments.fromBundle(extras),
      SMS_HEADLESS_TIMEOUT_MS,
      true,
    )
  }
}

class OneWalletSmsCaptureModule(private val reactContext: ReactApplicationContext) :
  ReactContextBaseJavaModule(reactContext) {
  override fun getName(): String = "OneWalletSmsCapture"

  @ReactMethod
  fun syncPreferences(payload: ReadableMap, promise: Promise) {
    OneWalletSmsCaptureStore.save(
      reactContext,
      OneWalletSmsCapturePreferences(
        enabled = readBoolean(payload, "enabled", false),
        smsEnabled = readBoolean(payload, "smsEnabled", false),
        backgroundEnabled = readBoolean(payload, "backgroundEnabled", false),
        triggerKeywords = readStringArray(payload.getArrayOrNull("triggerKeywords")),
        ignoredSenderIds = readStringArray(payload.getArrayOrNull("ignoredSenderIds")),
      ),
    )
    promise.resolve(null)
  }
}

private fun readBoolean(payload: ReadableMap, key: String, fallback: Boolean): Boolean =
  if (payload.hasKey(key) && !payload.isNull(key)) payload.getBoolean(key) else fallback

private fun ReadableMap.getArrayOrNull(key: String): ReadableArray? =
  if (hasKey(key) && !isNull(key)) getArray(key) else null

private fun readStringArray(array: ReadableArray?): List<String> {
  if (array == null) return emptyList()
  val values = mutableListOf<String>()
  for (index in 0 until array.size()) {
    if (array.getType(index) == ReadableType.String) {
      val value = array.getString(index)?.trim().orEmpty()
      if (value.isNotBlank()) values.add(value)
    }
  }
  return values
}

private fun normalizeKeyword(value: String): String =
  value.trim().lowercase(Locale.ROOT).replace(Regex("\\s+"), " ").take(64)

private fun normalizeSearchText(value: String): String =
  value.lowercase(Locale.ROOT).replace(Regex("[^a-z0-9]+"), " ").replace(Regex("\\s+"), " ").trim()

private fun normalizeSenderId(value: String): String =
  value.trim().uppercase(Locale.ROOT).replace(Regex("[^A-Z0-9]"), "")

private fun containsAny(normalizedText: String, terms: List<String>): Boolean =
  terms.any { term -> normalizedContainsTerm(normalizedText, term) }

private fun looksBalanceOnly(normalizedText: String): Boolean {
  val hasBalanceTerm = BALANCE_ONLY_TERMS.any { term -> normalizedContainsTerm(normalizedText, term) }
  if (!hasBalanceTerm) return false
  return BALANCE_TRANSACTION_TERMS.none { term -> normalizedContainsTerm(normalizedText, term) }
}

private fun normalizedContainsTerm(normalizedText: String, term: String): Boolean =
  " $normalizedText ".contains(" ${normalizeSearchText(term)} ")

private fun keywordMatches(rawText: String, normalizedText: String, keyword: String): Boolean {
  val normalizedKeyword = normalizeKeyword(keyword)
  if (normalizedKeyword.length < 2) return false
  val symbolKeyword = normalizedKeyword.any { char -> !char.isLetterOrDigit() && !char.isWhitespace() }
  if (symbolKeyword) return rawText.lowercase(Locale.ROOT).contains(normalizedKeyword)
  return " $normalizedText ".contains(" $normalizedKeyword ")
}
