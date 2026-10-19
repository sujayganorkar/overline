import 'dart:collection';
import 'dart:typed_data';

import 'app_diagnostics.dart';

/// A bounded Least-Recently-Used (LRU) memory cache for rendered PDF page images.
///
/// Prevents Out-Of-Memory (OOM) crashes when scrolling through large 100+ page
/// documents by ensuring at most [maxCapacity] page bitmaps and [maxBytes]
/// total image memory are kept in RAM.
/// Automatically evicts all cached pages when the operating system issues a
/// memory pressure warning.
class BoundedPageCache {
  BoundedPageCache({
    this.maxCapacity = 10,
    this.maxBytes = 64 * 1024 * 1024, // 64 MB default per cache
  }) {
    AppDiagnostics.instance.addMemoryPressureListener(clear);
  }

  final int maxCapacity;
  final int maxBytes;
  final LinkedHashMap<int, Future<Uint8List>> _cache =
      LinkedHashMap<int, Future<Uint8List>>();
  final Map<int, int> _byteSizes = <int, int>{};
  int _currentBytes = 0;

  /// Current memory size of all resolved pages in bytes.
  int get currentBytes => _currentBytes;

  /// Returns the cached future for [page], or loads it via [ifAbsent].
  Future<Uint8List> putIfAbsent(int page, Future<Uint8List> Function() ifAbsent) {
    if (_cache.containsKey(page)) {
      // Re-insert to mark as most recently used in LinkedHashMap
      final future = _cache.remove(page)!;
      _cache[page] = future;
      return future;
    }

    _evictToCapacity();

    final future = ifAbsent().then((bytes) {
      final size = bytes.lengthInBytes;
      _byteSizes[page] = size;
      _currentBytes += size;
      _evictToBytes();
      return bytes;
    });

    _cache[page] = future;
    return future;
  }

  void _evictToCapacity() {
    while (_cache.length >= maxCapacity && _cache.isNotEmpty) {
      final oldestKey = _cache.keys.first;
      _evictKey(oldestKey, 'capacity limit ($maxCapacity)');
    }
  }

  void _evictToBytes() {
    while (_currentBytes > maxBytes && _cache.isNotEmpty) {
      final oldestKey = _cache.keys.first;
      _evictKey(oldestKey, 'memory limit (${maxBytes ~/ (1024 * 1024)} MB)');
    }
  }

  void _evictKey(int key, String reason) {
    _cache.remove(key);
    final size = _byteSizes.remove(key) ?? 0;
    _currentBytes -= size;
    AppDiagnostics.instance.record(
      category: 'memory',
      message: 'Evicted page $key from cache ($reason)',
    );
  }

  /// Check if a page is currently cached.
  bool contains(int page) => _cache.containsKey(page);

  /// Number of pages currently cached.
  int get length => _cache.length;

  /// Clears all cached pages.
  void clear() {
    if (_cache.isNotEmpty) {
      final count = _cache.length;
      final bytes = _currentBytes;
      _cache.clear();
      _byteSizes.clear();
      _currentBytes = 0;
      AppDiagnostics.instance.record(
        category: 'memory',
        message: 'Cleared $count cached pages (${bytes ~/ 1024} KB) from memory cache',
      );
    }
  }

  void dispose() {
    AppDiagnostics.instance.removeMemoryPressureListener(clear);
    _cache.clear();
    _byteSizes.clear();
    _currentBytes = 0;
  }
}
