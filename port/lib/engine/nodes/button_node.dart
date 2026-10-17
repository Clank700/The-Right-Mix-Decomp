import 'dart:ui' as ui;

import '../color_transform.dart';
import '../definitions.dart';
import '../library.dart';
import '../stage.dart';
import 'node.dart';
import 'shape_node.dart';
import 'text_field_node.dart';
import 'movie_clip.dart';

/// DefineButton2 instance: up / over / down graphics, hit area, and an `on(release)` action.
class ButtonNode extends Node {
  final ButtonDef def;
  final Library lib;
  final Stage stageRef;
  final void Function(ButtonNode self)? onReleaseAction;
  String state = 'up';
  void Function()? onPress;
  void Function()? onRelease;
  void Function()? onRollOver;
  void Function()? onRollOut;

  /// Script-visible flag (set by the game while the button is held).
  bool active = false;

  ButtonNode(this.def, this.lib, this.stageRef, this.onReleaseAction);

  @override
  bool get isInteractive => true;

  final Map<String, List<Node>> _built = {};

  List<Node> _recs(String st) {
    return _built.putIfAbsent(st, () {
      final out = <Node>[];
      final recs = [...(def.states[st] ?? const <ButtonRec>[])]..sort((a, b) => a.depth.compareTo(b.depth));
      for (final r in recs) {
        final d = createNode(lib, lib.chars[r.charId], stageRef);
        if (d == null) continue;
        d.matrix = r.matrix.clone();
        d.colorTransform = r.colorTransform.clone();
        out.add(d);
      }
      return out;
    });
  }

  @override
  void drawContent(ui.Canvas canvas, ColorTransform eff) {
    for (final d in _recs(state)) {
      d.draw(canvas, eff);
    }
  }

  @override
  bool hitShape(ui.Offset p) {
    for (final d in _recs('hit')) {
      final lp = d.toLocal(p);
      if (d.hitShape(lp)) return true;
    }
    return false;
  }

  @override
  Node? hitInteractive(ui.Offset p) {
    if (!visible) return null;
    return hitShape(toLocal(p)) ? this : null;
  }

  void firePress() {
    state = 'down';
    onPress?.call();
  }

  void fireRelease() {
    state = 'over';
    onRelease?.call();
    onReleaseAction?.call(this);
  }

  void fireRollOver() {
    state = 'over';
    onRollOver?.call();
  }

  void fireRollOut() {
    state = 'up';
    onRollOut?.call();
  }
}

Node? createNode(Library lib, CharDef? def, Stage stage) {
  if (def is ShapeDef) return ShapeNode(def, lib);
  if (def is SpriteDef) return MovieClip(lib, def, stage: stage);
  if (def is EditDef) return TextFieldNode(def, lib);
  if (def is ButtonDef) return ButtonNode(def, lib, stage, stage.buttonAction(def.id));
  return null;
}
