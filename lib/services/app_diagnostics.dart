import 'dart:collection';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum BreadcrumbLevel { info, warning, error }

/// Represents a single diagnostic event or breadcrumb in the user's session.
class DiagnosticBreadcrumb {
  DiagnosticBreadcrumb({
    required this.category,
    required this.message,
    this.level = BreadcrumbLevel.info,
    this.details,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final String category;
  final String message;
  final BreadcrumbLevel level;
  final Map<String, dynamic>? details;
  final DateTime timestamp;

  String get formattedTime =>
      '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}.${timestamp.millisecond.toString().padLeft(3, '0')}';

  @override
  String toString() =>
      '[$formattedTime] [${level.name.toUpperCase()}] [$category] $message${details != null ? ' $details' : ''}';
}

/// Central diagnostic logging, breadcrumb collection, and crash-shielding service.
///
/// Collects in-memory breadcrumbs (ring buffer of last 150 events) to diagnose
/// issues on 1M+ devices in production without needing local debugging tools.
class AppDiagnostics {
  AppDiagnostics._();
  static final AppDiagnostics instance = AppDiagnostics._();

  static const int _maxBreadcrumbs = 150;
  final Queue<DiagnosticBreadcrumb> _breadcrumbs = Queue<DiagnosticBreadcrumb>();
  final List<VoidCallback> _memoryPressureListeners = <VoidCallback>[];

  /// Register a listener to be notified when the OS sends a low-memory warning.
  void addMemoryPressureListener(VoidCallback listener) {
    _memoryPressureListeners.add(listener);
  }

  /// Unregister a low-memory warning listener.
  void removeMemoryPressureListener(VoidCallback listener) {
    _memoryPressureListeners.remove(listener);
  }

  /// Record a diagnostic breadcrumb.
  void record({
    required String category,
    required String message,
    BreadcrumbLevel level = BreadcrumbLevel.info,
    Map<String, dynamic>? details,
  }) {
    final entry = DiagnosticBreadcrumb(
      category: category,
      message: message,
      level: level,
      details: details,
    );
    if (_breadcrumbs.length >= _maxBreadcrumbs) {
      _breadcrumbs.removeFirst();
    }
    _breadcrumbs.addLast(entry);

    if (kDebugMode) {
      debugPrint(entry.toString());
    }
  }

  /// Record an error with its stack trace.
  void recordError(
    Object error,
    StackTrace? stackTrace, {
    String category = 'app',
    String? message,
  }) {
    record(
      category: category,
      message: message ?? error.toString(),
      level: BreadcrumbLevel.error,
      details: stackTrace != null ? {'stack': stackTrace.toString().split('\n').take(8).join('\n')} : null,
    );
  }

  /// Notify that system memory pressure was encountered.
  void notifyMemoryPressure() {
    record(
      category: 'system',
      message: 'Memory pressure warning received from OS (trim memory)',
      level: BreadcrumbLevel.warning,
    );
    for (final listener in List<VoidCallback>.from(_memoryPressureListeners)) {
      try {
        listener();
      } catch (e, st) {
        recordError(e, st, category: 'memory_listener');
      }
    }
  }

  /// Retrieve all current session breadcrumbs in chronological order.
  List<DiagnosticBreadcrumb> get breadcrumbs => List.unmodifiable(_breadcrumbs);

  /// Formatted timeline of breadcrumbs suitable for export or bug report.
  String exportTimeline() =>
      _breadcrumbs.map((b) => b.toString()).join('\n');

  /// Installs global crash shielding handlers:
  /// 1. [FlutterError.onError] for framework/render tree errors.
  /// 2. [PlatformDispatcher.instance.onError] for unhandled root async errors.
  /// 3. [ErrorWidget.builder] to render graceful production recovery cards.
  static void installGlobalErrorHandlers() {
    // 1. Flutter framework error handler
    final originalFlutterError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      instance.recordError(
        details.exception,
        details.stack,
        category: 'flutter_framework',
        message: details.summary.toString(),
      );
      if (kDebugMode) {
        originalFlutterError?.call(details);
      }
    };

    // 2. Unhandled asynchronous isolate/microtask errors
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      instance.recordError(
        error,
        stack,
        category: 'async_unhandled',
      );
      // Return true to indicate the error has been handled and avoid crashing process
      return true;
    };

    // 3. Graceful fallback widget for rendering errors (replaces red/grey error box)
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return ProductionErrorCard(details: details);
    };
  }
}

/// User-friendly fallback widget shown when a component encounters a rendering error.
class ProductionErrorCard extends StatelessWidget {
  const ProductionErrorCard({super.key, required this.details});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.error.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: theme.colorScheme.error,
                size: 36,
              ),
              const SizedBox(height: 8),
              Text(
                'Something went wrong displaying this view',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onErrorContainer,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'The issue has been logged. Try switching views or reopening the document.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

