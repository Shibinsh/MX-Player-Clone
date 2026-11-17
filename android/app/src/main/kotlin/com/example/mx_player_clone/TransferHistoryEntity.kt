package com.example.mx_player_clone

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "transfer_history")
data class TransferHistoryEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val fileName: String,
    val filePath: String,
    val fileSize: Long,
    val fileType: String,
    val senderDevice: String,
    val receiverDevice: String,
    val remoteDevice: String,
    val remoteIp: String,
    val direction: String,
    val status: String,
    val speedBytesPerSecond: Double,
    val durationMillis: Long,
    val createdAtMillis: Long,
    val error: String?
)
