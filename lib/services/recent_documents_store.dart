import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Metadata for a recently opened document.
class RecentDocumentEntry {
  const RecentDocumentEntry({
    required this.name,
    required this.pageCount,
    required this.openedAtMs,
    this.cachedFilePath,
    this.byteLength,
  });

  final String name;
  final int pageCount;
  final int openedAtMs;
  final String? cachedFilePath;
  final int? byteLength;

  Map<String, dynamic> toJson() => {
    'name': name,
    'pageCount': pageCount,
    'openedAtMs': openedAtMs,
    'cachedFilePath': cachedFilePath,
    'byteLength': byteLength,
  };

  static RecentDocumentEntry? fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String?;
    final pageCount = (json['pageCount'] as num?)?.toInt();
    final openedAtMs = (json['openedAtMs'] as num?)?.toInt();
    if (name == null || pageCount == null || openedAtMs == null) return null;
    return RecentDocumentEntry(
      name: name,
      pageCount: pageCount,
      openedAtMs: openedAtMs,
      cachedFilePath: json['cachedFilePath'] as String?,
      byteLength: (json['byteLength'] as num?)?.toInt(),
    );
  }
}

/// Stores and manages recently opened documents in private app storage.
///
/// Keeps the last 5 accessed documents so users can resume work from the
/// empty home screen without having to navigate system file pickers repeatedly.
class RecentDocumentsStore {
  static const _channel = MethodChannel('app.overline.pdf/paths');
  static const int _maxRecents = 5;

  Future<Directory?> _recentsDir() async {
    try {
      final supportPath = await _channel.invokeMethod<String>('getSupportDir');
      if (supportPath == null || supportPath.isEmpty) return null;
      final dir = Directory('$supportPath/recents');
      await dir.create(recursive: true);
      return dir;
    } catch (_) {
      return null;
    }
  }

  Future<File?> _manifestFile() async {
    final dir = await _recentsDir();
    if (dir == null) return null;
    return File('${dir.path}/manifest.json');
  }

  /// Loads all recent documents ordered by most recently opened first.
  Future<List<RecentDocumentEntry>> loadRecents() async {
    try {
      final file = await _manifestFile();
      if (file == null || !await file.exists()) return const [];
      final content = await file.readAsString();
      if (content.trim().isEmpty) return const [];
      final decoded = jsonDecode(content);
      if (decoded is! List) return const [];
      final entries = <RecentDocumentEntry>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          final entry = RecentDocumentEntry.fromJson(item);
          if (entry != null) {
            // Verify file still exists if a cached path is present
            if (entry.cachedFilePath != null) {
              final cachedFile = File(entry.cachedFilePath!);
              if (!await cachedFile.exists()) continue;
            }
            entries.add(entry);
          }
        }
      }
      entries.sort((a, b) => b.openedAtMs.compareTo(a.openedAtMs));
      return entries;
    } catch (_) {
      return const [];
    }
  }

  static const int _maxCachedBytes = 25 * 1024 * 1024; // 25 MB max per cached recent file

  /// Records an opened document and optionally caches its bytes for instant re-opening.
  Future<void> recordOpened({
    required String name,
    required int pageCount,
    Uint8List? bytes,
  }) async {
    try {
      final dir = await _recentsDir();
      String? cachedPath;
      if (dir != null && bytes != null && bytes.isNotEmpty && bytes.length <= _maxCachedBytes) {
        final sanitized = name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        final cachedFile = File('${dir.path}/$sanitized');
        final tmpFile = File('${cachedFile.path}.tmp');
        await tmpFile.writeAsBytes(bytes, flush: true);
        await tmpFile.rename(cachedFile.path);
        cachedPath = cachedFile.path;
      }

      final existing = await loadRecents();
      final updated = <RecentDocumentEntry>[
        RecentDocumentEntry(
          name: name,
          pageCount: pageCount,
          openedAtMs: DateTime.now().millisecondsSinceEpoch,
          cachedFilePath: cachedPath,
          byteLength: bytes?.length,
        ),
        for (final e in existing)
          if (e.name != name) e,
      ];

      // Trim excess and delete abandoned cache files
      while (updated.length > _maxRecents) {
        final removed = updated.removeLast();
        if (removed.cachedFilePath != null) {
          try {
            final f = File(removed.cachedFilePath!);
            if (await f.exists()) await f.delete();
          } catch (_) {}
        }
      }

      final manifest = await _manifestFile();
      if (manifest != null) {
        final jsonList = [for (final e in updated) e.toJson()];
        final tmpManifest = File('${manifest.path}.tmp');
        await tmpManifest.writeAsString(jsonEncode(jsonList), flush: true);
        await tmpManifest.rename(manifest.path);
      }
    } catch (_) {
      // Recent storage is an ergonomic convenience; failure is non-blocking
    }
  }

  /// Removes an entry by name.
  Future<void> removeRecent(String name) async {
    try {
      final existing = await loadRecents();
      final updated = <RecentDocumentEntry>[];
      for (final e in existing) {
        if (e.name == name) {
          if (e.cachedFilePath != null) {
            try {
              final f = File(e.cachedFilePath!);
              if (await f.exists()) await f.delete();
            } catch (_) {}
          }
        } else {
          updated.add(e);
        }
      }
      final manifest = await _manifestFile();
      if (manifest != null) {
        await manifest.writeAsString(
          jsonEncode([for (final e in updated) e.toJson()]),
          flush: true,
        );
      }
    } catch (_) {}
  }

  /// Clears all stored recents.
  Future<void> clearRecents() async {
    try {
      final dir = await _recentsDir();
      if (dir != null && await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }
}
