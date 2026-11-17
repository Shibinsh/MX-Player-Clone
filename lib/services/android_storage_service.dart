import 'package:flutter/services.dart';

class AndroidStorageService {
  static const MethodChannel _channel =
      MethodChannel('mx_player_clone/storage');

  Future<List<String>> removableStoragePaths() async {
    try {
      final result = await _channel.invokeListMethod<String>('sdCardPaths');
      return result ?? const [];
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, Object?>>> videoFolders() async {
    try {
      final result = await _channel.invokeListMethod<dynamic>('videoFolders');
      if (result == null) return const [];
      return result
          .whereType<Map>()
          .map((item) => Map<String, Object?>.from(item))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, Object?>>> audioFiles() async {
    try {
      final result = await _channel.invokeListMethod<dynamic>('audioFiles');
      if (result == null) return const [];
      return result
          .whereType<Map>()
          .map((item) => Map<String, Object?>.from(item))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
