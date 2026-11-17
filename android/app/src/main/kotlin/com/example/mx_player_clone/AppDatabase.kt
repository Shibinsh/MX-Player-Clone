package com.example.mx_player_clone

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

class AppDatabase private constructor(context: Context) : SQLiteOpenHelper(
    context.applicationContext,
    "mx_player_clone.db",
    null,
    1
) {
    private val dao = object : TransferHistoryDao {
        override fun insert(item: TransferHistoryEntity): Long {
            val db = writableDatabase
            val values = ContentValues().apply {
                put("fileName", item.fileName)
                put("filePath", item.filePath)
                put("fileSize", item.fileSize)
                put("fileType", item.fileType)
                put("senderDevice", item.senderDevice)
                put("receiverDevice", item.receiverDevice)
                put("remoteDevice", item.remoteDevice)
                put("remoteIp", item.remoteIp)
                put("direction", item.direction)
                put("status", item.status)
                put("speedBytesPerSecond", item.speedBytesPerSecond)
                put("durationMillis", item.durationMillis)
                put("createdAtMillis", item.createdAtMillis)
                put("error", item.error)
            }
            return db.insert("transfer_history", null, values)
        }

        override fun page(query: String, filter: String, limit: Int, offset: Int): List<TransferHistoryEntity> {
            val db = readableDatabase
            val selectionClauses = mutableListOf<String>()
            val selectionArgs = mutableListOf<String>()

            if (query.isNotBlank()) {
                selectionClauses.add("(fileName LIKE ? OR remoteDevice LIKE ? OR remoteIp LIKE ?)")
                val q = "%$query%"
                selectionArgs.add(q)
                selectionArgs.add(q)
                selectionArgs.add(q)
            }

            if (filter != "all") {
                selectionClauses.add("(direction = ? OR status = ?)")
                selectionArgs.add(filter)
                selectionArgs.add(filter)
            }

            val selection = if (selectionClauses.isEmpty()) null else selectionClauses.joinToString(" AND ")
            val args = if (selectionArgs.isEmpty()) null else selectionArgs.toTypedArray()

            val cursor = db.query(
                "transfer_history",
                null,
                selection,
                args,
                null,
                null,
                "createdAtMillis DESC",
                "$offset, $limit"
            )

            val results = mutableListOf<TransferHistoryEntity>()
            cursor.use { c ->
                while (c.moveToNext()) {
                    results.add(c.toEntity())
                }
            }
            return results
        }

        override fun delete(id: Long) {
            writableDatabase.delete("transfer_history", "id = ?", arrayOf(id.toString()))
        }

        override fun clear() {
            writableDatabase.delete("transfer_history", null, null)
        }

        private fun Cursor.toEntity(): TransferHistoryEntity {
            return TransferHistoryEntity(
                id = getLong(getColumnIndexOrThrow("id")),
                fileName = getString(getColumnIndexOrThrow("fileName")) ?: "",
                filePath = getString(getColumnIndexOrThrow("filePath")) ?: "",
                fileSize = getLong(getColumnIndexOrThrow("fileSize")),
                fileType = getString(getColumnIndexOrThrow("fileType")) ?: "",
                senderDevice = getString(getColumnIndexOrThrow("senderDevice")) ?: "",
                receiverDevice = getString(getColumnIndexOrThrow("receiverDevice")) ?: "",
                remoteDevice = getString(getColumnIndexOrThrow("remoteDevice")) ?: "",
                remoteIp = getString(getColumnIndexOrThrow("remoteIp")) ?: "",
                direction = getString(getColumnIndexOrThrow("direction")) ?: "sent",
                status = getString(getColumnIndexOrThrow("status")) ?: "completed",
                speedBytesPerSecond = getDouble(getColumnIndexOrThrow("speedBytesPerSecond")),
                durationMillis = getLong(getColumnIndexOrThrow("durationMillis")),
                createdAtMillis = getLong(getColumnIndexOrThrow("createdAtMillis")),
                error = if (isNull(getColumnIndexOrThrow("error"))) null else getString(getColumnIndexOrThrow("error"))
            )
        }
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS transfer_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                fileName TEXT NOT NULL,
                filePath TEXT NOT NULL,
                fileSize INTEGER NOT NULL,
                fileType TEXT NOT NULL,
                senderDevice TEXT NOT NULL,
                receiverDevice TEXT NOT NULL,
                remoteDevice TEXT NOT NULL,
                remoteIp TEXT NOT NULL,
                direction TEXT NOT NULL,
                status TEXT NOT NULL,
                speedBytesPerSecond REAL NOT NULL,
                durationMillis INTEGER NOT NULL,
                createdAtMillis INTEGER NOT NULL,
                error TEXT
            )
            """.trimIndent()
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // No migration needed for v1
    }

    fun transferHistoryDao(): TransferHistoryDao = dao

    companion object {
        @Volatile private var instance: AppDatabase? = null

        fun get(context: Context): AppDatabase {
            return instance ?: synchronized(this) {
                instance ?: AppDatabase(context).also { instance = it }
            }
        }
    }
}
