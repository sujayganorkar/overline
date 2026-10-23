import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'app_diagnostics.dart';

class UpdateInfo {
  final bool hasUpdate;
  final String latestVersion;
  final String releaseUrl;
  final String? releaseNotes;

  const UpdateInfo({
    required this.hasUpdate,
    required this.latestVersion,
    required this.releaseUrl,
    this.releaseNotes,
  });
}

class UpdateCheckerService {
  UpdateCheckerService._();
  static final UpdateCheckerService instance = UpdateCheckerService._();

  static const _channel = MethodChannel('app.overline.pdf/paths');
  static const String repoOwner = 'sujayganorkar';
  static const String repoName = 'overline';

  /// Open release URL in user's browser
  static Future<void> launchUrl(String url) async {
    try {
      await _channel.invokeMethod('openUrl', {'url': url});
    } catch (e) {
      debugPrint('Failed to open url: $e');
    }
  }

  /// Check GitHub Releases API for the latest release.
  Future<UpdateInfo?> checkForUpdate({
    String currentVersion = '1.0.0',
    String? customRepo,
  }) async {
    try {
      final repo = customRepo ?? '$repoOwner/$repoName';
      final url = Uri.parse('https://api.github.com/repos/$repo/releases/latest');
      final response = await http.get(
        url,
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'Overline-Android-App',
        },
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final tagName = (data['tag_name'] as String? ?? '').replaceFirst('v', '').trim();
        final htmlUrl = data['html_url'] as String? ?? 'https://github.com/$repo/releases';
        final body = data['body'] as String?;

        if (tagName.isNotEmpty && _isNewerVersion(tagName, currentVersion)) {
          AppDiagnostics.instance.record(
            category: 'update_checker',
            message: 'New update available: $tagName (current: $currentVersion)',
          );
          return UpdateInfo(
            hasUpdate: true,
            latestVersion: tagName,
            releaseUrl: htmlUrl,
            releaseNotes: body,
          );
        }
      }
    } catch (e) {
      // Best-effort check; offline or rate limits must never disrupt viewer UX
      debugPrint('Update check non-fatal error: $e');
    }
    return null;
  }

  bool _isNewerVersion(String remote, String local) {
    try {
      final remoteParts = remote.split('+').first.split('.').map(int.parse).toList();
      final localParts = local.split('+').first.split('.').map(int.parse).toList();

      for (var i = 0; i < 3; i++) {
        final r = i < remoteParts.length ? remoteParts[i] : 0;
        final l = i < localParts.length ? localParts[i] : 0;
        if (r > l) return true;
        if (r < l) return false;
      }
    } catch (_) {}
    return false;
  }
}
