import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:the_right_mix/game/frame_scripts.dart';
import 'package:the_right_mix/game/world.dart';
import 'package:the_right_mix/engine/engine.dart';

/// Reads assets straight from the project's `assets/` folder (no Flutter asset pipeline needed).
class DiskBundle extends CachingAssetBundle {
  final String root;
  DiskBundle(this.root);

  @override
  Future<ByteData> load(String key) async {
    final bytes = await File('$root/$key').readAsBytes();
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

/// Records every sound call so tests can assert on audio behaviour without playing anything.
class RecordingAudio implements AudioBackend {
  final List<String> log = [];
  final List<String> files = [];

  @override
  int load(String assetPath) {
    files.add(assetPath);
    return files.length - 1;
  }

  @override
  void play(int handle, {double offsetSeconds = 0, bool loop = false}) =>
      log.add('play ${files[handle]}${loop ? ' loop' : ''}');

  @override
  void stop(int handle) => log.add('stop ${files[handle]}');

  @override
  void setVolume(int handle, double volume01) {}
}

class Sim {
  final Stage stage;
  final RecordingAudio audio;
  final GameHost host;
  Sim(this.stage, this.audio, this.host);

  GameWorld get world => host.game!.world;

  static Future<Sim> create({math.Random? random}) async {
    final lib = await Library.load(DiskBundle('.'));
    final audio = RecordingAudio();
    final stage = Stage(lib, audio);
    final host = GameHost(random ?? math.Random(1));
    registerFrameScripts(stage, host);
    stage.start();
    return Sim(stage, audio, host);
  }

  /// First stage point (scanning the stage) whose topmost interactive object is [target].
  ui.Offset? findHit(Object target) {
    for (var y = 0.0; y < 440; y += 3) {
      for (var x = 0.0; x < 600; x += 3) {
        if (identical(stage.root.hitInteractive(ui.Offset(x, y)), target)) return ui.Offset(x, y);
      }
    }
    return null;
  }

  void ticks(int n) {
    for (var i = 0; i < n; i++) {
      stage.tick();
    }
  }

  void press(double x, double y) => stage.pointerDown(ui.Offset(x, y));
  void release(double x, double y) => stage.pointerUp(ui.Offset(x, y), leaves: false);
  void move(double x, double y) => stage.pointerMove(ui.Offset(x, y));

  void click(double x, double y, {int hold = 2}) {
    move(x, y);
    press(x, y);
    ticks(hold);
    release(x, y);
  }

  /// Render the current stage to a PNG (2x scale).
  Future<Uint8List> snapshot({double scale = 1, double blend = 1}) async {
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    final size = ui.Size(600 * scale, 440 * scale);
    stage.paint(canvas, size, blend: blend);
    final img = await rec.endRecording().toImage(size.width.toInt(), size.height.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  Future<void> save(String name) async {
    final dir = Directory('../work/snapshots')..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(await snapshot());
  }
}
