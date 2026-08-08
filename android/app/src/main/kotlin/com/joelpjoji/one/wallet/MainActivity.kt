package com.joelpjoji.one.wallet

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.firebase.firestore.FlutterFirebaseFirestorePlugin
import io.flutter.plugin.common.MethodChannel
import android.content.pm.PackageManager
import android.provider.Telephony
import android.net.Uri
import android.os.Bundle
import android.content.Intent
import org.json.JSONArray
import org.json.JSONObject
import androidx.core.app.NotificationManagerCompat
import android.provider.Settings
import android.graphics.drawable.BitmapDrawable
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import java.io.ByteArrayOutputStream

class MainActivity : FlutterFragmentActivity() {
	private val CHANNEL = "com.joelpjoji.one.wallet/sms"
    private var initialRoute: String? = null
    private var methodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        initialRoute = intent?.getStringExtra("flutter_route")
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val route = intent.getStringExtra("flutter_route")
        if (route != null) {
            initialRoute = route
            methodChannel?.invokeMethod("onRoute", route)
        }
    }

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		if (!flutterEngine.plugins.has(FlutterFirebaseFirestorePlugin::class.java)) {
			flutterEngine.plugins.add(FlutterFirebaseFirestorePlugin())
		}

		methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
		methodChannel!!.setMethodCallHandler { call, result ->
			when (call.method) {
				"getInitialRoute" -> {
					val r = initialRoute
					initialRoute = null
					result.success(r)
				}
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
						val minDate = call.argument<Number>("minDate")?.toLong()
						val maxDate = call.argument<Number>("maxDate")?.toLong()

						val selectionParts = mutableListOf<String>()
						val selectionArgsList = mutableListOf<String>()
						if (minDate != null) {
							selectionParts.add("date >= ?")
							selectionArgsList.add(minDate.toString())
						}
						if (maxDate != null) {
							selectionParts.add("date <= ?")
							selectionArgsList.add(maxDate.toString())
						}

						val selection = if (selectionParts.isEmpty()) null else selectionParts.joinToString(" AND ")
						val selectionArgs = if (selectionArgsList.isEmpty()) null else selectionArgsList.toTypedArray()
						val sortOrder = if (maxCount > 0) "date DESC LIMIT $maxCount" else "date DESC"

						val cursor = contentResolver.query(
							Uri.parse("content://sms/inbox"),
							arrayOf("_id", "address", "body", "date"),
							selection,
							selectionArgs,
							sortOrder
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
				"checkNotificationPermission" -> {
					val enabled = NotificationManagerCompat.getEnabledListenerPackages(this@MainActivity).contains(packageName)
					result.success(enabled)
				}
				"requestNotificationPermission" -> {
					val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
					startActivity(intent)
					result.success(true)
				}
				"getInstalledApps" -> {
					try {
						val pm = packageManager
						val apps = pm.getInstalledApplications(PackageManager.GET_META_DATA)
						val jsonArray = JSONArray()
						for (app in apps) {
							if ((app.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) == 0 || (app.flags and android.content.pm.ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0) {
								val obj = JSONObject()
								obj.put("packageName", app.packageName)
								obj.put("appName", pm.getApplicationLabel(app).toString())
								jsonArray.put(obj)
							}
						}
						result.success(jsonArray.toString())
					} catch (e: Exception) {
						result.error("ERROR", e.message, null)
					}
				}
				"getAppIcon" -> {
					try {
						val pkg = call.argument<String>("packageName")
						if (pkg != null) {
							val pm = packageManager
							val icon = pm.getApplicationIcon(pkg)
							val bitmap = getBitmapFromDrawable(icon)
							val stream = ByteArrayOutputStream()
							bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
							result.success(stream.toByteArray())
						} else {
							result.error("ERROR", "Package name is null", null)
						}
					} catch (e: Exception) {
						result.error("ERROR", e.message, null)
					}
				}
				else -> result.notImplemented()
			}
		}
	}

	private fun getBitmapFromDrawable(drawable: Drawable): Bitmap {
		if (drawable is BitmapDrawable) {
			return drawable.bitmap
		}
		val width = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else 100
		val height = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 100
		val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
		val canvas = Canvas(bitmap)
		drawable.setBounds(0, 0, canvas.width, canvas.height)
		drawable.draw(canvas)
		return bitmap
	}
}
