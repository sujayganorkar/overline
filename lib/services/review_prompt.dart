import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_diagnostics.dart';

/// Intelligent, respectful in-app review and satisfaction prompt engine.
///
/// Prompts for app feedback only at peak user delight moments (e.g. after
/// successfully signing, compressing, or saving multiple documents), strictly
/// respecting cooldowns and never prompting after an error has occurred in session.
class ReviewPromptManager {
  ReviewPromptManager._();
  static final ReviewPromptManager instance = ReviewPromptManager._();

  static const String _keyMilestoneCount = 'review_milestones_completed';
  static const String _keyLastPromptMs = 'review_last_prompt_timestamp';
  static const int _milestonesRequired = 3;
  static const int _cooldownDays = 60;

  bool _sessionHasErrors = false;

  /// Mark that an error occurred in this session so we never prompt an unhappy user.
  void markSessionError() {
    _sessionHasErrors = true;
  }

  /// Records a successful user accomplishment (e.g. Save As, Signed, Exported).
  ///
  /// Returns `true` if conditions are optimal to request an in-app review.
  Future<bool> recordMilestone(String milestoneName) async {
    AppDiagnostics.instance.record(
      category: 'review',
      message: 'Milestone reached: $milestoneName',
    );

    if (_sessionHasErrors) {
      return false;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final count = (prefs.getInt(_keyMilestoneCount) ?? 0) + 1;
      await prefs.setInt(_keyMilestoneCount, count);

      final lastPromptMs = prefs.getInt(_keyLastPromptMs) ?? 0;
      final daysSinceLast = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(lastPromptMs))
          .inDays;

      if (count >= _milestonesRequired && daysSinceLast >= _cooldownDays) {
        // Record prompt timestamp to reset cooldown
        await prefs.setInt(
          _keyLastPromptMs,
          DateTime.now().millisecondsSinceEpoch,
        );
        AppDiagnostics.instance.record(
          category: 'review',
          message: 'Review prompt threshold met (count: $count, daysSince: $daysSinceLast)',
        );
        return true;
      }
    } catch (e, st) {
      AppDiagnostics.instance.recordError(e, st, category: 'review');
    }
    return false;
  }

  @visibleForTesting
  void reset() {
    _sessionHasErrors = false;
  }
}

