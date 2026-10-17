import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

RandomAccessFile? _notes;
bool _androidLog = false;
final List<String> _pendingNotes = [];

/// Diagnostics (frame-time measurements). On Windows, when RIGHTMIX_FRAMELOG names a file, every frame's build and
/// raster time is appended to it as `buildMs rasterMs totalMs`, with `<file>.notes` holding what the game was doing in the
/// same order. On Android (TRACE builds) every frame is printed to the log as `RM ft raster=.. total=.. <note>`.
bool get frameLogEnabled => _notes != null || _androidLog;

void frameNote(String text) {
  if (_notes != null) {
    _notes!.writeStringSync('$text\n');
  } else if (_androidLog) {
    _pendingNotes.add(text);
  }
}

void startFrameLog() {
  final path = Platform.environment['RIGHTMIX_FRAMELOG'];
  if (path != null && path.isNotEmpty) {
    _notes = File('$path.notes').openSync(mode: FileMode.write);
    final sink = File(path).openSync(mode: FileMode.write);
    SchedulerBinding.instance.addTimingsCallback((timings) {
      for (final t in timings) {
        sink.writeStringSync('${t.buildDuration.inMicroseconds / 1000} ${t.rasterDuration.inMicroseconds / 1000} '
            '${t.totalSpan.inMicroseconds / 1000}\n');
      }
      sink.flushSync();
    });
  } else if (Platform.isAndroid && const bool.fromEnvironment('TRACE') && const bool.fromEnvironment('FRAMELOG')) {
    _androidLog = true;
    SchedulerBinding.instance.addTimingsCallback((timings) {
      for (final t in timings) {
        final note = _pendingNotes.isEmpty ? '' : _pendingNotes.removeAt(0);
        debugPrint('RM ft raster=${(t.rasterDuration.inMicroseconds / 1000).toStringAsFixed(1)} '
            'total=${(t.totalSpan.inMicroseconds / 1000).toStringAsFixed(1)} $note');
      }
    });
  }
}
