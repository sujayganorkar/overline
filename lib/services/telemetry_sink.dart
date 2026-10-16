import 'app_diagnostics.dart';

/// Abstract contract for production telemetry, crash reporting, and analytics providers
/// (e.g. Firebase Crashlytics, Sentry, Datadog, internal logging endpoints).
abstract interface class TelemetrySink {
  /// Record a significant business or user action.
  void recordEvent(String name, {Map<String, dynamic>? parameters});

  /// Record an error or exception.
  void recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  });

  /// Associate a key-value attribute with future crash reports.
  void setCustomKey(String key, Object value);
}

/// Default local telemetry sink that streams events into [AppDiagnostics].
class DiagnosticTelemetrySink implements TelemetrySink {
  const DiagnosticTelemetrySink();

  @override
  void recordEvent(String name, {Map<String, dynamic>? parameters}) {
    AppDiagnostics.instance.record(
      category: 'telemetry',
      message: 'Event: $name',
      details: parameters,
    );
  }

  @override
  void recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) {
    AppDiagnostics.instance.recordError(
      error,
      stack,
      category: fatal ? 'fatal_crash' : 'telemetry_error',
      message: reason,
    );
  }

  @override
  void setCustomKey(String key, Object value) {
    AppDiagnostics.instance.record(
      category: 'telemetry_attr',
      message: 'Set attribute [$key] = $value',
    );
  }
}

/// Central manager that dispatches telemetry and crash signals to all registered sinks.
class TelemetryManager {
  TelemetryManager._() {
    registerSink(const DiagnosticTelemetrySink());
  }
  static final TelemetryManager instance = TelemetryManager._();

  final List<TelemetrySink> _sinks = <TelemetrySink>[];

  /// Register an external telemetry provider (e.g. Firebase Crashlytics, Sentry).
  void registerSink(TelemetrySink sink) {
    if (!_sinks.contains(sink)) {
      _sinks.add(sink);
    }
  }

  /// Remove a telemetry provider.
  void unregisterSink(TelemetrySink sink) {
    _sinks.remove(sink);
  }

  /// Track a user workflow milestone or analytics event.
  void track(String eventName, [Map<String, dynamic>? parameters]) {
    for (final sink in _sinks) {
      try {
        sink.recordEvent(eventName, parameters: parameters);
      } catch (_) {}
    }
  }

  /// Capture a non-fatal or fatal error with stack trace.
  void captureException(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) {
    for (final sink in _sinks) {
      try {
        sink.recordError(error, stack, reason: reason, fatal: fatal);
      } catch (_) {}
    }
  }

  /// Add global session context (e.g. active document page count, engine version).
  void setContext(String key, Object value) {
    for (final sink in _sinks) {
      try {
        sink.setCustomKey(key, value);
      } catch (_) {}
    }
  }
}

