import 'dart:async';

/// Coalesces noisy realtime events while guaranteeing a final synchronization.
///
/// A read receipt can update many message rows at once. Supabase emits one
/// event per row, so starting a full inbox refresh for every event creates
/// races and duplicate notifications. This coordinator keeps at most one sync
/// in flight and collapses every burst into one trailing pass.
class ChatSyncCoordinator {
  ChatSyncCoordinator({this.debounce = const Duration(milliseconds: 140)});

  final Duration debounce;

  Timer? _timer;
  bool _isRunning = false;
  bool _runAgain = false;
  bool _isDisposed = false;

  void schedule(Future<void> Function() synchronize) {
    if (_isDisposed) return;
    _runAgain = true;
    _timer?.cancel();
    _timer = Timer(debounce, () {
      _timer = null;
      unawaited(runNow(synchronize));
    });
  }

  Future<void> runNow(Future<void> Function() synchronize) async {
    if (_isDisposed) return;
    _runAgain = true;
    if (_isRunning) return;

    _timer?.cancel();
    _timer = null;
    _isRunning = true;
    try {
      while (_runAgain && !_isDisposed) {
        _runAgain = false;
        await synchronize();
        // An event received during the request has already set _runAgain.
        // Cancel its debounce timer because the trailing pass can start now.
        if (_runAgain) {
          _timer?.cancel();
          _timer = null;
        }
      }
    } finally {
      _isRunning = false;
      // Preserve a request that arrived between the last loop condition and
      // the finally block, including when [synchronize] throws.
      if (_runAgain && !_isDisposed) {
        schedule(synchronize);
      }
    }
  }

  void cancelPending() {
    _timer?.cancel();
    _timer = null;
    _runAgain = false;
  }

  void dispose() {
    _isDisposed = true;
    cancelPending();
  }
}
