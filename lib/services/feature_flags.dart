import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_diagnostics.dart';

/// Central feature flag, experiment, and emergency kill-switch service.
///
/// At 1M users, if an engine bug, upstream CVE, or device-specific crash is
/// discovered in a specific PDF automation tool (e.g. OCR, conversion, flattening),
/// this service allows disabling that single tool instantly via remote config
/// without waiting for a full app store release review.
class FeatureFlagService {
  FeatureFlagService._();
  static final FeatureFlagService instance = FeatureFlagService._();

  static const String _prefsKey = 'pdfcraft_feature_flags_v1';

  // In-memory active flag configuration
  final Map<String, bool> _flags = <String, bool>{
    'tool:doc_ocr': true,
    'tool:doc_convert': true,
    'tool:doc_optimize': true,
    'tool:doc_sanitize': true,
    'tool:doc_redact': true,
    'tool:doc_compare': true,
    'feature:continuous_reading': true,
    'feature:dark_mode': true,
    'feature:cloud_export': true,
    'feature:diagnostics_export': true,
  };

  // Specific reasons for disabled tools/features (shown to user)
  final Map<String, String> _disabledReasons = <String, String>{};

  /// Initializes flags from persisted cache.
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_prefsKey);
      if (cached != null && cached.isNotEmpty) {
        final decoded = jsonDecode(cached);
        if (decoded is Map<String, dynamic>) {
          applyConfig(decoded, persist: false);
        }
      }
    } catch (e, st) {
      AppDiagnostics.instance.recordError(e, st, category: 'feature_flags');
    }
  }

  /// Check whether a generic feature flag is enabled.
  bool isFeatureEnabled(String featureKey, {bool defaultValue = true}) {
    return _flags[featureKey] ?? defaultValue;
  }

  /// Check whether a specific PdfCraft engine tool is enabled.
  bool isToolEnabled(String toolId) {
    return _flags['tool:$toolId'] ?? true;
  }

  /// Returns user-facing reason if a tool was disabled by a remote kill switch.
  String? getToolDisabledReason(String toolId) {
    if (isToolEnabled(toolId)) return null;
    return _disabledReasons['tool:$toolId'] ??
        'This tool is temporarily undergoing maintenance. Please check back shortly.';
  }

  /// Update flags dynamically (e.g. from Remote Config / API response).
  Future<void> applyConfig(Map<String, dynamic> config, {bool persist = true}) async {
    for (final entry in config.entries) {
      final val = entry.value;
      if (val is bool) {
        _flags[entry.key] = val;
      } else if (val is Map<String, dynamic>) {
        final enabled = val['enabled'] as bool? ?? true;
        _flags[entry.key] = enabled;
        final reason = val['reason'] as String?;
        if (reason != null && !enabled) {
          _disabledReasons[entry.key] = reason;
        }
      }
    }

    AppDiagnostics.instance.record(
      category: 'feature_flags',
      message: 'Feature flags updated: ${_flags.length} active flags',
    );

    if (persist) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKey, jsonEncode(_flags));
      } catch (e, st) {
        AppDiagnostics.instance.recordError(e, st, category: 'feature_flags');
      }
    }
  }

  /// Emergency in-session kill switch for a specific tool.
  void emergencyKillTool(String toolId, {String? reason}) {
    _flags['tool:$toolId'] = false;
    if (reason != null) {
      _disabledReasons['tool:$toolId'] = reason;
    }
    AppDiagnostics.instance.record(
      category: 'feature_flags',
      message: 'EMERGENCY KILL SWITCH ACTIVATED for tool: $toolId ($reason)',
      level: BreadcrumbLevel.warning,
    );
  }

  /// Reset all flags to baseline defaults (for testing and recovery).
  @visibleForTesting
  void reset() {
    _flags.clear();
    _disabledReasons.clear();
    _flags.addAll({
      'tool:doc_ocr': true,
      'tool:doc_convert': true,
      'tool:doc_optimize': true,
      'tool:doc_sanitize': true,
      'tool:doc_redact': true,
      'tool:doc_compare': true,
      'feature:continuous_reading': true,
      'feature:dark_mode': true,
      'feature:cloud_export': true,
      'feature:diagnostics_export': true,
    });
  }
}