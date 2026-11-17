package com.example.mx_player_clone

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query

@Dao
interface TransferHistoryDao {
    @Insert
    fun insert(item: TransferHistoryEntity): Long

    @Query(
        """
        SELECT * FROM transfer_history
        WHERE (:query = '' OR fileName LIKE '%' || :query || '%' OR remoteDevice LIKE '%' || :query || '%' OR remoteIp LIKE '%' || :query || '%')
        AND (:filter = 'all' OR direction = :filter OR status = :filter)
        ORDER BY createdAtMillis DESC
        LIMIT :limit OFFSET :offset
        """
    )
    fun page(query: String, filter: String, limit: Int, offset: Int): List<TransferHistoryEntity>

    @Query("DELETE FROM transfer_history WHERE id = :id")
    fun delete(id: Long)

    @Query("DELETE FROM transfer_history")
    fun clear()
}
