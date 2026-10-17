import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// The sound files must be Flash-accurate: encoder delay removed, envelope variants present and referenced.
void main() {
  Map<String, dynamic> readWav(String path) {
    final b = ByteData.sublistView(File(path).readAsBytesSync());
    final ch = b.getUint16(22, Endian.little);
    final rate = b.getUint32(24, Endian.little);
    var q = 12, dataAt = -1, dataLen = 0;
    while (q + 8 <= b.lengthInBytes) {
      final id = String.fromCharCodes([for (var i = 0; i < 4; i++) b.getUint8(q + i)]);
      final len = b.getUint32(q + 4, Endian.little);
      if (id == 'data') {
        dataAt = q + 8;
        dataLen = len;
        break;
      }
      q += 8 + len;
    }
    return {'ch': ch, 'rate': rate, 'at': dataAt, 'len': dataLen, 'b': b};
  }

  /// Milliseconds until the signal first exceeds 2% of its peak.
  double leadMs(String path) {
    final w = readWav(path);
    final b = w['b'] as ByteData;
    final n = (w['len'] as int) ~/ 2;
    var peak = 0;
    for (var i = 0; i < n; i++) {
      final v = b.getInt16((w['at'] as int) + 2 * i, Endian.little).abs();
      if (v > peak) peak = v;
    }
    var i = 0;
    while (i < n && b.getInt16((w['at'] as int) + 2 * i, Endian.little).abs() < peak * 0.02) {
      i++;
    }
    return 1000 * (i / (w['ch'] as int)) / (w['rate'] as int);
  }

  test('11 kHz sounds start within 60 ms of audible signal (no 150 ms MP3 padding)', () {
    // 2 = music loop, 150/171/235 = finale effects: authored without a lead-in. The padding used to be 150 ms.
    for (final id in [1, 2, 150, 171, 192, 235, 256]) {
      expect(leadMs('assets/sounds/$id.wav'), lessThan(60), reason: 'sound $id');
    }
  });

  test('every referenced sound file exists; envelope variants are referenced by cues', () {
    final doc = jsonDecode(File('assets/game.json').readAsStringSync()) as Map<String, dynamic>;
    final files = <String>{};
    void cues(List frames) {
      for (final f in frames) {
        for (final c in (f['snd'] ?? const []) as List) {
          if (c['f'] != null) files.add(c['f'] as String);
          expect(c.containsKey('env'), isFalse);
        }
      }
    }

    cues(doc['main'] as List);
    for (final c in (doc['chars'] as Map).values) {
      if (c['k'] == 'sprite') cues(c['frames'] as List);
      if (c['k'] == 'sound') {
        expect(File('assets/${c['file']}').existsSync(), isTrue, reason: c['file'] as String);
      }
    }
    expect(files.length, 8);
    for (final f in files) {
      expect(File('assets/$f').existsSync(), isTrue, reason: f);
    }
  });
}
