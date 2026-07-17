typedef ChatMediaUrlLoader = Future<String> Function();

class ChatMediaUrlCache {
  ChatMediaUrlCache({
    required this.timeToLive,
    this.refreshMargin = const Duration(minutes: 5),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration timeToLive;
  final Duration refreshMargin;
  final DateTime Function() _now;

  final Map<String, _ChatMediaUrlEntry> _entries = {};
  final Map<String, Future<String?>> _inFlight = {};
  int _generation = 0;

  Future<String?> resolve({
    required String key,
    required ChatMediaUrlLoader load,
  }) {
    final cached = _entries[key];
    if (cached != null && cached.expiresAt.isAfter(_now().add(refreshMargin))) {
      return Future<String?>.value(cached.url);
    }

    final existingRequest = _inFlight[key];
    if (existingRequest != null) return existingRequest;

    final generation = _generation;
    final request = Future<String>.sync(load).then<String?>((value) {
      final url = value.trim();
      if (url.isEmpty) return null;
      if (generation == _generation) {
        _entries[key] = _ChatMediaUrlEntry(
          url: url,
          expiresAt: _now().add(timeToLive),
        );
      }
      return url;
    });
    _inFlight[key] = request;
    request.then<void>(
      (_) {
        if (identical(_inFlight[key], request)) _inFlight.remove(key);
      },
      onError: (Object _, StackTrace _) {
        if (identical(_inFlight[key], request)) _inFlight.remove(key);
      },
    );
    return request;
  }

  void invalidate(String key) {
    _entries.remove(key);
  }

  void clear() {
    _generation++;
    _entries.clear();
    _inFlight.clear();
  }
}

class _ChatMediaUrlEntry {
  const _ChatMediaUrlEntry({required this.url, required this.expiresAt});

  final String url;
  final DateTime expiresAt;
}
