import 'package:flutter_test/flutter_test.dart';
import 'package:the_right_mix/settings.dart';

void main() {
  test('settings round-trip through JSON', () {
    final s = Settings(integerScale: true, blurredBackdrop: true, smoothMotion: false, fullscreen: true);
    final back = Settings.decode(s.encode());
    expect(back.integerScale, isTrue);
    expect(back.blurredBackdrop, isTrue);
    expect(back.smoothMotion, isFalse);
    expect(back.fullscreen, isTrue);
  });

  test('defaults: smooth motion on, everything else off', () {
    final s = Settings();
    expect([s.smoothMotion, s.integerScale, s.blurredBackdrop, s.fullscreen], [true, false, false, false]);
  });

  test('missing, empty or corrupt files give defaults instead of an error', () {
    for (final text in [null, '', '{', '[1,2]', 'not json']) {
      final s = Settings.decode(text);
      expect(s.smoothMotion, isTrue);
      expect(s.integerScale, isFalse);
    }
  });

  test('unknown keys are ignored and partial files keep defaults for the rest', () {
    final s = Settings.decode('{"integerScale": true, "somethingNew": 5}');
    expect(s.integerScale, isTrue);
    expect(s.smoothMotion, isTrue);
  });
}
