/// Tracks the entire contact sequence, including fingers lifted before the last
/// one. A pinch must never finish as a tap, stroke, or page turn.
class TouchSession {
  final Set<int> _pointers = {};
  bool interrupted = false;
  bool get canEdit => !interrupted;

  void down(int pointer) {
    if (_pointers.isEmpty) interrupted = false;
    _pointers.add(pointer);
    if (_pointers.length > 1) interrupted = true;
  }

  void up(int pointer) => _pointers.remove(pointer);

  void cancel(int pointer) {
    interrupted = true;
    _pointers.remove(pointer);
  }
}
