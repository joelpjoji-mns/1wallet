package com.joelpjoji.one.wallet

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class CaptureQueueTest {
    private lateinit var context: Context
    @Before fun setup() {
        context = ApplicationProvider.getApplicationContext()
        CaptureQueue.closeForTesting()
        context.deleteDatabase("capture_queue.db")
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit().clear().commit()
        CaptureQueue.configure(context, "owner-a", """{"smsCaptureEnabled":true}""")
    }
    @After fun close() { CaptureQueue.closeForTesting() }

    @Test fun appendingDuringAcknowledgmentRetainsNewEntries() {
        assertTrue(CaptureQueue.append(context, "sms", JSONObject("""{"body":"first"}"""), "owner-a"))
        val first = CaptureQueue.pending(context, "sms", "owner-a").single()["id"]!!
        assertTrue(CaptureQueue.append(context, "sms", JSONObject("""{"body":"second"}"""), "owner-a"))
        CaptureQueue.acknowledge(context, "owner-a", listOf(first))
        val remaining = CaptureQueue.pending(context, "sms", "owner-a")
        assertEquals(1, remaining.size)
        assertTrue(remaining.single()["payload"]!!.contains("second"))
    }
    @Test fun ownershipAndConfigurationVersionsFenceProducers() {
        val configuration = CaptureQueue.configuration(context)!!
        CaptureQueue.configure(context, "owner-a", """{"smsCaptureEnabled":false}""")
        assertFalse(CaptureQueue.append(context, "sms", JSONObject(), "owner-a", configuration.revision))
        CaptureQueue.configure(context, "owner-b")
        assertFalse(CaptureQueue.append(context, "sms", JSONObject(), "owner-a"))
    }
    @Test fun committedEntriesAndOwnersSurviveReopening() {
        CaptureQueue.append(context, "sms", JSONObject("""{"body":"persisted"}"""), "owner-a")
        CaptureQueue.closeForTesting()
        assertEquals("owner-a", CaptureQueue.owner(context))
        assertEquals(1, CaptureQueue.pending(context, "sms", "owner-a").size)
        assertTrue(CaptureQueue.pending(context, "sms", "owner-b").isEmpty())
    }
    @Test fun legacyMigrationIsIdempotentAndRequiresAssignment() {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val key = "flutter.one_wallet_flutter.sms_spool"
        val raw = """["{\"body\":\"legacy\"}"]"""
        prefs.edit().putString(key, raw).commit()
        assertEquals(1, CaptureQueue.unassigned(context))
        assertTrue(CaptureQueue.pending(context, "sms", "owner-a").isEmpty())
        prefs.edit().putString(key, raw).commit()
        assertEquals(1, CaptureQueue.unassigned(context))
        CaptureQueue.configure(context, "owner-b")
        try {
            CaptureQueue.assignLegacy(context, "owner-a")
            fail("A stale owner must not claim legacy entries")
        } catch (_: IllegalStateException) {
            assertEquals(1, CaptureQueue.unassigned(context))
        }
        CaptureQueue.configure(context, "owner-a")
        CaptureQueue.assignLegacy(context, "owner-a")
        val id = CaptureQueue.pending(context, "sms", "owner-a").single()["id"]!!
        CaptureQueue.acknowledge(context, "owner-b", listOf(id))
        assertEquals(1, CaptureQueue.pending(context, "sms", "owner-a").size)
        CaptureQueue.quarantine(context, "owner-a", id, "invalid body")
        assertTrue(CaptureQueue.pending(context, "sms", "owner-a").isEmpty())
        assertEquals(1, CaptureQueue.quarantined(context, "owner-a"))
    }
}
