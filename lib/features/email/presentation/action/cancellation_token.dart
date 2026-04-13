/// A lightweight token that controllers create and cancel in onClose().
/// When cancelled, the [EmailActionQueue] skips callbacks but still
/// completes the HTTP call and fires bus events.
class CancellationToken {
  bool _cancelled = false;

  void cancel() => _cancelled = true;

  bool get isCancelled => _cancelled;
}
