import 'definitions.dart';
import 'library.dart';
import 'audio_factory_stub.dart' if (dart.library.io) 'audio_factory_io.dart';

/// Minimal sound output used by the Flash runtime. Handles are opaque ints.
abstract class AudioBackend {
  /// Prepare an MP3 that ships as `assets/<assetPath>`; returns a handle (or -1 when unavailable).
  int load(String assetPath);
  void play(int handle, {double offsetSeconds = 0, bool loop = false});
  void stop(int handle);
  void setVolume(int handle, double volume01);

  /// Picks the native backend for the current platform (silent where none exists, e.g. web).
  static AudioBackend create() => createPlatformAudio() ?? NullAudio();
}

class NullAudio implements AudioBackend {
  int _n = 0;
  @override
  int load(String assetPath) => _n++;
  @override
  void play(int handle, {double offsetSeconds = 0, bool loop = false}) {}
  @override
  void stop(int handle) {}
  @override
  void setVolume(int handle, double volume01) {}
}

/// ActionScript `Sound` object: one attached sound with its own volume.
class SoundObject {
  final AudioBackend _backend;
  final Library _lib;
  int _handle = -1;
  int _volume = 100;

  SoundObject(this._backend, this._lib);

  void attachSound(String linkage) {
    final id = _lib.idByLinkage(linkage);
    final def = id == null ? null : _lib.chars[id];
    if (def is SoundDef) {
      _handle = _backend.load(def.file);
      _backend.setVolume(_handle, _volume / 100);
    }
  }

  /// Sound.start(secondOffset, loops)
  void start([double secondOffset = 0, int loops = 1]) {
    _backend.setVolume(_handle, _volume / 100);
    _backend.play(_handle, offsetSeconds: secondOffset, loop: loops > 1);
  }

  void stop() => _backend.stop(_handle);

  void setVolume(int v) {
    _volume = v.clamp(0, 100);
    _backend.setVolume(_handle, _volume / 100);
  }

  int getVolume() => _volume;
}

/// Sounds triggered from timelines (`StartSound` tags).
class SoundHub {
  final AudioBackend backend;
  final Map<String, int> _handles = {};
  SoundHub(this.backend);

  /// Handles per sound id: the sound's own file plus any envelope variants, so a "stop" cue silences all of them.
  final Map<int, Set<int>> _bySound = {};

  void playCue(Library lib, int soundId, int loops, bool stopFlag, [String? file]) {
    final def = lib.chars[soundId];
    if (def is! SoundDef) return;
    if (stopFlag) {
      for (final h in _bySound[soundId] ?? const <int>{}) {
        backend.stop(h);
      }
      return;
    }
    final path = file ?? def.file;
    final h = _handles.putIfAbsent(path, () {
      final handle = backend.load(path);
      _bySound.putIfAbsent(soundId, () => {}).add(handle);
      return handle;
    });
    backend.setVolume(h, 1.0);
    backend.play(h, loop: loops > 1);
  }
}
