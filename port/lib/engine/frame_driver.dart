import 'fixed_step.dart';
import 'stage.dart';

/// Connects the display's frame ticker to the 18 Hz simulation: runs whole ticks, tells the painter how far between
/// two ticks the picture is, and makes sure nothing is blended across a gap in time (pause, window drag, stall).
class FrameDriver {
  final Stage stage;
  final FixedStepper stepper;

  /// Called after every simulated tick (used for tracing).
  void Function()? onTick;

  FrameDriver(this.stage, double step) : stepper = FixedStepper(step: step);

  /// One display frame at ticker time [elapsed]. Returns the number of simulation ticks that ran.
  int frame(Duration elapsed) {
    final steps = stepper.advance(elapsed);
    if (stepper.suspended) stage.clearBlend();
    for (var i = 0; i < steps; i++) {
      stage.tick();
      onTick?.call();
    }
    return steps;
  }

  /// The app left the foreground (or the window lost focus): forget time and any half-finished blend.
  void suspend() {
    stepper.reset();
    stage.clearBlend();
  }

  /// How far between the last tick (0) and the next (1) to draw; 1 when smoothing is off.
  double blend(bool smooth) => smooth ? stepper.alpha : 1.0;
}
