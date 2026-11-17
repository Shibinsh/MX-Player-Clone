package com.example.mx_player_clone

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.storage.StorageManager
import android.os.storage.StorageVolume
import android.provider.MediaStore
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.BufferedReader
import java.io.FileReader
import java.util.concurrent.Executors

class MainActivity : FlutterFragmentActivity() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val thumbnailExecutor = Executors.newFixedThreadPool(3)
    private val mediaExecutor = Executors.newSingleThreadExecutor()
    private val historyDao by lazy { AppDatabase.get(this).transferHistoryDao() }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "mx_player_clone/storage"
        ).setMethodCallHandler { call, result ->
            if (call.method == "sdCardPaths") {
                mediaExecutor.execute {
                    val paths = sdCardPaths()
                    mainHandler.post { result.success(paths) }
                }
            } else if (call.method == "videoFolders") {
                mediaExecutor.execute {
                    val folders = videoFolders()
                    mainHandler.post { result.success(folders) }
                }
            } else if (call.method == "audioFiles") {
                mediaExecutor.execute {
                    val audios = audioFiles()
                    mainHandler.post { result.success(audios) }
                }
            } else if (call.method == "videoThumbnail") {
                val path = call.argument<String>("path")
                thumbnailExecutor.execute {
                    val thumbnail = videoThumbnail(path)
                    mainHandler.post {
                        result.success(thumbnail)
                    }
                }
            } else if (call.method == "insertTransferHistory") {
                val args = call.arguments as? Map<*, *>
                mediaExecutor.execute {
                    val id = insertTransferHistory(args)
                    mainHandler.post { result.success(id) }
                }
            } else if (call.method == "listTransferHistory") {
                val query = call.argument<String>("query") ?: ""
                val filter = call.argument<String>("filter") ?: "all"
                val limit = call.argument<Int>("limit") ?: 80
                val offset = call.argument<Int>("offset") ?: 0
                mediaExecutor.execute {
                    val rows = historyDao.page(query, filter, limit, offset).map { it.toMap() }
                    mainHandler.post { result.success(rows) }
                }
            } else if (call.method == "deleteTransferHistory") {
                val id = call.argument<Long>("id") ?: (call.argument<Int>("id")?.toLong() ?: 0L)
                mediaExecutor.execute {
                    historyDao.delete(id)
                    mainHandler.post { result.success(true) }
                }
            } else if (call.method == "clearTransferHistory") {
                mediaExecutor.execute {
                    historyDao.clear()
                    mainHandler.post { result.success(true) }
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun insertTransferHistory(args: Map<*, *>?): Long {
        if (args == null) return 0L
        val item = TransferHistoryEntity(
            fileName = args["fileName"] as? String ?: "",
            filePath = args["filePath"] as? String ?: "",
            fileSize = (args["fileSize"] as? Number)?.toLong() ?: 0L,
            fileType = args["fileType"] as? String ?: "",
            senderDevice = args["senderDevice"] as? String ?: "",
            receiverDevice = args["receiverDevice"] as? String ?: "",
            remoteDevice = args["remoteDevice"] as? String ?: "",
            remoteIp = args["remoteIp"] as? String ?: "",
            direction = args["direction"] as? String ?: "sent",
            status = args["status"] as? String ?: "completed",
            speedBytesPerSecond = (args["speedBytesPerSecond"] as? Number)?.toDouble() ?: 0.0,
            durationMillis = (args["durationMillis"] as? Number)?.toLong() ?: 0L,
            createdAtMillis = (args["createdAtMillis"] as? Number)?.toLong()
                ?: System.currentTimeMillis(),
            error = args["error"] as? String
        )
        return historyDao.insert(item)
    }

    private fun sdCardPaths(): List<String> {
        val paths = linkedSetOf<String>()
        val storageManager = getSystemService(StorageManager::class.java)
        val volumes: List<StorageVolume> = storageManager.storageVolumes
        for (volume in volumes) {
            if (!volume.isRemovable) continue
            val directory: File? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                volume.directory
            } else {
                storageVolumePath(volume)
            }
            if (directory != null) {
                paths.add(directory.absolutePath)
                continue
            }

            val uuid = volume.uuid
            if (!uuid.isNullOrBlank()) {
                paths.add("/storage/$uuid")
            }
        }
        paths.addAll(storageDirectoryCandidates())
        paths.addAll(mountCandidates())
        return paths.toList()
    }

    private fun TransferHistoryEntity.toMap(): Map<String, Any?> {
        return mapOf(
            "id" to id,
            "fileName" to fileName,
            "filePath" to filePath,
            "fileSize" to fileSize,
            "fileType" to fileType,
            "senderDevice" to senderDevice,
            "receiverDevice" to receiverDevice,
            "remoteDevice" to remoteDevice,
            "remoteIp" to remoteIp,
            "direction" to direction,
            "status" to status,
            "speedBytesPerSecond" to speedBytesPerSecond,
            "durationMillis" to durationMillis,
            "createdAtMillis" to createdAtMillis,
            "error" to error
        )
    }

    private fun storageVolumePath(volume: StorageVolume): File? {
        return try {
            val method = StorageVolume::class.java.getDeclaredMethod("getPathFile")
            method.isAccessible = true
            method.invoke(volume) as? File
        } catch (_: Exception) {
            try {
                val method = StorageVolume::class.java.getDeclaredMethod("getPath")
                method.isAccessible = true
                val path = method.invoke(volume) as? String
                if (path.isNullOrBlank()) null else File(path)
            } catch (_: Exception) {
                null
            }
        }
    }

    private fun storageDirectoryCandidates(): List<String> {
        val result = mutableListOf<String>()
        val storage = File("/storage")
        val children = storage.listFiles() ?: return result
        val regex = Regex("^[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}$")
        for (child in children) {
            if (child.isDirectory && regex.matches(child.name)) {
                result.add(child.absolutePath)
            }
        }
        return result
    }

    private fun mountCandidates(): List<String> {
        val result = mutableListOf<String>()
        val regex = Regex("/storage/[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}")
        try {
            BufferedReader(FileReader("/proc/mounts")).useLines { lines ->
                lines.forEach { line ->
                    regex.findAll(line).forEach { match ->
                        result.add(match.value)
                    }
                }
            }
        } catch (_: Exception) {
        }
        return result
    }

    private fun videoFolders(): List<Map<String, Any>> {
        val folders = linkedMapOf<String, MutableMap<String, Any>>()
        val projection = arrayOf(
            MediaStore.Video.Media.DATA,
            MediaStore.Video.Media.DATE_MODIFIED
        )
        val sortOrder = "${MediaStore.Video.Media.DATE_MODIFIED} DESC"
        try {
            contentResolver.query(
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                projection,
                null,
                null,
                sortOrder
            )?.use { cursor ->
                val dataIndex = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DATA)
                val dateIndex = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DATE_MODIFIED)
                while (cursor.moveToNext()) {
                    val filePath = cursor.getString(dataIndex) ?: continue
                    val parent = File(filePath).parentFile ?: continue
                    if (!parent.exists()) continue
                    val folderPath = parent.absolutePath
                    val modifiedAt = cursor.getLong(dateIndex) * 1000L
                    val current = folders[folderPath]
                    if (current == null) {
                        folders[folderPath] = mutableMapOf(
                            "path" to folderPath,
                            "name" to parent.name,
                            "count" to 1,
                            "modifiedAt" to modifiedAt
                        )
                    } else {
                        current["count"] = (current["count"] as Int) + 1
                        if (modifiedAt > current["modifiedAt"] as Long) {
                            current["modifiedAt"] = modifiedAt
                        }
                    }
                }
            }
        } catch (_: Exception) {
        }
        return folders.values.toList()
    }

    private fun audioFiles(): List<Map<String, Any>> {
        val audios = mutableListOf<Map<String, Any>>()
        val projection = arrayOf(
            MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.DATE_MODIFIED,
            MediaStore.Audio.Media.SIZE
        )
        val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0"
        val sortOrder = "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC"
        try {
            contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                projection,
                selection,
                null,
                sortOrder
            )?.use { cursor ->
                val dataIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
                val titleIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
                val artistIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
                val albumIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
                val durationIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
                val dateIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_MODIFIED)
                val sizeIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)
                while (cursor.moveToNext()) {
                    val path = cursor.getString(dataIndex) ?: continue
                    val file = File(path)
                    if (!file.exists() || !file.isFile) continue
                    val title = cursor.getString(titleIndex)?.takeIf { it.isNotBlank() }
                        ?: file.nameWithoutExtension
                    val artist = cursor.getString(artistIndex)
                        ?.takeIf { it.isNotBlank() && it != "<unknown>" }
                    val album = cursor.getString(albumIndex)
                        ?.takeIf { it.isNotBlank() && it != "<unknown>" }
                    val folder = file.parentFile?.name?.takeIf { it.isNotBlank() }
                    audios.add(
                        mapOf(
                            "id" to path,
                            "title" to title,
                            "path" to path,
                            "artist" to (artist ?: ""),
                            "album" to (album ?: ""),
                            "folder" to (folder ?: ""),
                            "duration" to cursor.getLong(durationIndex),
                            "modifiedAt" to cursor.getLong(dateIndex) * 1000L,
                            "sizeBytes" to cursor.getLong(sizeIndex)
                        )
                    )
                }
            }
        } catch (_: Exception) {
        }
        return audios
    }

    private fun videoThumbnail(path: String?): ByteArray? {
        if (path.isNullOrBlank()) return null
        val file = File(path)
        if (!file.exists() || !file.isFile) return null

        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            val bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                retriever.getScaledFrameAtTime(
                    1_000_000,
                    MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                    180,
                    104
                )
            } else {
                retriever.getFrameAtTime(
                    1_000_000,
                    MediaMetadataRetriever.OPTION_CLOSEST_SYNC
                )
            } ?: return null

            ByteArrayOutputStream().use { stream ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, 62, stream)
                bitmap.recycle()
                stream.toByteArray()
            }
        } catch (_: Exception) {
            null
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
            }
        }
    }
}
