import 'dart:io';

import 'package:flutter/services.dart';

/// Remembers the most recent typed and drawn signatures in app-private
/// storage so signing becomes create-once, place-anywhere. Nothing leaves
/// the device; a missing or unreadable store simply means "no saved
/// signature yet" and never blocks the signing flow.
class SignatureStore {
  static const _channel = MethodChannel('com.pdfcraft.pdfcraft_mobile/paths');

  Future<Directory> _signaturesDir() async {
    final supportPath = await _channel.invokeMethod<String>('getSupportDir');
    if (supportPath == null || supportPath.isEmpty) {
      throw StateError('Could not locate app storage for signatures');
    }
    final directory = Directory('$supportPath/signatures');
    await directory.create(recursive: true);
    return directory;
  }

  Future<String?> loadTypedName() async {
    try {
      final file = File('${(await _signaturesDir()).path}/typed_name.txt');
      if (!await file.exists()) return null;
      final name = (await file.readAsString()).trim();
      return name.isEmpty ? null : name;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveTypedName(String name) async {
    try {
      final trimmed = name.trim();
      if (trimmed.isEmpty) return;
      await File('${(await _signaturesDir()).path}/typed_name.txt')
          .writeAsString(trimmed, flush: true);
    } catch (_) {
      // Remembering is a convenience; signing must work regardless.
    }
  }

  Future<Uint8List?> loadDrawn() async {
    try {
      final file = File('${(await _signaturesDir()).path}/drawn.png');
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveDrawn(Uint8List png) async {
    try {
      if (png.isEmpty) return;
      await File('${(await _signaturesDir()).path}/drawn.png')
          .writeAsBytes(png, flush: true);
    } catch (_) {
      // Remembering is a convenience; signing must work regardless.
    }
  }
}
