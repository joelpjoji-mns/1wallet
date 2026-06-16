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
            spoolMessage(context, sender, body)
        }
    }

    private fun spoolMessage(context: Context, sender: String, body: String) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val spoolKey = "flutter.one_wallet_flutter.sms_spool"
        
        // Flutter's shared_preferences stores StringList as a Set<String> on Android
        val existingSpooled = prefs.getStringSet(spoolKey, null) ?: mutableSetOf<String>()
        val newSpooled = existingSpooled.toMutableSet()
        
        val payload = JSONObject()
        payload.put("sender", sender)
        payload.put("body", body)
        
        val df = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
        df.timeZone = TimeZone.getTimeZone("UTC")
        payload.put("timestamp", df.format(Date()))
        
        newSpooled.add(payload.toString())
        
        prefs.edit().putStringSet(spoolKey, newSpooled).apply()
    }
}
