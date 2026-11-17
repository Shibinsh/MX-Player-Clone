import 'dart:io';

import '../models/subtitle_cue.dart';

class SubtitleService {
  static Future<List<SubtitleCue>> loadSrt(File file) async {
    if (!await file.exists()) return const [];
    final content = await file.readAsString();
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final blocks = normalized.split(RegExp(r'\n{2,}'));
    final cues = <SubtitleCue>[];

    for (final block in blocks) {
      final lines = block
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      if (lines.length < 2) continue;

      final timeIndex = lines.indexWhere((line) => line.contains('-->'));
      if (timeIndex == -1 || timeIndex + 1 >= lines.length) continue;

      final times = lines[timeIndex].split('-->');
      if (times.length != 2) continue;

      final start = _parseTimestamp(times[0].trim());
      final end = _parseTimestamp(times[1].trim());
      if (start == null || end == null) continue;

      cues.add(
        SubtitleCue(
          start: start,
          end: end,
          text: lines.sublist(timeIndex + 1).join('\n'),
        ),
      );
    }

    cues.sort((a, b) => a.start.compareTo(b.start));
    return cues;
  }

  static Duration? _parseTimestamp(String input) {
    final match = RegExp(
      r'^(\d{2}):(\d{2}):(\d{2})[,.](\d{1,3})',
    ).firstMatch(input);
    if (match == null) return null;

    final hours = int.parse(match.group(1)!);
    final minutes = int.parse(match.group(2)!);
    final seconds = int.parse(match.group(3)!);
    final millisText = match.group(4)!.padRight(3, '0');
    final milliseconds = int.parse(millisText);

    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: milliseconds,
    );
  }
}
