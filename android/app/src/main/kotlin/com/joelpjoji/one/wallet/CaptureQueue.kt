package com.joelpjoji.one.wallet

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Executors
import org.json.JSONArray
import org.json.JSONObject

object CaptureQueue {
    val executor = Executors.newSingleThreadExecutor()
    private var helper: Store? = null
    internal fun closeForTesting() {
        helper?.close()
        helper = null
    }
    @Synchronized private fun database(context: Context): SQLiteDatabase {
        if (helper == null) helper = Store(context.applicationContext)
        return helper!!.writableDatabase
    }
    private class Store(context: Context) : SQLiteOpenHelper(context, "capture_queue.db", null, 2) {
        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE configuration (singleton INTEGER PRIMARY KEY CHECK(singleton=1), owner TEXT, revision INTEGER NOT NULL DEFAULT 0, settings TEXT NOT NULL DEFAULT '{}')")
            db.execSQL("INSERT INTO configuration(singleton,owner) VALUES(1,NULL)")
            db.execSQL("CREATE TABLE entries (id TEXT PRIMARY KEY, source TEXT NOT NULL, owner TEXT, payload TEXT NOT NULL, state TEXT NOT NULL, error TEXT, created INTEGER NOT NULL)")
            db.execSQL("CREATE INDEX pending_owner ON entries(owner,source,state,created)")
        }
        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
            if (oldVersion == 1 && newVersion == 2) {
                db.execSQL("ALTER TABLE configuration ADD COLUMN revision INTEGER NOT NULL DEFAULT 0")
                db.execSQL("ALTER TABLE configuration ADD COLUMN settings TEXT NOT NULL DEFAULT '{}'")
            } else throw IllegalStateException("Unsupported capture queue upgrade")
        }
    }
    fun owner(context: Context): String? =
        database(context).rawQuery("SELECT owner FROM configuration WHERE singleton=1", null).use {
            if (it.moveToFirst() && !it.isNull(0)) it.getString(0) else null
        }
    data class ProducerConfiguration(val owner: String, val revision: Long, val settings: JSONObject)
    fun configuration(context: Context): ProducerConfiguration? =
        database(context).rawQuery("SELECT owner,revision,settings FROM configuration WHERE singleton=1", null).use {
            if (!it.moveToFirst() || it.isNull(0)) null
            else ProducerConfiguration(it.getString(0), it.getLong(1), JSONObject(it.getString(2)))
        }
    fun words(settings: JSONObject, key: String, fallback: List<String>): List<String> {
        if (!settings.has(key)) return fallback
        val values = settings.getJSONArray(key)
        return (0 until values.length()).map {
            val value = values.get(it)
            require(value is String) { "Invalid capture word list" }
            value.trim().lowercase()
        }.filter { it.isNotEmpty() }
    }
    fun configure(context: Context, owner: String?, settings: String? = null) {
        val db = database(context)
        db.beginTransaction()
        try {
            db.rawQuery("SELECT owner,revision,settings FROM configuration WHERE singleton=1", null).use {
                check(it.moveToFirst())
                val oldOwner = if (it.isNull(0)) null else it.getString(0)
                val nextSettings = settings ?: it.getString(2)
                JSONObject(nextSettings)
                if (oldOwner == owner && nextSettings == it.getString(2)) {
                    db.setTransactionSuccessful()
                    return
                }
                db.update("configuration", ContentValues().apply {
                    put("owner", owner); put("settings", nextSettings)
                    put("revision", it.getLong(1) + 1)
                }, "singleton=1", null)
            }
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
    }
    fun append(context: Context, source: String, payload: JSONObject, expectedOwner: String, expectedRevision: Long? = null): Boolean {
        val db = database(context)
        db.beginTransaction()
        try {
            val configuration = configuration(context)
            if (configuration?.owner != expectedOwner ||
                (expectedRevision != null && configuration.revision != expectedRevision)) return false
            db.insertOrThrow("entries", null, ContentValues().apply {
                put("id", UUID.randomUUID().toString()); put("source", source)
                put("owner", expectedOwner); put("payload", payload.toString())
                put("state", "pending"); put("created", System.currentTimeMillis())
            })
            db.setTransactionSuccessful()
            return true
        } finally { db.endTransaction() }
    }
    fun migrate(context: Context) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        for (source in listOf("sms", "notification")) {
            val key = "flutter.one_wallet_flutter.${source}_spool"
            val raw = prefs.getString(key, null) ?: continue
            val db = database(context)
            db.beginTransaction()
            try {
                val items = try { JSONArray(raw) } catch (_: org.json.JSONException) { JSONArray().put(raw) }
                for (i in 0 until items.length()) {
                    val payload = items.get(i).toString()
                    val id = MessageDigest.getInstance("SHA-256")
                        .digest("$source:$i:$payload".toByteArray()).joinToString("") { "%02x".format(it) }
                    db.insertWithOnConflict("entries", null, ContentValues().apply {
                        put("id", "legacy-$id"); put("source", source); putNull("owner")
                        put("payload", payload); put("state", "unassigned")
                        put("created", System.currentTimeMillis() + i)
                    }, SQLiteDatabase.CONFLICT_IGNORE)
                }
                db.setTransactionSuccessful()
            } finally { db.endTransaction() }
            if (!prefs.edit().remove(key).commit()) throw IllegalStateException("Legacy spool migration acknowledgment failed")
        }
    }
    fun pending(context: Context, source: String, owner: String): List<Map<String, String>> {
        migrate(context)
        return database(context).rawQuery(
            "SELECT id,payload FROM entries WHERE owner=? AND source=? AND state='pending' ORDER BY created,id LIMIT 100",
            arrayOf(owner, source)
        ).use { cursor ->
            val result = mutableListOf<Map<String, String>>()
            while (cursor.moveToNext()) result.add(mapOf("id" to cursor.getString(0), "payload" to cursor.getString(1)))
            result
        }
    }
    fun acknowledge(context: Context, owner: String, ids: List<String>) {
        val db = database(context)
        db.beginTransaction()
        try {
            for (id in ids) db.delete("entries", "owner=? AND id=? AND state='pending'", arrayOf(owner,id))
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
    }
    fun quarantine(context: Context, owner: String, id: String, reason: String) {
        database(context).update("entries", ContentValues().apply {
            put("state", "quarantine"); put("error", reason.take(512))
        }, "owner=? AND id=?", arrayOf(owner,id))
    }
    fun unassigned(context: Context): Int {
        migrate(context)
        return database(context).rawQuery("SELECT COUNT(*) FROM entries WHERE state='unassigned'", null)
            .use { it.moveToFirst(); it.getInt(0) }
    }
    fun quarantined(context: Context, owner: String): Int =
        database(context).rawQuery("SELECT COUNT(*) FROM entries WHERE owner=? AND state='quarantine'", arrayOf(owner))
            .use { it.moveToFirst(); it.getInt(0) }
    fun assignLegacy(context: Context, owner: String) {
        val db = database(context)
        db.beginTransaction()
        try {
            if (this.owner(context) != owner) throw IllegalStateException("Capture owner changed")
            db.update("entries", ContentValues().apply {
                put("owner", owner); put("state", "pending")
            }, "state='unassigned' AND owner IS NULL", null)
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
    }
    fun purge(context: Context, owner: String) {
        database(context).delete("entries", "owner=?", arrayOf(owner))
    }
}
