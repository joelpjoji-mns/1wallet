package com.joelpjoji.one.wallet

import android.content.Context
import android.content.ContextWrapper
import androidx.test.core.app.ApplicationProvider
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class LegacyUpdateRecoveryTest {
    private lateinit var context: Context
    @Before fun setup() {
        context = ApplicationProvider.getApplicationContext()
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        info.longVersionCode = 2104201L
        info.versionName = "2.2.01"
        shadowOf(context.packageManager).installPackage(info)
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit().clear().commit()
    }
    private fun fields(code: Int) = JSONObject()
        .put("latestVersionCode", JSONObject().put("integerValue", code.toString()))
        .put("latestVersionName", JSONObject().put("stringValue", "2.2.06"))

    @Test fun baseBuildMetadataReproducesTheShippedNativeWorkerSuppression() {
        NotificationReceiver.processAppUpdateFields(context, fields(2102206))
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        assertFalse(prefs.contains("flutter.lastNotifiedVersionCode.stable"))
    }
    @Test fun actualApkBuildAdvancesTheMarkerUsedByTheShippedDartUpdater() {
        NotificationReceiver.processAppUpdateFields(context, fields(2104206))
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        assertEquals(2104206L, prefs.getLong("flutter.lastNotifiedVersionCode.stable", 0L))
        NotificationReceiver.processAppUpdateFields(context, fields(2104206))
        assertEquals(2104206L, prefs.getLong("flutter.lastNotifiedVersionCode.stable", 0L))
    }
    @Test fun blockedNotificationPermissionStillAllowsTheShippedInAppRecovery() {
        val blocked = object : ContextWrapper(context) {
            override fun getSystemService(name: String): Any? {
                if (name == Context.NOTIFICATION_SERVICE) throw SecurityException("Notifications are blocked")
                return super.getSystemService(name)
            }
        }
        NotificationReceiver.processAppUpdateFields(blocked, fields(2104206))
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        assertEquals(2104206L, prefs.getLong("flutter.lastNotifiedVersionCode.stable", 0L))
    }
}
