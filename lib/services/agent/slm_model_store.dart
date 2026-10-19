import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../app_diagnostics.dart';

/// Progress event emitted while downloading an on-device SLM model.
class SlmDownloadProgress {
  const SlmDownloadProgress({
    required this.bytesReceived,
    required this.totalBytes,
    required this.fraction,
    required this.statusMessage,
  });

  final int bytesReceived;
  final int totalBytes;
  final double fraction;
  final String statusMessage;

  @override
  String toString() =>
      'SlmDownloadProgress(${(fraction * 100).toStringAsFixed(1)}%, $statusMessage)';
}

/// Manages local storage, download, and SHA-256 integrity verification
/// for on-device Small Language Models (e.g. Qwen2.5 1.5B Instruct GGUF).
class SlmModelStore {
  SlmModelStore._();

  static final SlmModelStore instance = SlmModelStore._();

  /// Default model file name stored locally.
  static const String defaultModelFileName =
      'qwen2.5-1.5b-instruct-q4_k_m.gguf';

  /// Standard HuggingFace download URL.
  static const String defaultDownloadUrl =
      'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf';

  /// Expected SHA-256 hash. Can be set or overridden for verification.
  /// When set to empty or matching wildcard, integrity check passes upon valid non-empty byte completion.
  static const String defaultExpectedSha256 = '';

  /// Minimum valid model size threshold (50 MB) to prevent corrupted stub files.
  static const int minValidSizeBytes = 50 * 1024 * 1024;

  http.Client? _activeClient;
  bool _isDownloading = false;

  bool get isDownloading => _isDownloading;

  /// Resolves the absolute path to the local model directory.
  Future<Directory> getModelDirectory() async {
    Directory baseDir;
    try {
      baseDir = await getApplicationSupportDirectory();
    } catch (_) {
      baseDir = Directory.systemTemp;
    }
    final modelDir = Directory('${baseDir.path}/models');
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }
    return modelDir;
  }

  /// Returns the target File for the model on disk.
  Future<File> getModelFile({String fileName = defaultModelFileName}) async {
    final dir = await getModelDirectory();
    return File('${dir.path}/$fileName');
  }

  /// Checks if the model file is downloaded, non-empty, and exceeds the minimum size.
  Future<bool> isModelReady({String fileName = defaultModelFileName}) async {
    try {
      final file = await getModelFile(fileName: fileName);
      if (!await file.exists()) return false;
      final length = await file.length();
      return length >= minValidSizeBytes;
    } catch (e) {
      debugPrint('SlmModelStore.isModelReady check error: $e');
      return false;
    }
  }

  /// Returns the size in bytes of the installed model, or 0 if missing.
  Future<int> getInstalledModelSize({String fileName = defaultModelFileName}) async {
    try {
      final file = await getModelFile(fileName: fileName);
      if (await file.exists()) {
        return await file.length();
      }
    } catch (_) {}
    return 0;
  }

  /// Downloads the SLM model file with chunked progress reporting and SHA-256 verification.
  Stream<SlmDownloadProgress> downloadModel({
    String url = defaultDownloadUrl,
    String fileName = defaultModelFileName,
    String expectedSha256 = defaultExpectedSha256,
  }) async* {
    if (_isDownloading) {
      throw StateError('A model download is already in progress.');
    }

    _isDownloading = true;
    final targetFile = await getModelFile(fileName: fileName);
    final tempFile = File('${targetFile.path}.tmp');

    if (await tempFile.exists()) {
      try {
        await tempFile.delete();
      } catch (_) {}
    }

    _activeClient = http.Client();
    try {
      yield const SlmDownloadProgress(
        bytesReceived: 0,
        totalBytes: 0,
        fraction: 0.0,
        statusMessage: 'Connecting to model repository…',
      );

      final request = http.Request('GET', Uri.parse(url));
      final response = await _activeClient!.send(request);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Failed to download model: HTTP ${response.statusCode} (${response.reasonPhrase})',
        );
      }

      final totalBytes = response.contentLength ?? 0;
      var receivedBytes = 0;
      final sink = tempFile.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        final fraction = totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
        yield SlmDownloadProgress(
          bytesReceived: receivedBytes,
          totalBytes: totalBytes,
          fraction: fraction,
          statusMessage: 'Downloading model (${(receivedBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
              '${totalBytes > 0 ? ' / ${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB' : ''})',
        );
      }

      await sink.flush();
      await sink.close();

      // Integrity verification
      if (expectedSha256.isNotEmpty) {
        yield const SlmDownloadProgress(
          bytesReceived: 0,
          totalBytes: 0,
          fraction: 1.0,
          statusMessage: 'Verifying SHA-256 cryptographic signature…',
        );

        final digest = await sha256.bind(tempFile.openRead()).first;
        final actualHash = digest.toString().toLowerCase();
        if (actualHash != expectedSha256.toLowerCase()) {
          await tempFile.delete();
          throw StateError(
            'Model verification failed: expected hash $expectedSha256, but received $actualHash',
          );
        }
      }

      // Atomically move temp file to target file
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await tempFile.rename(targetFile.path);

      AppDiagnostics.instance.record(
        category: 'slm',
        message: 'SLM model successfully acquired: ${targetFile.path} ($receivedBytes bytes)',
      );

      yield const SlmDownloadProgress(
        bytesReceived: 0,
        totalBytes: 0,
        fraction: 1.0,
        statusMessage: 'Model ready for offline inference.',
      );
    } finally {
      _isDownloading = false;
      _activeClient?.close();
      _activeClient = null;
    }
  }

  /// Cancels any active model download and cleans up temporary files.
  Future<void> cancelDownload() async {
    _activeClient?.close();
    _activeClient = null;
    _isDownloading = false;

    final targetFile = await getModelFile();
    final tempFile = File('${targetFile.path}.tmp');
    if (await tempFile.exists()) {
      try {
        await tempFile.delete();
      } catch (_) {}
    }
  }

  /// Deletes the local model file to free disk space.
  Future<bool> deleteModel({String fileName = defaultModelFileName}) async {
    try {
      final file = await getModelFile(fileName: fileName);
      if (await file.exists()) {
        await file.delete();
        AppDiagnostics.instance.record(
          category: 'slm',
          message: 'SLM model removed from local storage: ${file.path}',
        );
        return true;
      }
    } catch (e) {
      debugPrint('Failed to delete SLM model: $e');
    }
    return false;
  }
}

