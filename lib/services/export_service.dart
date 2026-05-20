import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/timer_string.dart';

class ExportService {
  Future<File> writeStringCsv(TimerString s) async {
    final dir = await getTemporaryDirectory();
    final filename = 'string_${s.id ?? 'draft'}_${s.createdAt.millisecondsSinceEpoch}.csv';
    final file = File(p.join(dir.path, filename));
    final buffer = StringBuffer()
      ..writeln('shot,cycle,time_s,split_s,manual')
      ..writeln(
        '# created_at=${s.createdAt.toIso8601String()} '
        'mode=${s.drillMode.name} '
        'delay_used_ms=${s.delayUsedMs} '
        'penalty_ms=${s.penaltyMs}',
      );
    for (var i = 0; i < s.shots.length; i++) {
      final shot = s.shots[i];
      // Splits only make sense within a cycle — across cycles the times reset.
      final prev = i == 0 ? null : s.shots[i - 1];
      final sameCycle = prev != null && prev.cycleIndex == shot.cycleIndex;
      final split = sameCycle ? shot.timeMs - prev.timeMs : 0;
      buffer.writeln(
        '${i + 1},'
        '${shot.cycleIndex},'
        '${(shot.timeMs / 1000).toStringAsFixed(3)},'
        '${(split / 1000).toStringAsFixed(3)},'
        '${shot.manual ? 1 : 0}',
      );
    }
    await file.writeAsString(buffer.toString());
    return file;
  }

  Future<File> writeAllStringsCsv(List<TimerString> strings) async {
    final dir = await getTemporaryDirectory();
    final filename =
        'simple_shot_timer_export_${DateTime.now().millisecondsSinceEpoch}.csv';
    final file = File(p.join(dir.path, filename));
    final buffer = StringBuffer()
      ..writeln(
        'string_id,created_at,drill_mode,delay_mode,delay_used_ms,'
        'shot_index,cycle,time_s,split_s,manual,penalty_ms,label,notes',
      );
    for (final s in strings) {
      for (var i = 0; i < s.shots.length; i++) {
        final shot = s.shots[i];
        final prev = i == 0 ? null : s.shots[i - 1];
        final sameCycle = prev != null && prev.cycleIndex == shot.cycleIndex;
        final split = sameCycle ? shot.timeMs - prev.timeMs : 0;
        buffer.writeln(
          '${s.id},${s.createdAt.toIso8601String()},'
          '${s.drillMode.name},${s.delayMode.name},${s.delayUsedMs},'
          '${i + 1},${shot.cycleIndex},'
          '${(shot.timeMs / 1000).toStringAsFixed(3)},'
          '${(split / 1000).toStringAsFixed(3)},'
          '${shot.manual ? 1 : 0},${s.penaltyMs},'
          '${_csv(s.label)},${_csv(s.notes)}',
        );
      }
    }
    await file.writeAsString(buffer.toString());
    return file;
  }

  Future<void> share(File file, {String? subject}) async {
    await Share.shareXFiles([XFile(file.path)], subject: subject);
  }

  String _csv(String? s) {
    if (s == null || s.isEmpty) return '';
    final escaped = s.replaceAll('"', '""');
    return '"$escaped"';
  }
}
