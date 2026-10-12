import 'dart:convert';

/// Turn engine result data into a short, task-focused message. Paths and
/// identifiers stay in the app layer for Save As and are never shown as raw
/// payloads to the person using the editor.
String humanizeToolResult(String title, String source) {
  Object? value;
  try {
    value = jsonDecode(source);
  } catch (_) {
    return source.trim().isEmpty ? '$title complete.' : source.trim();
  }
  if (value is! Map<String, dynamic>) {
    if (value is List) return '$title complete. ${value.length} items found.';
    return '$title complete.';
  }

  final lines = <String>[];
  final files = value['files'];
  if (files is List) {
    var completed = 0;
    final failures = <String>[];
    for (final item in files) {
      if (item is! Map<String, dynamic>) continue;
      final input = _fileName(item['path'] ?? item['name']);
      final error = item['error'];
      if (error is String) {
        failures.add('$input: $error');
      } else {
        completed++;
      }
    }
    lines.add('$completed of ${files.length} files completed.');
    if (failures.isNotEmpty) {
      lines.addAll(failures.map((failure) => 'Could not process $failure'));
    }
  }

  final changes = value['changes'];
  if (changes is List) {
    final counts = <String, int>{};
    for (final item in changes) {
      if (item is Map<String, dynamic>) {
        final kind = item['kind'] ?? item['type'] ?? 'change';
        final label = switch ('$kind'.toLowerCase()) {
          'inserted' || 'insert' => 'insertions',
          'deleted' || 'delete' => 'deletions',
          'replaced' || 'replace' => 'replacements',
          _ => 'other changes',
        };
        counts.update(label, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    lines.add(
      counts.isEmpty
          ? '${changes.length} differences found.'
          : 'Differences: ${counts.entries.map((entry) => '${entry.value} ${entry.key}').join(', ')}.',
    );
  }

  for (final entry in value.entries) {
    final key = entry.key;
    final data = entry.value;
    if ({
      'files',
      'changes',
      'path',
      'output',
      'out',
      'doc',
      'id',
      'index',
      'revision',
      'generation',
      'document',
    }.contains(key)) {
      continue;
    }
    if (data == null || data is Map) continue;
    if (data is bool) {
      if (key == 'written') {
        lines.add(
          data ? 'A new file was created.' : 'No smaller copy was produced.',
        );
      }
      continue;
    }
    if (data is num) {
      if (key == 'bytes_before' || key == 'bytes_after') {
        lines.add('${_label(key)}: ${_formatBytes(data.toInt())}.');
      } else if (key != 'bytes' && key != 'width' && key != 'height') {
        lines.add('${_label(key)}: $data.');
      }
      continue;
    }
    if (data is String) {
      if (data.isNotEmpty && key != 'query') {
        lines.add('${_label(key)}: $data.');
      }
      continue;
    }
    if (data is List) {
      if (data.isEmpty) continue;
      if (key == 'pages_marked' || key == 'skipped_pages') {
        lines.add('${_label(key)}: ${data.join(', ')}.');
      } else if (key == 'matches' || key == 'pages') {
        lines.add('${data.length} ${_label(key)}.');
      }
    }
  }
  if (lines.isEmpty) return '$title complete.';
  return lines.toSet().join('\n');
}

String _label(String key) => key
    .replaceAll('_', ' ')
    .replaceAllMapped(
      RegExp(r'\b[a-z]'),
      (match) => match.group(0)!.toUpperCase(),
    );

String _fileName(Object? value) {
  if (value is! String || value.isEmpty) return 'file';
  return value.split(RegExp(r'[/\\]')).last;
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes bytes';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  return '${(kb / 1024).toStringAsFixed(2)} MB';
}
