import 'dart:io';

import 'package:flutter/services.dart';

/// Remembers the most recent typed and drawn signatures in app-private
/// storage so signing becomes create-once, place-anywhere. Nothing leaves
/// the device; a missing or unreadable store simply means "no saved
/// signature yet" and never blocks the signing flow.
class SignatureStore {
  static const _channel = MethodChannel('app.overline.pdf/paths');

  Future<Directory> _signaturesDir() async {
    final supportPath = await _channel.invokeMethod<String>('getSupportDir');
    if (supportPath == null || supportPath.isEmpty) {
      throw StateError('Could not locate app storage for signatures');
    }
    final directory = Directory('$supportPath/signatures');
    await directory.create(recursive: true);
    return directory;
  }

  // Obfuscation mask to prevent raw plaintext PNG/text storage on flash memory
  static const int _sigXorKey = 0x5A;

  Future<String?> loadTypedName() async {
    try {
      final file = File('${(await _signaturesDir()).path}/typed_name.enc');
      final legacyFile = File('${(await _signaturesDir()).path}/typed_name.txt');
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        final unobfuscated = Uint8List.fromList([for (final b in bytes) b ^ _sigXorKey]);
        final name = String.fromCharCodes(unobfuscated).trim();
        return name.isEmpty ? null : name;
      } else if (await legacyFile.exists()) {
        final name = (await legacyFile.readAsString()).trim();
        return name.isEmpty ? null : name;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveTypedName(String name) async {
    try {
      final trimmed = name.trim();
      if (trimmed.isEmpty) return;
      final dir = await _signaturesDir();
      final targetFile = File('${dir.path}/typed_name.enc');
      final tmpFile = File('${targetFile.path}.tmp');
      final obfuscated = Uint8List.fromList([for (final c in trimmed.codeUnits) c ^ _sigXorKey]);
      await tmpFile.writeAsBytes(obfuscated, flush: true);
      await tmpFile.rename(targetFile.path);

      // Clean up legacy plaintext file if present
      final legacyFile = File('${dir.path}/typed_name.txt');
      if (await legacyFile.exists()) {
        await legacyFile.delete();
      }
    } catch (_) {
      // Remembering is a convenience; signing must work regardless.
    }
  }

  Future<Uint8List?> loadDrawn() async {
    try {
      final file = File('${(await _signaturesDir()).path}/drawn.enc');
      final legacyFile = File('${(await _signaturesDir()).path}/drawn.png');
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) return null;
        return Uint8List.fromList([for (final b in bytes) b ^ _sigXorKey]);
      } else if (await legacyFile.exists()) {
        final bytes = await legacyFile.readAsBytes();
        return bytes.isEmpty ? null : bytes;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveDrawn(Uint8List png) async {
    try {
      if (png.isEmpty) return;
      final dir = await _signaturesDir();
      final targetFile = File('${dir.path}/drawn.enc');
      final tmpFile = File('${targetFile.path}.tmp');
      final obfuscated = Uint8List.fromList([for (final b in png) b ^ _sigXorKey]);
      await tmpFile.writeAsBytes(obfuscated, flush: true);
      await tmpFile.rename(targetFile.path);

      // Clean up legacy plaintext file if present
      final legacyFile = File('${dir.path}/drawn.png');
      if (await legacyFile.exists()) {
        await legacyFile.delete();
      }
    } catch (_) {
      // Remembering is a convenience; signing must work regardless.
    }
  }
}
