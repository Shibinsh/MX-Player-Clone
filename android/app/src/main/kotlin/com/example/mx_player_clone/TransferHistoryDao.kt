package com.example.mx_player_clone

interface TransferHistoryDao {
    fun insert(item: TransferHistoryEntity): Long
    fun page(query: String, filter: String, limit: Int, offset: Int): List<TransferHistoryEntity>
    fun delete(id: Long)
    fun clear()
}
