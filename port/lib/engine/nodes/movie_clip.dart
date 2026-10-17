import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import '../color_transform.dart';
import '../definitions.dart';
import '../library.dart';
import '../stage.dart';
import 'node.dart';
import 'shape_node.dart';
import 'button_node.dart';

/// MovieClip: a display list plus an optional timeline.
class MovieClip extends Node {
  final Library lib;
  final SpriteDef? def;
  final Stage? _stage;
  final SplayTreeMap<int, Node> children = SplayTreeMap<int, Node>();
  int frame = 1;
  bool playing = true;

  /// The timeline created, removed or swapped something this tick (frame-by-frame art rather than a tween).
  bool _structural = false;
  bool _justCreated = true;

  // Script-visible state
  Object? parentObj;
  bool active = false;
  void Function()? onPress;
  void Function()? onRelease;
  void Function()? onRollOver;
  void Function()? onRollOut;
  void Function()? onEnterFrame;

  // Drawing API (used by the pouring stream)
  final List<_LineRun> _lines = [];
  _LineRun? _curLine;
  ui.Offset _pen = ui.Offset.zero;

  MovieClip(this.lib, this.def, {this._stage, bool deferInit = false}) {
    if (def != null && !deferInit) initTimeline();
  }

  /// Places frame 1 of the timeline (the root clip does this after the stage is fully set up).
  void initTimeline() => _applyFrame(1, runScripts: true, initial: true);

  @override
  Stage get stage => _stage ?? parent!.stage;

  int get totalFrames => def?.nframes ?? 1;

  @override
  bool get isInteractive => onPress != null || onRelease != null || onRollOver != null || onRollOut != null;

  // ---- display list management -----------------------------------------------------------------
  Node? child(String name) {
    for (final c in children.values) {
      if (c.name == name) return c;
    }
    return null;
  }

  MovieClip? clipChild(String name) {
    final c = child(name);
    return c is MovieClip ? c : null;
  }

  void addChild(Node d, int depth) {
    final old = children[depth];
    if (old != null) _detach(old);
    d.parent = this;
    d.depth = depth;
    children[depth] = d;
  }

  void _detach(Node d) {
    if (stage.hovered == d) stage.hovered = null;
    if (stage.pressed == d) stage.pressed = null;
    if (d is MovieClip) {
      for (final c in d.children.values.toList()) {
        d._detach(c);
      }
    }
    d.parent = null;
  }

  void removeChild(Node d) {
    if (children[d.depth] == d) {
      children.remove(d.depth);
      _detach(d);
    }
  }

  void swapChildDepth(Node d, int newDepth) {
    if (d.depth == newDepth) return;
    final other = children[newDepth];
    children.remove(d.depth);
    if (other != null) {
      other.depth = d.depth;
      children[d.depth] = other;
    }
    d.depth = newDepth;
    children[newDepth] = d;
  }

  /// MovieClip.attachMovie: instantiate an exported symbol. Returns null for an unknown linkage id.
  MovieClip? attachMovie(String linkage, String instanceName, int depth) {
    final cd = lib.byLinkage(linkage);
    if (cd is! SpriteDef) return null;
    final c = MovieClip(lib, cd, stage: stage);
    c.name = instanceName;
    // A clip attached by script is visited later in the same tick and starts playing right away (timeline-placed
    // clips instead hold their first frame for one tick).
    c._justCreated = false;
    addChild(c, depth);
    return c;
  }

  /// attachMovie for a Button symbol (the Pour / Shake / Serve controls are exported buttons).
  ButtonNode? attachButton(String linkage, String instanceName, int depth) {
    final cd = lib.byLinkage(linkage);
    if (cd is! ButtonDef) return null;
    final b = ButtonNode(cd, lib, stage, stage.buttonAction(cd.id));
    b.name = instanceName;
    addChild(b, depth);
    return b;
  }

  MovieClip createEmptyMovieClip(String instanceName, int depth) {
    final c = MovieClip(lib, null, stage: stage);
    c.name = instanceName;
    addChild(c, depth);
    return c;
  }

  // ---- timeline --------------------------------------------------------------------------------
  void play() => playing = true;
  void stop() => playing = false;

  void gotoAndStop(int f) {
    playing = false;
    gotoFrame(f);
  }

  void gotoAndPlay(int f) {
    playing = true;
    gotoFrame(f);
  }

  void gotoFrame(int f) {
    if (def == null) return;
    final target = f.clamp(1, totalFrames);
    if (target == frame) return;
    _applyFrame(target, runScripts: true);
  }

  void _applyFrame(int target, {required bool runScripts, bool initial = false}) {
    final d = def!;
    if (!initial && target < frame) {
      for (final dd in children.values.where((c) => c.timelineOwned).toList()) {
        removeChild(dd);
      }
      frame = 0;
    }
    if (initial) frame = 0;
    // Blending carries an object's previous position into the next frame only for ordinary playback (one frame
    // forward). A jump (gotoAndStop to a far frame, a rewind) is a discontinuity: those objects are drawn where
    // they now are.
    final smooth = !initial && target == frame + 1;
    if (!smooth && !initial) _structural = true;
    for (var f = frame + 1; f <= target; f++) {
      if (f - 1 < d.frames.length) {
        for (final cmd in d.frames[f - 1].cmds) {
          _place(cmd, smooth);
        }
      }
    }
    frame = target;
    if (_structural) animationRoot.holdChildren();
    if (target - 1 < d.frames.length) {
      final fd = d.frames[target - 1];
      for (final s in fd.sounds) {
        stage.audio.playCue(lib, s.soundId, s.loops, s.stop, s.file);
      }
      if (runScripts && !stage.ignoreFrameScripts) {
        if (fd.scriptKind == 'stop') {
          playing = false;
        } else if (fd.scriptKind == 'script') {
          stage.runFrameScript(this, d.id, target);
        }
      }
    }
  }

  void _place(PlaceCmd cmd, bool smooth) {
    if (cmd.remove != null) {
      final c = children[cmd.remove!];
      if (c != null && c.timelineOwned) {
        removeChild(c);
        _structural = true;
      }
      return;
    }
    final existing = children[cmd.depth];
    if (cmd.charId != null) {
      final cd = lib.chars[cmd.charId];
      final inst = createNode(lib, cd, stage);
      if (inst == null) return;
      inst.timelineOwned = true;
      inst.charId = cmd.charId;
      // Frame-by-frame art: something appears or is swapped for another drawing. Moving parts of such a clip must not
      // be blended against parts that just changed, so the whole clip is drawn at its current frame this tick.
      if (existing == null || !cmd.move || existing.charId != cmd.charId) _structural = true;
      if (cmd.move && existing != null) {
        inst.matrix = existing.matrix.clone();
        inst.colorTransform = existing.colorTransform.clone();
        inst.name = existing.name;
        inst.clipDepth = existing.clipDepth;
      }
      if (cmd.matrix != null) inst.matrix = cmd.matrix!.clone();
      if (cmd.colorTransform != null) inst.colorTransform = cmd.colorTransform!.clone();
      if (cmd.name != null) inst.name = cmd.name!;
      if (cmd.clipDepth != null) inst.clipDepth = cmd.clipDepth!;
      // A timeline step that moves an object more than a tween plausibly does is a cut: draw it where it lands.
      if (smooth &&
          cmd.move &&
          existing != null &&
          existing.charId == cmd.charId &&
          !existing.matrix.isJumpTo(inst.matrix)) {
        inst.inheritBlendFrom(existing);
      }
      if (cmd.hasClipActions && inst is MovieClip && cmd.name != null) {
        stage.applyClipLoad(inst, def!.id, cmd.name!);
      }
      addChild(inst, cmd.depth);
      return;
    }
    if (existing != null) {
      if (!smooth || (cmd.matrix != null && existing.matrix.isJumpTo(cmd.matrix!))) existing.breakBlend();
      if (cmd.matrix != null) existing.matrix = cmd.matrix!.clone();
      if (cmd.colorTransform != null) existing.colorTransform = cmd.colorTransform!.clone();
      if (cmd.name != null) existing.name = cmd.name!;
      if (cmd.clipDepth != null) existing.clipDepth = cmd.clipDepth!;
    }
  }

  /// One tick for this clip and its descendants, walked depth first like the original player does: the clip's own
  /// onEnterFrame handler runs, then its playhead moves, then its children get the same treatment (including
  /// clips the handler just attached). So a parent's handler sees its children one tick behind.
  void tickFrame() {
    onEnterFrame?.call();
    if (_justCreated) {
      _justCreated = false;
    } else if (playing && totalFrames > 1) {
      final next = frame + 1 > totalFrames ? 1 : frame + 1;
      _applyFrame(next, runScripts: true);
    }
    for (final c in children.values.toList()) {
      if (c is MovieClip && c.parent == this) c.tickFrame();
    }
  }

  /// Draw everything inside this clip as it is now (no blending) until the next tick.
  void holdChildren() {
    for (final c in children.values) {
      if (c is MovieClip) {
        c.clearBlendDeep();
      } else {
        c.breakBlend();
      }
    }
  }

  /// The outermost timeline clip this one is part of (a character such as Miguel, a finale, the hand): hand-drawn
  /// animation is held as a whole, because its parts are drawn to fit each other frame by frame. Clips made by script
  /// (containers) and the stage root are not part of an animation.
  MovieClip get animationRoot {
    MovieClip c = this;
    while (c.parent != null && c.parent!.def != null && !identical(c.parent, stage.root)) {
      c = c.parent!;
    }
    return c;
  }

  /// End of a tick: every animation that changed drawings this tick (a part appeared, vanished or was swapped, or the
  /// timeline jumped) is drawn at its current frame in full, including parts whose own timelines advanced after the
  /// parent's. Flags are reset for the next tick.
  void applyBlendHolds() {
    final roots = <MovieClip>{};
    void collect(MovieClip c) {
      if (c._structural) {
        c._structural = false;
        roots.add(c.animationRoot);
      }
      for (final k in c.children.values) {
        if (k is MovieClip) collect(k);
      }
    }

    collect(this);
    for (final r in roots) {
      r.holdChildren();
    }
  }

  void clearBlendDeep() {
    breakBlend();
    for (final c in children.values) {
      if (c is MovieClip) {
        c.clearBlendDeep();
      } else {
        c.breakBlend();
      }
    }
  }

  @override
  void snapshotForBlend() {
    super.snapshotForBlend();
    for (final c in children.values) {
      c.snapshotForBlend();
    }
  }

  /// Playhead movement only (no handlers): used to step a stand-alone clip, e.g. when rendering a symbol frame.
  void advanceFrame() {
    if (_justCreated) {
      _justCreated = false;
    } else if (playing && totalFrames > 1) {
      final next = frame + 1 > totalFrames ? 1 : frame + 1;
      _applyFrame(next, runScripts: true);
    }
    for (final c in children.values.toList()) {
      if (c is MovieClip && c.parent == this) c.advanceFrame();
    }
  }

  // ---- drawing API -----------------------------------------------------------------------------
  void clearDrawing() {
    _lines.clear();
    _curLine = null;
  }

  void lineStyle(double width, int rgb, double alphaPct) {
    _curLine = _LineRun(width, rgb, alphaPct);
    _lines.add(_curLine!);
  }

  void moveTo(double x, double y) {
    _pen = ui.Offset(x, y);
    _curLine?.segs.add([x, y, null, null]);
  }

  void lineTo(double x, double y) {
    _curLine?.segs.add([_pen.dx, _pen.dy, x, y]);
    _pen = ui.Offset(x, y);
  }

  // ---- rendering -------------------------------------------------------------------------------
  @override
  double get height {
    // Approximate `_height` from child bounds (only used for layout of the shelf bottles).
    var top = double.infinity, bottom = double.negativeInfinity;
    for (final c in children.values) {
      if (c is ShapeNode) {
        top = math.min(top, c.def.bounds.top * c.matrix.d + c.matrix.ty);
        bottom = math.max(bottom, c.def.bounds.bottom * c.matrix.d + c.matrix.ty);
      } else {
        final h = c.height;
        top = math.min(top, c.matrix.ty);
        bottom = math.max(bottom, c.matrix.ty + h);
      }
    }
    if (top == double.infinity) return 0;
    return (bottom - top) * yscale / 100;
  }

  @override
  void drawContent(ui.Canvas canvas, ColorTransform eff) {
    for (final l in _lines) {
      final paint = ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = l.width
        ..strokeCap = ui.StrokeCap.round
        ..strokeJoin = ui.StrokeJoin.round
        ..isAntiAlias = true
        ..color = eff.apply([(l.rgb >> 16) & 255, (l.rgb >> 8) & 255, l.rgb & 255, (l.alpha * 2.55).round()]);
      final path = ui.Path();
      for (final s in l.segs) {
        if (s[2] == null) {
          path.moveTo(s[0]!, s[1]!);
        } else {
          path.moveTo(s[0]!, s[1]!);
          path.lineTo(s[2]!, s[3]!);
        }
      }
      canvas.drawPath(path, paint);
    }
    final kids = children.values.toList();
    var i = 0;
    while (i < kids.length) {
      final k = kids[i];
      if (k.clipDepth > 0) {
        // mask layer: content between this depth and clipDepth is clipped to the mask's shape
        final content = <Node>[];
        var j = i + 1;
        while (j < kids.length && kids[j].depth <= k.clipDepth) {
          content.add(kids[j]);
          j++;
        }
        if (content.isNotEmpty) {
          canvas.saveLayer(null, ui.Paint());
          for (final c in content) {
            c.draw(canvas, eff);
          }
          canvas.saveLayer(null, ui.Paint()..blendMode = ui.BlendMode.dstIn);
          k.draw(canvas, ColorTransform());
          canvas.restore();
          canvas.restore();
        }
        i = j;
      } else {
        k.draw(canvas, eff);
        i++;
      }
    }
  }

  // ---- interaction -----------------------------------------------------------------------------
  @override
  bool hitShape(ui.Offset p) {
    for (final c in children.values) {
      if (!c.visible || c.clipDepth > 0) continue;
      if (c.hitShape(c.toLocal(p))) return true;
    }
    return false;
  }

  @override
  Node? hitInteractive(ui.Offset p) {
    if (!visible) return null;
    final lp = toLocal(p);
    if (isInteractive && hitShape(lp)) return this;
    for (final c in children.values.toList().reversed) {
      final r = c.hitInteractive(lp);
      if (r != null) return r;
    }
    return null;
  }
}

class _LineRun {
  final double width;
  final int rgb;
  final double alpha;
  final List<List<double?>> segs = [];
  _LineRun(this.width, this.rgb, this.alpha);
}
