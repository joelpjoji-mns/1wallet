package com.joelpjoji.one.wallet

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.firebase.firestore.FlutterFirebaseFirestorePlugin
import io.flutter.plugin.common.MethodChannel
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import android.provider.Telephony
import android.net.Uri
import android.os.Bundle
import android.content.Intent
import org.json.JSONArray
import org.json.JSONObject
import androidx.core.app.NotificationManagerCompat
import android.provider.Settings
import android.graphics.drawable.Drawable
import android.graphics.drawable.BitmapDrawable
import android.graphics.Bitmap
import android.graphics.Canvas
import android.app.Notification
import android.content.ComponentName
import android.os.Build
import android.service.notification.NotificationListenerService
import java.io.ByteArrayOutputStream

class MainActivity : FlutterFragmentActivity() {
	private val CHANNEL = "com.joelpjoji.one.wallet/sms"
	private val SMS_PERMISSION_REQUEST_CODE = 100
    private var initialRoute: String? = null
    private var methodChannel: MethodChannel? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

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
					val readGranted = checkSelfPermission(android.Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED
					val receiveGranted = checkSelfPermission(android.Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED
					if (readGranted && receiveGranted) {
						// Already granted: no system prompt needed, report truthfully now.
						result.success("granted")
					} else if (pendingPermissionResult != null) {
						// Avoid dropping a caller's result if a request is already in flight.
						result.error("PENDING", "A permission request is already in progress", null)
					} else {
						pendingPermissionResult = result
						ActivityCompat.requestPermissions(
							this,
							arrayOf(android.Manifest.permission.READ_SMS, android.Manifest.permission.RECEIVE_SMS),
							SMS_PERMISSION_REQUEST_CODE
						)
					}
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
				"readActiveNotifications" -> {
					try {
						val hasPermission = NotificationManagerCompat.getEnabledListenerPackages(this@MainActivity).contains(packageName)
						if (!hasPermission) {
							result.error("PERMISSION_DENIED", "Notification access permission not granted", null)
							return@setMethodCallHandler
						}

						var instance = NotificationReceiver.instance
						if (instance == null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
							try {
								NotificationListenerService.requestRebind(
									ComponentName(this@MainActivity, NotificationReceiver::class.java)
								)
								var waited = 0
								while (NotificationReceiver.instance == null && waited < 400) {
									Thread.sleep(50)
									waited += 50
								}
								instance = NotificationReceiver.instance
							} catch (_: Exception) {
							}
						}

						if (instance == null) {
							result.error("SERVICE_UNAVAILABLE", "Notification listener service not connected. Please ensure Notification Access is enabled.", null)
							return@setMethodCallHandler
						}

						val requestedPackages = call.argument<List<String>>("packageNames")?.map { it.lowercase() }?.toSet()
						val sbns = instance.activeNotifications ?: emptyArray()
						val jsonArray = JSONArray()
						val pm = packageManager

						for (sbn in sbns) {
							if (sbn == null) continue
							val pkg = sbn.packageName ?: continue
							if (pkg == packageName) continue

							if (requestedPackages != null && requestedPackages.isNotEmpty()) {
								if (!requestedPackages.contains(pkg.lowercase())) {
									continue
								}
							}

							val extras = sbn.notification?.extras
							val title = extras?.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
							val text = extras?.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
							val bigText = extras?.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""
							val subText = extras?.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString() ?: ""

							val combinedText = "$title $text $bigText".trim()
							if (combinedText.isEmpty()) continue

							val appName = try {
								val appInfo = pm.getApplicationInfo(pkg, 0)
								pm.getApplicationLabel(appInfo).toString()
							} catch (_: Exception) {
								pkg
							}

							val postTime = if (sbn.postTime > 0) {
								sbn.postTime
							} else {
								val nWhen = sbn.notification?.`when` ?: 0L
								if (nWhen > 0) nWhen else System.currentTimeMillis()
							}

							val obj = JSONObject()
							obj.put("id", sbn.key ?: "${pkg}_${sbn.id}_${postTime}")
							obj.put("packageName", pkg)
							obj.put("appName", appName)
							obj.put("title", title)
							obj.put("text", text)
							obj.put("bigText", bigText)
							obj.put("subText", subText)
							obj.put("body", combinedText)
							obj.put("date", postTime)
							jsonArray.put(obj)
						}
						result.success(jsonArray.toString())
					} catch (e: Exception) {
						result.error("ERROR", e.message, null)
					}
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

	override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
		super.onRequestPermissionsResult(requestCode, permissions, grantResults)
		if (requestCode == SMS_PERMISSION_REQUEST_CODE) {
			val pending = pendingPermissionResult
			pendingPermissionResult = null
			// Re-check via checkSelfPermission rather than trusting grantResults ordering,
			// so the reported state always reflects the actual permission state.
			val readGranted = checkSelfPermission(android.Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED
			val receiveGranted = checkSelfPermission(android.Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED
			pending?.success(if (readGranted && receiveGranted) "granted" else "denied")
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
