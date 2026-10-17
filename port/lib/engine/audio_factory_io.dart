import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

import 'audio.dart';

AudioBackend? createPlatformAudio() {
  try {
    if (Platform.environment['RIGHTMIX_MUTE'] == '1') return null; // silent run (automated tests)
    if (Platform.isWindows) return WindowsAudio();
    if (Platform.isAndroid) return AndroidAudio();
  } catch (_) {}
  return null;
}

/// Windows: `rightmix_audio.dll` (miniaudio, see windows/audio/) next to the executable.
class WindowsAudio implements AudioBackend {
  late final DynamicLibrary _lib;
  late final int Function() _init;
  late final int Function(Pointer<Utf16>) _load;
  late final void Function(int, double, int) _play;
  late final void Function(int) _stop;
  late final void Function(int, double) _volume;
  late final int Function(int) _isPlaying;
  late final double Function() _latencyMs;
  final String _assetRoot;

  /// [assetRoot] defaults to the `assets` folder shipped next to the executable;
  /// [libraryPath] to the DLL next to the executable.
  WindowsAudio({String? assetRoot, String? libraryPath})
      : _assetRoot = assetRoot ??
            '${File(Platform.resolvedExecutable).parent.path}\\data\\flutter_assets\\assets\\' {
    _lib = DynamicLibrary.open(libraryPath ?? 'rightmix_audio.dll');
    _init = _lib.lookupFunction<Int32 Function(), int Function()>('ra_init');
    _load = _lib.lookupFunction<Int32 Function(Pointer<Utf16>), int Function(Pointer<Utf16>)>('ra_load');
    _play = _lib.lookupFunction<Void Function(Int32, Double, Int32), void Function(int, double, int)>('ra_play');
    _stop = _lib.lookupFunction<Void Function(Int32), void Function(int)>('ra_stop');
    _volume = _lib.lookupFunction<Void Function(Int32, Float), void Function(int, double)>('ra_volume');
    _isPlaying = _lib.lookupFunction<Int32 Function(Int32), int Function(int)>('ra_is_playing');
    _latencyMs = _lib.lookupFunction<Double Function(), double Function()>('ra_latency_ms');
    if (_init() != 0) throw StateError('audio device unavailable');
  }

  @override
  int load(String assetPath) {
    final p = '$_assetRoot${assetPath.replaceAll('/', '\\')}'.toNativeUtf16();
    final h = _load(p);
    malloc.free(p);
    return h;
  }

  @override
  void play(int handle, {double offsetSeconds = 0, bool loop = false}) {
    if (handle >= 0) _play(handle, offsetSeconds, loop ? 1 : 0);
  }

  @override
  void stop(int handle) {
    if (handle >= 0) _stop(handle);
  }

  @override
  void setVolume(int handle, double volume01) {
    if (handle >= 0) _volume(handle, volume01.clamp(0.0, 1.0));
  }

  /// Output buffering of the mixer in milliseconds (diagnostics).
  double get latencyMs => _latencyMs();

  /// Diagnostics / tests.
  bool isPlaying(int handle) => handle >= 0 && _isPlaying(handle) != 0;
}

/// Android: a MediaPlayer wrapper in MainActivity.kt, reached over a method channel.
class AndroidAudio implements AudioBackend {
  static const MethodChannel _ch = MethodChannel('org.decomp.therightmix/audio');
  int _next = 1;

  @override
  int load(String assetPath) {
    final id = _next++;
    _ch.invokeMethod('load', {'id': id, 'path': 'flutter_assets/assets/$assetPath'});
    return id;
  }

  @override
  void play(int handle, {double offsetSeconds = 0, bool loop = false}) {
    if (handle < 0) return;
    _ch.invokeMethod('play', {'id': handle, 'offsetMs': (offsetSeconds * 1000).round(), 'loop': loop});
  }

  @override
  void stop(int handle) {
    if (handle < 0) return;
    _ch.invokeMethod('stop', {'id': handle});
  }

  @override
  void setVolume(int handle, double volume01) {
    if (handle < 0) return;
    _ch.invokeMethod('volume', {'id': handle, 'v': volume01.clamp(0.0, 1.0)});
  }
}
