/// Decides whether a camera detection should be processed.
///
/// The scanner reports the same QR code many times per second while it stays
/// in view. The gate:
/// - allows only one detection to be processed at a time;
/// - ignores the most recent code while it keeps being seen, until it has
///   been out of view for [cooldown] (each sighting extends the window);
/// - lets a different code through as soon as the current one is finished.
class ScanGate {
  ScanGate({required this.cooldown, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final Duration cooldown;
  final DateTime Function() _clock;

  bool _busy = false;
  String? _lastKey;
  DateTime? _lastSeenAt;

  bool get isBusy => _busy;

  /// Returns true if [key] should be processed now. The caller must call
  /// [release] when processing finishes (typically in a `finally` block).
  bool tryAcquire(String key) {
    final now = _clock();
    final lastSeen = _lastSeenAt;
    final isRecentRepeat =
        key == _lastKey &&
        lastSeen != null &&
        now.difference(lastSeen) < cooldown;

    if (key == _lastKey) {
      _lastSeenAt = now;
    }
    if (_busy || isRecentRepeat) return false;

    _busy = true;
    _lastKey = key;
    _lastSeenAt = now;
    return true;
  }

  /// Marks processing as finished. The cooldown restarts from now, so a code
  /// that stays in view during a slow request is still not resubmitted.
  void release() {
    _busy = false;
    _lastSeenAt = _clock();
  }

  /// Forgets the last code so it can be scanned again immediately.
  void reset() {
    _lastKey = null;
    _lastSeenAt = null;
  }
}
