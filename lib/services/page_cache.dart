import 'dart:collection';
import 'dart:typed_data';

import 'app_diagnostics.dart';

/// A bounded Least-Recently-Used (LRU) memory cache for rendered PDF page images.
///
/// Prevents Out-Of-Memory (OOM) crashes when scrolling through large 100+ page
/// documents by ensuring at most [maxCapacity] page bitmaps are kept in RAM.
/// Automatically evicts all cached pages when the operating system issues a
/// memory pressure warning.
class BoundedPageCache {
  BoundedPageCache({this.maxCapacity = 10}) {
    AppDiagnostics.instance.addMemoryPressureListener(clear);
  }

  final int maxCapacity;
  final LinkedHashMap<int, Future<Uint8List>> _cache =
      LinkedHashMap<int, Future<Uint8List>>();

  /// Returns the cached future for [page], or loads it via [ifAbsent].
  Future<Uint8List> putIfAbsent(int page, Future<Uint8List> Function() ifAbsent) {
    if (_cache.containsKey(page)) {
      // Re-insert to mark as most recently used in LinkedHashMap
      final future = _cache.remove(page)!;
      _cache[page] = future;
      return future;
    }

    // Evict oldest if capacity reached
    if (_cache.length >= maxCapacity) {
      final oldestKey = _cache.keys.first;
      _cache.remove(oldestKey);
      AppDiagnostics.instance.record(
        category: 'memory',
        message: 'Evicted page $oldestKey from cache (capacity $maxCapacity)',
      );
    }

    final future = ifAbsent();
    _cache[page] = future;
    return future;
  }

  /// Check if a page is currently cached.
  bool contains(int page) => _cache.containsKey(page);

  /// Number of pages currently cached.
  int get length => _cache.length;

  /// Clears all cached pages.
  void clear() {
    if (_cache.isNotEmpty) {
      final count = _cache.length;
      _cache.clear();
      AppDiagnostics.instance.record(
        category: 'memory',
        message: 'Cleared $count cached pages from memory cache',
      );
    }
  }

  void dispose() {
    AppDiagnostics.instance.removeMemoryPressureListener(clear);
    _cache.clear();
  }
}

