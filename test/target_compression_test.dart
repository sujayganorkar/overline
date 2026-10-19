import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:overline/bridge/api.dart' as bridge;
import 'package:overline/services/target_compression.dart';

import 'viewer_initialization_test.dart' show FakePdfEngine;

Uint8List pdfBytes(int size) =>
    Uint8List(size)..setRange(0, 5, ascii.encode('%PDF-'));

class CompressionEngine extends FakePdfEngine {
  CompressionEngine(this.sizes);
  final List<int> sizes;
  int calls = 0, previewPages = 2, rendered = 0;
  final closed = <int>[];
  Uint8List? opened;
  @override
  Future<bridge.OperationResponse> executeTool({
    required int handle,
    required String tool,
    required String argumentsJson,
  }) async {
    expect(tool, 'doc_optimize');
    expect(handle, 1);
    calls++;
    return super.executeTool(
      handle: handle,
      tool: tool,
      argumentsJson: argumentsJson,
    );
  }

  @override
  Future<Uint8List> readOutput({required String path}) async {
    final size = sizes[(calls - 1).clamp(0, sizes.length - 1)];
    return size == 0 ? Uint8List(0) : pdfBytes(size);
  }

  @override
  Future<int> open({
    required String name,
    required Uint8List bytes,
    String? password,
  }) async {
    opened = bytes;
    return 2;
  }

  @override
  Future<int> pageCount({required int handle}) async => previewPages;
  @override
  Future<void> close({required int handle, bool discardChanges = false}) async {
    closed.add(handle);
  }

  @override
  Future<Uint8List> renderPagePng({
    required int handle,
    required int page1Based,
    required int dpi,
  }) async {
    rendered++;
    return base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAD0lEQVR4nGP4jwQYiOMAANuQL9FuRbCyAAAAAElFTkSuQmCC',
    );
  }
}

TargetCompression compressor(CompressionEngine e) => TargetCompression(
  engine: e,
  handle: 1,
  pageCount: 2,
  progress: (_) {},
  isActive: () => true,
);
void main() {
  test('continues beyond six presets and accepts exact byte limit only after page verification', () async {
    final engine = CompressionEngine([
      8000,
      7000,
      6000,
      5000,
      4000,
      3000,
      2000,
    ]);
    final result = await compressor(engine).optimize(pdfBytes(10000), 2000);
    expect(result.reached, isTrue);
    expect(result.bytes.length, 2000);
    expect(engine.calls, 7);
    expect(engine.closed, [2]);
  });
  test('oversized best effort is never a reached target', () async {
    final engine = CompressionEngine([3000]);
    final result = await compressor(engine).optimize(pdfBytes(10000), 2000);
    expect(result.reached, isFalse);
    expect(engine.calls, 8);
  });
  test(
    'empty output and missing pages fail instead of claiming success',
    () async {
      await expectLater(
        compressor(CompressionEngine([0])).optimize(pdfBytes(10000), 2000),
        throwsStateError,
      );
      final engine = CompressionEngine([1000])..previewPages = 1;
      await expectLater(
        compressor(engine).optimize(pdfBytes(10000), 2000),
        throwsStateError,
      );
      expect(engine.closed, [2]);
    },
  );
  test(
    'image fallback creates a PDF with all pages under the ceiling',
    () async {
      final engine = CompressionEngine([30000]);
      final result = await compressor(engine).imageCopy(pdfBytes(30000), 10000);
      expect(result.reached, isTrue);
      expect(result.imageOnly, isTrue);
      expect(engine.rendered, 2);
      final contents = latin1.decode(result.bytes);
      expect(
        RegExp(r'/Type/Page\b|/Type /Page\b').allMatches(contents).length,
        2,
      );
      expect(engine.closed, [2]);
    },
  );
  test(
    'impossible target terminates without success or deleting pages',
    () async {
      final engine = CompressionEngine([30000]);
      final result = await compressor(engine).imageCopy(pdfBytes(30000), 1);
      expect(result.reached, isFalse);
      expect(engine.rendered, 14);
    },
  );
  test('cancelled work does not start another pass', () async {
    final engine = CompressionEngine([1000]);
    final c = TargetCompression(
      engine: engine,
      handle: 1,
      pageCount: 2,
      progress: (_) {},
      isActive: () => false,
    );
    await expectLater(c.optimize(pdfBytes(10000), 2000), throwsStateError);
    expect(engine.calls, 0);
  });
}
