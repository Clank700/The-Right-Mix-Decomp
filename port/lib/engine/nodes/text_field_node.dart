import 'dart:ui' as ui;

import '../color_transform.dart';
import '../definitions.dart';
import '../library.dart';
import 'node.dart';

/// Dynamic text field (DefineEditText) rendered from the embedded font outlines.
class TextFieldNode extends Node {
  final EditDef def;
  final Library lib;
  String text;
  TextFieldNode(this.def, this.lib) : text = def.initialText;

  @override
  void drawContent(ui.Canvas canvas, ColorTransform eff) {
    if (text.isEmpty) return;
    final font = def.fontId == null ? null : lib.chars[def.fontId] as FontDef?;
    final color = eff.apply(def.color);
    if (font == null || font.glyphs.isEmpty) {
      _drawDeviceText(canvas, color);
      return;
    }
    final scale = def.height / font.em;
    final ascent = font.ascent * scale;
    final descent = font.descent * scale;
    final lineH = ascent + descent + def.leading;
    final left = def.bounds.left + 2 + def.leftMargin;
    final avail = def.bounds.width - 4 - def.leftMargin - def.rightMargin;

    double adv(int code) {
      final g = font.codeToGlyph[code];
      return g == null ? 0 : font.adv[g] * scale;
    }

    double width(List<int> s) => s.fold(0.0, (a, c) => a + adv(c));

    final lines = <List<int>>[];
    for (final para in text.split(RegExp(r'\r\n|\r|\n'))) {
      final codes = para.runes.toList();
      if (!def.wrap) {
        lines.add(codes);
        continue;
      }
      var cur = <int>[];
      var curW = 0.0;
      var i = 0;
      while (i < codes.length) {
        var j = i;
        while (j < codes.length && codes[j] != 32) {
          j++;
        }
        final word = codes.sublist(i, j);
        final space = j < codes.length ? <int>[32] : <int>[];
        final ww = width(word);
        if (cur.isNotEmpty && curW + ww > avail) {
          lines.add(cur);
          cur = <int>[];
          curW = 0;
        }
        cur.addAll(word);
        curW += ww;
        cur.addAll(space);
        curW += width(space);
        i = j + 1;
      }
      lines.add(cur);
    }

    final paint = ui.Paint()
      ..isAntiAlias = true
      ..color = color;
    var baseline = def.bounds.top + 2 + ascent;
    for (final line in lines) {
      final lw = width(_trimRight(line));
      var penX = left;
      if (def.align == 2) {
        penX = left + (avail - lw) / 2;
      } else if (def.align == 1) {
        penX = left + avail - lw;
      }
      for (final code in line) {
        final g = font.codeToGlyph[code];
        if (g == null) continue;
        canvas.save();
        canvas.translate(penX, baseline);
        canvas.scale(scale, scale);
        canvas.drawPath(font.glyphs[g], paint);
        canvas.restore();
        penX += font.adv[g] * scale;
      }
      baseline += lineH;
    }
  }

  static List<int> _trimRight(List<int> l) {
    var e = l.length;
    while (e > 0 && l[e - 1] == 32) {
      e--;
    }
    return l.sublist(0, e);
  }

  void _drawDeviceText(ui.Canvas canvas, ui.Color color) {
    final pb = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: const [ui.TextAlign.left, ui.TextAlign.right, ui.TextAlign.center, ui.TextAlign.justify][def.align],
      fontSize: def.height,
    ))
      ..pushStyle(ui.TextStyle(color: color, fontFamily: 'Arial'))
      ..addText(text);
    final p = pb.build()..layout(ui.ParagraphConstraints(width: def.bounds.width - 4));
    canvas.drawParagraph(p, ui.Offset(def.bounds.left + 2, def.bounds.top + 2));
  }
}
