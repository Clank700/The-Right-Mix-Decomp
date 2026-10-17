import 'dart:math' as math;
import 'dart:ui' as ui;

import 'audio.dart';
import 'fill_cache.dart';
import 'view_layout.dart';
import 'color_transform.dart';
import 'library.dart';
import 'nodes/button_node.dart';
import 'nodes/movie_clip.dart';
import 'nodes/node.dart';

/// Equivalent of `Mouse.addListener(obj)` with onMouseDown / onMouseUp.
class MouseListener {
  void Function()? onMouseDown;
  void Function()? onMouseUp;
}

typedef FrameScript = void Function(MovieClip clip);

/// Owns the display list root, the 18 fps tick, mouse routing and sound.
class Stage {
  final Library lib;
  final AudioBackend backend;
  late final SoundHub audio = SoundHub(backend);
  late final MovieClip root;

  /// Scripts that the original SWF attached to timeline frames, keyed `spriteId:frame` (0 = main timeline).
  final Map<String, FrameScript> frameScripts = {};

  /// `on(release)` actions of DefineButton2 symbols by character id.
  final Map<int, void Function(ButtonNode self)> _buttonActions = {};

  final List<MouseListener> _mouseListeners = [];

  Node? hovered;
  Node? pressed;
  ui.Offset mouse = ui.Offset.zero;
  int frameCount = 0;

  /// Debug aid: ignore every timeline script (including bare `stop()`), like a plain SWF renderer.
  bool ignoreFrameScripts = false;


  Stage(this.lib, this.backend) {
    root = MovieClip(lib, lib.main, stage: this, deferInit: true);
  }

  void Function(ButtonNode self)? buttonAction(int id) => _buttonActions[id];
  void setButtonAction(int id, void Function(ButtonNode self) fn) => _buttonActions[id] = fn;

  void registerFrameScript(int spriteId, int frame, FrameScript fn) => frameScripts['$spriteId:$frame'] = fn;

  void runFrameScript(MovieClip clip, int spriteId, int frame) => frameScripts['$spriteId:$frame']?.call(clip);

  /// `onClipEvent(load)` handlers present in the SWF (both just hide the clip).
  void applyClipLoad(MovieClip clip, int parentSpriteId, String name) {
    if (name == 'tandc' || name == 'credits') clip.visible = false;
  }

  void addMouseListener(MouseListener l) => _mouseListeners.add(l);

  /// Start the main timeline (runs the frame-1 script that boots the game).
  void start() => root.initTimeline();

  // ---- frame loop ------------------------------------------------------------------------------
  /// One 1/18 s step (see [MovieClip.tickFrame] for the order inside it).
  void tick() {
    frameCount++;
    root.snapshotForBlend();
    root.tickFrame();
    root.applyBlendHolds();
  }

  // ---- rendering -------------------------------------------------------------------------------
  /// Forget the "previous tick" of every object: the next paints show the current state without blending. Used after a
  /// gap in time (app paused, long stall), where blending would run from a stale picture.
  void clearBlend() => root.clearBlendDeep();

  /// Placement options for the picture (scaling mode, safe area, backdrop). Changed by the app's settings.
  ViewOptions viewOptions = ViewOptions();

  ViewTransform viewTransform(ui.Size size) =>
      computeViewTransform(size, lib.stageW.toDouble(), lib.stageH.toDouble(), viewOptions);

  /// Paint the scene. [blend] (0..1) is how far between the previous and the current 18 Hz tick to draw; 1 shows the
  /// current state exactly.
  void paint(ui.Canvas canvas, ui.Size size, {double blend = 1}) {
    final v = viewTransform(size);
    final stageRect = ui.Rect.fromLTWH(v.offset.dx, v.offset.dy, lib.stageW * v.scale, lib.stageH * v.scale);
    canvas.drawRect(ui.Offset.zero & size, ui.Paint()..color = const ui.Color(0xFF000000));
    Node.blend = blend;
    FillTextureCache.devicePixelRatio = viewOptions.devicePixelRatio;
    try {
      final needsBackdrop = viewOptions.blurredBackdrop &&
          (stageRect.left > 0.5 || stageRect.top > 0.5 || stageRect.right < size.width - 0.5 || stageRect.bottom < size.height - 0.5);
      ui.Picture? scene;
      if (needsBackdrop) {
        final rec = ui.PictureRecorder();
        root.draw(ui.Canvas(rec), ColorTransform());
        scene = rec.endRecording();
        // Cover the whole screen with the picture, blurred and dimmed.
        final cover = math.max(size.width / lib.stageW, size.height / lib.stageH);
        canvas.save();
        canvas.clipRect(ui.Offset.zero & size);
        canvas.translate((size.width - lib.stageW * cover) / 2, (size.height - lib.stageH * cover) / 2);
        canvas.scale(cover, cover);
        final sigma = 14.0 / cover * v.scale.clamp(1, 4);
        canvas.saveLayer(null, ui.Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: ui.TileMode.clamp));
        canvas.drawPicture(scene);
        canvas.restore();
        canvas.restore();
        canvas.drawRect(ui.Offset.zero & size, ui.Paint()..color = const ui.Color(0x99000000));
      }
      canvas.save();
      canvas.translate(v.offset.dx, v.offset.dy);
      canvas.scale(v.scale, v.scale);
      canvas.clipRect(ui.Rect.fromLTWH(0, 0, lib.stageW.toDouble(), lib.stageH.toDouble()));
      if (scene != null) {
        canvas.drawPicture(scene);
      } else {
        root.draw(canvas, ColorTransform());
      }
      canvas.restore();
    } finally {
      Node.blend = 1;
    }
  }

  ui.Offset toStage(ui.Offset widgetPoint, ui.Size size) {
    final v = viewTransform(size);
    return (widgetPoint - v.offset) / v.scale;
  }

  // ---- pointer input ---------------------------------------------------------------------------
  Node? _hit(ui.Offset p) => root.hitInteractive(p);

  void _rollOver(Node d) {
    if (d is MovieClip) {
      d.onRollOver?.call();
    } else if (d is ButtonNode) {
      d.fireRollOver();
    }
  }

  void _rollOut(Node d) {
    if (d is MovieClip) {
      d.onRollOut?.call();
    } else if (d is ButtonNode) {
      d.fireRollOut();
    }
  }

  void pointerMove(ui.Offset p) {
    mouse = p;
    final target = _hit(p);
    if (pressed != null) {
      // While a button is held, only that button gets rollOver / rollOut.
      final inside = target == pressed;
      if (inside && hovered != pressed) {
        hovered = pressed;
        _rollOver(pressed!);
      } else if (!inside && hovered == pressed) {
        hovered = null;
        _rollOut(pressed!);
      }
      return;
    }
    if (target != hovered) {
      final old = hovered;
      hovered = null;
      if (old != null) _rollOut(old);
      hovered = target;
      if (target != null) _rollOver(target);
    }
  }

  void pointerDown(ui.Offset p) {
    pointerMove(p);
    for (final l in List.of(_mouseListeners)) {
      l.onMouseDown?.call();
    }
    final t = hovered;
    if (t != null) {
      pressed = t;
      if (t is MovieClip) {
        t.onPress?.call();
      } else if (t is ButtonNode) {
        t.firePress();
      }
    }
  }

  void pointerUp(ui.Offset p, {required bool leaves}) {
    mouse = p;
    for (final l in List.of(_mouseListeners)) {
      l.onMouseUp?.call();
    }
    final t = pressed;
    pressed = null;
    if (t != null && t == hovered) {
      if (t is MovieClip) {
        t.onRelease?.call();
      } else if (t is ButtonNode) {
        t.fireRelease();
      }
    }
    if (leaves && hovered != null) {
      final old = hovered!;
      hovered = null;
      _rollOut(old);
    } else {
      pointerMove(p);
    }
  }
}
