package com.joelpjoji.one.wallet

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.firebase.firestore.FlutterFirebaseFirestorePlugin
import io.flutter.plugin.common.MethodChannel
import android.content.pm.PackageManager
import android.provider.Telephony
import android.net.Uri
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterFragmentActivity() {
	private val CHANNEL = "com.joelpjoji.one.wallet/sms"

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		if (!flutterEngine.plugins.has(FlutterFirebaseFirestorePlugin::class.java)) {
			flutterEngine.plugins.add(FlutterFirebaseFirestorePlugin())
		}

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
			when (call.method) {
				"isAvailable" -> result.success(true)
				"getPermissionState" -> {
					val read = if (checkSelfPermission(android.Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED) "granted" else "denied"
					val receive = if (checkSelfPermission(android.Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED) "granted" else "denied"
					result.success(mapOf("read" to read, "receive" to receive))
				}
				"requestPermissions" -> {
					requestPermissions(arrayOf(android.Manifest.permission.READ_SMS, android.Manifest.permission.RECEIVE_SMS), 100)
					result.success("granted") // Simplified for now
				}
				"readInbox" -> {
					try {
						val maxCount = call.argument<Int>("maxCount") ?: 200
						val minDate = call.argument<Long>("minDate")
						val maxDate = call.argument<Long>("maxDate")
						
						var selection: String? = null
						var selectionArgs: Array<String>? = null
						
						if (minDate != null) {
							selection = "date >= ?"
							selectionArgs = arrayOf(minDate.toString())
						}
						
						val cursor = contentResolver.query(
							Uri.parse("content://sms/inbox"),
							arrayOf("_id", "address", "body", "date"),
							selection,
							selectionArgs,
							"date DESC LIMIT $maxCount"
						)

						val jsonArray = JSONArray()
						cursor?.use {
							while (it.moveToNext()) {
								val obj = JSONObject()
								obj.put("_id", it.getString(it.getColumnIndexOrThrow("_id")))
								obj.put("address", it.getString(it.getColumnIndexOrThrow("address")))
								obj.put("body", it.getString(it.getColumnIndexOrThrow("body")))
								obj.put("date", it.getLong(it.getColumnIndexOrThrow("date")))
								jsonArray.put(obj)
							}
						}
						result.success(jsonArray.toString())
					} catch (e: Exception) {
						result.error("ERROR", e.message, null)
					}
				}
				else -> result.notImplemented()
			}
		}
	}
}
