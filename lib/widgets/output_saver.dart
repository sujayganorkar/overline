import 'dart:convert';

import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';

import '../services/pdf_engine.dart';

/// Find workspace-relative output paths in a tool result and offer Save As
/// for each one. Upstream file-producing tools report their outputs as
/// `path` strings or `files` arrays; this keeps every export flow to one
/// shared, tested path.
List<String> outputPathsIn(String jsonSource) {
  try {
    final value = jsonDecode(jsonSource);
    final paths = <String>[];
    void visit(Object? node) {
      if (node is Map<String, dynamic>) {
        final hasOutput = node['output'] is String || node['out'] is String;
        for (final entry in node.entries) {
          final v = entry.value;
          if ((entry.key == 'output' || entry.key == 'out') && v is String) {
            paths.add(v);
          } else if (entry.key == 'path' && v is String && !hasOutput) {
            paths.add(v);
          } else if (entry.key == 'files' && v is List) {
            for (final item in v) {
              if (item is String) {
                paths.add(item);
              } else {
                visit(item);
              }
            }
          } else {
            visit(v);
          }
        }
      } else if (node is List) {
        for (final item in node) {
          visit(item);
        }
      }
    }

    visit(value);
    return paths.toSet().toList(growable: false);
  } catch (_) {
    return const [];
  }
}

String mimeTypeFor(String path) {
  final ext = path.split('.').last.toLowerCase();
  return switch (ext) {
    'pdf' => 'application/pdf',
    'csv' => 'text/csv',
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'tif' || 'tiff' => 'image/tiff',
    'html' => 'text/html',
    'txt' => 'text/plain',
    'fdf' || 'xfdf' => 'application/vnd.adobe.xfdf',
    _ => 'application/octet-stream',
  };
}

/// Show Save As dialogs for every output path found in [jsonSources].
/// Returns silently when there is nothing to save.
Future<void> saveToolOutputs(
  BuildContext context,
  PdfEngineApi engine,
  List<String> jsonSources,
) async {
  final paths = <String>[];
  for (final source in jsonSources) {
    for (final path in outputPathsIn(source)) {
      if (!paths.contains(path)) paths.add(path);
    }
  }
  if (paths.isEmpty) return;
  await saveOutputPaths(context, engine, paths);
}

/// Offer the system Save As sheet for explicit engine workspace output paths.
Future<void> saveOutputPaths(
  BuildContext context,
  PdfEngineApi engine,
  List<String> paths,
) async {
  for (final path in paths) {
    if (!context.mounted) return;
    try {
      final bytes = await engine.readOutput(path: path);
      final name = path.split('/').last;
      final uri = await FilePickerPlatform.instance.saveFile(
        fileName: name.isEmpty ? 'output' : name,
        bytes: bytes,
        mimeType: mimeTypeFor(path),
        dialogTitle: 'Save $name',
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            uri == null
                ? 'Save cancelled for $name'
                : 'Saved $name through Files',
          ),
        ),
      );
      if (uri == null) return;
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save ${path.split('/').last}: $e')),
      );
      return;
    }
  }
}
