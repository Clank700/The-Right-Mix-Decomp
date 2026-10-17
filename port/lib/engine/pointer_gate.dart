/// Flash has exactly one mouse. A touch screen can have several fingers down; this lets the first finger act as the
/// mouse and ignores the others until it lifts, so a second finger cannot press, release or move the first one's
/// button.
class SinglePointerGate {
  int? _active;

  /// The pointer currently acting as the mouse, if any.
  int? get active => _active;

  /// A pointer went down. Returns true when it becomes (or already is) the mouse pointer.
  bool down(int pointer) {
    if (_active != null && _active != pointer) return false;
    _active = pointer;
    return true;
  }

  /// A pointer moved (or hovered). True when it is the mouse pointer, or no pointer is down (mouse hover).
  bool move(int pointer) => _active == null || _active == pointer;

  /// A pointer went up or was cancelled. Returns true when it was the mouse pointer.
  bool up(int pointer) {
    if (_active != pointer) return false;
    _active = null;
    return true;
  }

  /// Forget everything (app paused, window lost focus).
  void reset() => _active = null;
}
