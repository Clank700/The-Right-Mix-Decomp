import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:the_right_mix/engine/audio_factory_io.dart';

/// Needs a prior `flutter build windows` (provides rightmix_audio.dll).
void main() {
  test('Windows audio backend loads and plays the shipped sounds', () async {
    if (!Platform.isWindows) return;
    final dll = '${Directory.current.path}\\build\\windows\\x64\\runner\\Release\\rightmix_audio.dll';
    if (!File(dll).existsSync()) return;
    final audio = WindowsAudio(assetRoot: '${Directory.current.path}\\assets\\', libraryPath: dll);
    final h = audio.load('sounds/2.wav'); // musicLoop
    expect(h, greaterThanOrEqualTo(0), reason: 'decoding the MP3 should succeed');
    // ignore: avoid_print
    print('Windows mixer buffering: ${audio.latencyMs.toStringAsFixed(1)} ms');
    expect(audio.latencyMs, inInclusiveRange(1, 60));
    audio.setVolume(h, 0.0);
    audio.play(h, loop: true);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(audio.isPlaying(h), isTrue);
    audio.stop(h);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(audio.isPlaying(h), isFalse);
  });
}
