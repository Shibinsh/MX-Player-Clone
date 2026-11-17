import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

class TransferHistoryRecord {
  const TransferHistoryRecord({
    required this.id,
    required this.fileName,
    required this.filePath,
    required this.fileSize,
    required this.fileType,
    required this.senderDevice,
    required this.receiverDevice,
    required this.remoteDevice,
    required this.remoteIp,
    required this.direction,
    required this.status,
    required this.speedBytesPerSecond,
    required this.duration,
    required this.createdAt,
    this.error,
  });

  final int id;
  final String fileName;
  final String filePath;
  final int fileSize;
  final String fileType;
  final String senderDevice;
  final String receiverDevice;
  final String remoteDevice;
  final String remoteIp;
  final String direction;
  final String status;
  final double speedBytesPerSecond;
  final Duration duration;
  final DateTime createdAt;
  final String? error;

  factory TransferHistoryRecord.fromMap(Map<dynamic, dynamic> map) {
    return TransferHistoryRecord(
      id: (map['id'] as num?)?.toInt() ?? 0,
      fileName: map['fileName'] as String? ?? '',
      filePath: map['filePath'] as String? ?? '',
      fileSize: (map['fileSize'] as num?)?.toInt() ?? 0,
      fileType: map['fileType'] as String? ?? '',
      senderDevice: map['senderDevice'] as String? ?? '',
      receiverDevice: map['receiverDevice'] as String? ?? '',
      remoteDevice: map['remoteDevice'] as String? ?? '',
      remoteIp: map['remoteIp'] as String? ?? '',
      direction: map['direction'] as String? ?? '',
      status: map['status'] as String? ?? '',
      speedBytesPerSecond:
          (map['speedBytesPerSecond'] as num?)?.toDouble() ?? 0,
      duration:
          Duration(milliseconds: (map['durationMillis'] as num?)?.toInt() ?? 0),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['createdAtMillis'] as num?)?.toInt() ?? 0,
      ),
      error: map['error'] as String?,
    );
  }
}

class TransferHistoryDraft {
  const TransferHistoryDraft({
    required this.fileName,
    required this.filePath,
    required this.fileSize,
    required this.senderDevice,
    required this.receiverDevice,
    required this.remoteDevice,
    required this.remoteIp,
    required this.direction,
    required this.status,
    required this.speedBytesPerSecond,
    required this.duration,
    required this.createdAt,
    this.error,
  });

  final String fileName;
  final String filePath;
  final int fileSize;
  final String senderDevice;
  final String receiverDevice;
  final String remoteDevice;
  final String remoteIp;
  final String direction;
  final String status;
  final double speedBytesPerSecond;
  final Duration duration;
  final DateTime createdAt;
  final String? error;

  Map<String, Object?> toMap() {
    return {
      'fileName': fileName,
      'filePath': filePath,
      'fileSize': fileSize,
      'fileType': p.extension(fileName).replaceFirst('.', '').toUpperCase(),
      'senderDevice': senderDevice,
      'receiverDevice': receiverDevice,
      'remoteDevice': remoteDevice,
      'remoteIp': remoteIp,
      'direction': direction,
      'status': status,
      'speedBytesPerSecond': speedBytesPerSecond,
      'durationMillis': duration.inMilliseconds,
      'createdAtMillis': createdAt.millisecondsSinceEpoch,
      'error': error,
    };
  }
}

class TransferHistoryService {
  static const MethodChannel _channel =
      MethodChannel('mx_player_clone/storage');

  Future<void> insert(TransferHistoryDraft draft) async {
    await _channel.invokeMethod<int>('insertTransferHistory', draft.toMap());
  }

  Future<List<TransferHistoryRecord>> page({
    String query = '',
    String filter = 'all',
    int limit = 80,
    int offset = 0,
  }) async {
    final rows = await _channel.invokeListMethod<dynamic>(
      'listTransferHistory',
      {
        'query': query,
        'filter': filter,
        'limit': limit,
        'offset': offset,
      },
    );
    return (rows ?? const [])
        .whereType<Map>()
        .map(TransferHistoryRecord.fromMap)
        .toList();
  }

  Future<void> delete(int id) async {
    await _channel.invokeMethod<bool>('deleteTransferHistory', {'id': id});
  }

  Future<void> clear() async {
    await _channel.invokeMethod<bool>('clearTransferHistory');
  }

  Future<bool> exists(TransferHistoryRecord record) {
    if (record.filePath.isEmpty) return Future.value(false);
    return File(record.filePath).exists();
  }
}
