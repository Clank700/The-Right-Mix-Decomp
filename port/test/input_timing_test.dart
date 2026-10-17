import 'package:flutter_test/flutter_test.dart';
import 'package:the_right_mix/engine/engine.dart';

/// Frame-rate independence and touch gating, tested on the same classes the app uses (main.dart wires them up).
void main() {
  group('FixedStepper (18 steps per second whatever the display rate)', () {
    int stepsOver(double hz, double seconds, {double jitter = 0}) {
      final s = FixedStepper(step: 1 / 18);
      var total = 0;
      final frames = (hz * seconds).round();
      for (var i = 0; i <= frames; i++) {
        final t = i / hz + (i.isOdd ? jitter : -jitter);
        total += s.advance(Duration(microseconds: (t * 1e6).round()));
      }
      return total;
    }

    for (final hz in [24.0, 30.0, 48.0, 60.0, 72.0, 90.0, 120.0, 144.0, 165.0, 240.0]) {
      test('${hz.toStringAsFixed(0)} Hz: 10 s -> 180 steps (+-1)', () {
        expect(stepsOver(hz, 10), inInclusiveRange(179, 181));
      });
    }

    test('uneven frame times (vsync jitter) do not change the count', () {
      expect(stepsOver(60, 10, jitter: 0.004), inInclusiveRange(179, 181));
    });

    test('a long stall is dropped, not replayed', () {
      final s = FixedStepper(step: 1 / 18);
      s.advance(Duration.zero);
      expect(s.advance(const Duration(seconds: 30)), lessThanOrEqualTo(4));
      expect(s.advance(const Duration(seconds: 30, milliseconds: 16)), lessThanOrEqualTo(1));
    });

    test('reset forgets the time spent in the background', () {
      final s = FixedStepper(step: 1 / 18);
      s.advance(Duration.zero);
      s.advance(const Duration(milliseconds: 100));
      s.reset();
      expect(s.advance(const Duration(minutes: 5)), 0); // first frame after reset only records the time
      expect(s.advance(const Duration(minutes: 5, milliseconds: 60)), 1);
    });
  });

  group('SinglePointerGate', () {
    test('first finger acts as the mouse; others are ignored until it lifts', () {
      final g = SinglePointerGate();
      expect(g.down(1), isTrue);
      expect(g.down(2), isFalse);
      expect(g.move(2), isFalse);
      expect(g.move(1), isTrue);
      expect(g.up(2), isFalse); // second finger lifting must not release the first
      expect(g.active, 1);
      expect(g.up(1), isTrue);
      expect(g.active, isNull);
      expect(g.down(2), isTrue); // now the other finger may take over
    });

    test('hover (no pointer down) is always accepted; reset releases', () {
      final g = SinglePointerGate();
      expect(g.move(7), isTrue);
      g.down(3);
      g.reset();
      expect(g.active, isNull);
      expect(g.up(3), isFalse);
    });
  });
}
