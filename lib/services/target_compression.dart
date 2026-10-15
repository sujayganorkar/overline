import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_engine.dart';

class CompressionResult {
  const CompressionResult(
    this.bytes,
    this.targetBytes, {
    this.imageOnly = false,
  });
  final Uint8List bytes;
  final int targetBytes;
  final bool imageOnly;
  bool get reached => bytes.isNotEmpty && bytes.length <= targetBytes;
}

/// Measures actual exported bytes. An over-limit result is never a success.
class TargetCompression {
  TargetCompression({
    required this.engine,
    required this.handle,
    required this.pageCount,
    required this.progress,
    required this.isActive,
  });
  final PdfEngineApi engine;
  final int handle, pageCount;
  final ValueChanged<String> progress;
  final bool Function() isActive;
  void _check() {
    if (!isActive()) throw StateError('Compression cancelled');
  }

  Future<void> verify(Uint8List bytes) async {
    if (bytes.length < 5 ||
        ascii.decode(bytes.sublist(0, 5), allowInvalid: true) != '%PDF-') {
      throw StateError('Compression did not produce a PDF.');
    }
    final preview = await engine.open(
      name: 'verify-compressed.pdf',
      bytes: bytes,
    );
    try {
      if (await engine.pageCount(handle: preview) != pageCount) {
        throw StateError('The compressed copy did not retain every page.');
      }
    } finally {
      await engine.close(handle: preview, discardChanges: true);
    }
  }

  Future<CompressionResult> optimize(Uint8List original, int target) async {
    if (target <= 0) throw ArgumentError.value(target, 'target');
    var best = original;
    if (best.length <= target) return CompressionResult(best, target);
    const profiles = [
      (80, 200),
      (65, 170),
      (50, 140),
      (38, 110),
      (28, 85),
      (18, 65),
      (10, 48),
      (1, 36),
    ];
    for (var i = 0; i < profiles.length; i++) {
      _check();
      final (quality, ppi) = profiles[i];
      progress('Optimizing images · pass ${i + 1} of ${profiles.length}');
      final imageOptions = {
        'downsample': true,
        'ppi': ppi,
        'above_ppi': ppi,
        'compression': 'jpeg',
        'quality': quality,
      };
      const path = 'outputs/target-compressed.pdf';
      await engine.executeTool(
        handle: handle,
        tool: 'doc_optimize',
        argumentsJson: jsonEncode({
          'path': path,
          'color': imageOptions,
          'gray': imageOptions,
          'discard_thumbnails': true,
          'discard_alternate_images': true,
          'flate_unencoded': true,
        }),
      );
      _check();
      final candidate = await engine.readOutput(path: path);
      if (candidate.isEmpty) {
        throw StateError('The optimizer returned an empty file.');
      }
      if (candidate.length < best.length) best = candidate;
      if (candidate.length <= target) {
        await verify(candidate);
        return CompressionResult(candidate, target);
      }
    }
    return CompressionResult(best, target);
  }

  Future<CompressionResult> imageCopy(Uint8List best, int target) async {
    const profiles = [
      (110, 65),
      (85, 45),
      (65, 30),
      (48, 20),
      (36, 12),
      (24, 6),
      (16, 1),
    ];
    var smallest = best;
    for (var pass = 0; pass < profiles.length; pass++) {
      final (dpi, quality) = profiles[pass];
      final pages = <({Uint8List jpeg, double width, double height})>[];
      for (var page = 1; page <= pageCount; page++) {
        _check();
        progress(
          'Creating image copy · pass ${pass + 1}/${profiles.length} · page $page/$pageCount',
        );
        final size = await engine.pageSize(handle: handle, page1Based: page);
        final boundedDpi = math.max(
          1,
          math.min(
            dpi,
            (2400 * 72 / math.max(size.width, size.height)).floor(),
          ),
        );
        final png = await engine.renderPagePng(
          handle: handle,
          page1Based: page,
          dpi: boundedDpi,
        );
        final jpeg = await compute(_jpeg, (png, quality));
        pages.add((jpeg: jpeg, width: size.width, height: size.height));
      }
      _check();
      final candidate = await compute(_imagePdf, pages);
      if (candidate.length < smallest.length) smallest = candidate;
      if (candidate.length <= target) {
        await verify(candidate);
        return CompressionResult(candidate, target, imageOnly: true);
      }
    }
    return CompressionResult(smallest, target, imageOnly: true);
  }
}

Uint8List _jpeg((Uint8List, int) input) {
  final decoded = img.decodePng(input.$1);
  if (decoded == null) throw StateError('Could not read a rendered page.');
  // Flatten transparency onto white, never black.
  final canvas = img.Image(
    width: decoded.width,
    height: decoded.height,
    numChannels: 3,
  );
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(canvas, decoded);
  return img.encodeJpg(canvas, quality: input.$2);
}

Future<Uint8List> _imagePdf(
  List<({Uint8List jpeg, double width, double height})> pages,
) async {
  final pdf = pw.Document(compress: true);
  for (final page in pages) {
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(page.width, page.height, marginAll: 0),
        build: (_) => pw.Image(
          pw.MemoryImage(page.jpeg),
          fit: pw.BoxFit.fill,
          width: page.width,
          height: page.height,
        ),
      ),
    );
  }
  return pdf.save();
}
