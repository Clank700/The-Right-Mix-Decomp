/// Turns the display's variable frame times into fixed simulation steps (the SWF runs at 18 frames per second).
///
/// Feed it the elapsed time of the frame ticker; it returns how many 1/18 s steps to run now. The number of steps
/// over any period depends on wall-clock time, not on the display rate, so 30, 60, 90, 120 or 144 Hz screens play at
/// the same speed. After a stall (app switch, debugger, slow frame) the lost time is dropped instead of replayed.
class FixedStepper {
  final double step;
  final double maxFrameTime;
  final int maxStepsPerFrame;
  Duration? _last;
  double _acc = 0;

  /// The latest [advance] came after the app was away or a frame took longer than [maxFrameTime]: the lost time
  /// is dropped (no catching up) and the caller should not blend across the gap.
  bool suspended = false;

  FixedStepper({required this.step, this.maxFrameTime = 0.25, this.maxStepsPerFrame = 4});

  /// How far the display is between the last simulated step (0) and the next one (1): used to blend frames.
  double get alpha => (_acc / step).clamp(0.0, 1.0);

  /// Forget the previous frame time (call when the app comes back from the background).
  void reset() {
    _last = null;
    _acc = 0;
    suspended = true;
  }

  int advance(Duration elapsed) {
    final last = _last;
    _last = elapsed;
    if (last == null) {
      suspended = true;
      _acc = 0;
      return 0;
    }
    var dt = (elapsed - last).inMicroseconds / 1e6;
    if (dt < 0) dt = 0;
    if (dt > maxFrameTime) {
      // The app was suspended (or the frame stalled for a long time): don't replay the gap.
      suspended = true;
      _acc = 0;
      return 0;
    }
    suspended = false;
    _acc += dt;
    var steps = 0;
    while (_acc >= step && steps < maxStepsPerFrame) {
      _acc -= step;
      steps++;
    }
    // If the step budget ran out, drop the remainder rather than carrying a growing backlog.
    if (steps == maxStepsPerFrame && _acc >= step) _acc = 0;
    return steps;
  }
}
