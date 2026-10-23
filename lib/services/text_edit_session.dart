import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../bridge/api.dart' as bridge;
import 'pdf_engine.dart';

class Paragraph {
  const Paragraph({
    required this.number,
    required this.text,
    required this.font,
    required this.size,
    required this.rect,
  });
  final int number;
  final String text, font;
  final double size;
  final List<double> rect;
  static Paragraph? fromJson(Map<String, dynamic> json) {
    final number = (json['paragraph'] as num?)?.toInt();
    final rect = (json['rect'] as List?)
        ?.whereType<num>()
        .map((v) => v.toDouble())
        .toList();
    if (number == null ||
        rect == null ||
        rect.length != 4 ||
        rect.any((v) => !v.isFinite) ||
        rect[2] <= rect[0] ||
        rect[3] <= rect[1]) {
      return null;
    }
    return Paragraph(
      number: number,
      text: json['text'] as String? ?? '',
      font: json['font'] as String? ?? '',
      size: (json['size'] as num?)?.toDouble() ?? 12,
      rect: rect,
    );
  }
}

class TextEditPreview {
  TextEditPreview._(
    this.png,
    this.tool,
    this.argumentsJson,
    this.font,
    this.paragraphs,
    this._baseline,
  );
  final Uint8List png;
  final String tool, argumentsJson, font;
  final List<Paragraph> paragraphs;
  final Uint8List _baseline;
}

/// Candidate edits run on fresh copies. The original receives one reviewed operation.
class TextEditSession {
  TextEditSession({
    required this.engine,
    required this.handle,
    required this.page,
  });
  final PdfEngineApi engine;
  final int handle, page;
  Uint8List? _baseline;
  Uint8List? _sourcePng;
  String _sourceText = '';
  String _fingerprint(List<Paragraph> blocks) => jsonEncode([
    for (final p in blocks) [p.number, p.text, p.font, p.size, p.rect],
  ]);

  Future<Uint8List> _snapshot() async {
    final snapshot = await engine.saveSnapshot(handle: handle);
    try {
      return snapshot.bytes;
    } finally {
      await engine.cancelSave(handle: handle, token: snapshot.token);
    }
  }

  Future<List<Paragraph>> refresh() async {
    _baseline = await _snapshot();
    final blocks = await paragraphs(handle);
    _sourceText = _fingerprint(blocks);
    _sourcePng = await engine.renderPagePng(
      handle: handle,
      page1Based: page,
      dpi: 96,
    );
    return blocks;
  }

  Future<List<Paragraph>> paragraphs(int document) async {
    final response = await engine.executeTool(
      handle: document,
      tool: 'text_paragraphs',
      argumentsJson: jsonEncode({'page': page}),
    );
    return [
      for (final content in response.contents)
        if (content.json.isNotEmpty) ..._parse(content.json),
    ];
  }

  static List<Paragraph> _parse(String json) {
    final decoded = jsonDecode(json);
    final list = decoded is Map ? decoded['paragraphs'] : decoded;
    if (list is! List) return [];
    return [
      for (final item in list)
        if (item is Map<String, dynamic>)
          if (Paragraph.fromJson(item) case final Paragraph p) p,
    ];
  }

  Future<TextEditPreview> preview(
    String tool,
    Map<String, Object?> args,
  ) async {
    final baseline = _baseline;
    if (baseline == null) throw StateError('Load the page before editing.');
    final json = jsonEncode(args);
    final copy = await engine.open(
      name: 'text-layout-preview.pdf',
      bytes: baseline,
    );
    try {
      final response = await engine.executeTool(
        handle: copy,
        tool: tool,
        argumentsJson: json,
      );
      var font = '';
      for (final content in response.contents) {
        if (content.json.isEmpty) continue;
        final data = jsonDecode(content.json);
        if (data is Map && data['paragraph'] is Map) {
          font = data['paragraph']['font'] as String? ?? '';
        }
      }
      final blocks = await paragraphs(copy);
      final png = await engine.renderPagePng(
        handle: copy,
        page1Based: page,
        dpi: 96,
      );
      if (png.isEmpty) throw StateError('The page preview was empty.');
      return TextEditPreview._(png, tool, json, font, blocks, baseline);
    } finally {
      await engine.close(handle: copy, discardChanges: true);
    }
  }

  Future<bridge.DocumentStatus> apply(TextEditPreview preview) async {
    if (!identical(preview._baseline, _baseline) ||
        _fingerprint(await paragraphs(handle)) != _sourceText ||
        !listEquals(
          await engine.renderPagePng(handle: handle, page1Based: page, dpi: 96),
          _sourcePng,
        )) {
      throw StateError(
        'The document changed. Reload the page and review your edit again.',
      );
    }
    final result = await engine.executeTool(
      handle: handle,
      tool: preview.tool,
      argumentsJson: preview.argumentsJson,
    );
    // Invalidate immediately: this candidate must never be committed twice.
    _baseline = null;
    return result.status;
  }
}
