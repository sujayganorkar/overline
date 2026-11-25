import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

const _models = {
  'text-detection.onnx': (
    2499479,
    'a917b23dbd9524b465df7e922641b3ff2981623df4ded5a0234004ef2fee7cfe',
  ),
  'text-recognition.onnx': (
    9713177,
    '86c145c2edb96c8caed5b1ebb8f44d706408922211451c309c625157dd6061c5',
  ),
};

/// The native reader opens models by filename. Install the bundled, verified
/// assets into its private model directory on the first OCR request.
Future<void> prepareOfflineOcr() async {
  const paths = MethodChannel('app.overline.pdf/paths');
  final directory = await paths.invokeMethod<String>('getOcrModelDir');
  if (directory == null) throw StateError('Cannot access offline OCR models.');
  final root = await Directory(directory).create(recursive: true);
  for (final entry in _models.entries) {
    final file = File('${root.path}/${entry.key}');
    if (await file.exists() && await file.length() == entry.value.$1) continue;
    final data = await rootBundle.load('assets/ocr/${entry.key}');
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    if (sha256.convert(bytes).toString() != entry.value.$2) {
      throw StateError('The bundled OCR model ${entry.key} is damaged.');
    }
    final temp = await root.createTemp('install-');
    try {
      final staged = await File('${temp.path}/${entry.key}')
          .writeAsBytes(bytes, flush: true);
      await staged.rename(file.path);
    } finally {
      await temp.delete(recursive: true);
    }
  }
}
