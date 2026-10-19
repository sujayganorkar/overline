import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overline/services/app_diagnostics.dart';
import 'package:overline/services/feature_flags.dart';
import 'package:overline/services/page_cache.dart';
import 'package:overline/services/review_prompt.dart';
import 'package:overline/services/telemetry_sink.dart';
import 'package:overline/widgets/diagnostics_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockTelemetrySink implements TelemetrySink {
  final List<String> events = [];
  final List<Object> errors = [];
  final Map<String, Object> customKeys = {};

  @override
  void recordEvent(String name, {Map<String, dynamic>? parameters}) {
    events.add(name);
  }

  @override
  void recordError(Object error, StackTrace? stack, {String? reason, bool fatal = false}) {
    errors.add(error);
  }

  @override
  void setCustomKey(String key, Object value) {
    customKeys[key] = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AppDiagnostics', () {
    test('records breadcrumbs and respects ring-buffer capacity', () {
      final diagnostics = AppDiagnostics.instance;
      for (var i = 0; i < 200; i++) {
        diagnostics.record(category: 'test', message: 'Event $i');
      }
      expect(diagnostics.breadcrumbs.length, lessThanOrEqualTo(150));
      expect(diagnostics.breadcrumbs.last.message, 'Event 199');
    });

    test('notifies memory pressure listeners', () {
      final diagnostics = AppDiagnostics.instance;
      var notified = false;
      void listener() => notified = true;

      diagnostics.addMemoryPressureListener(listener);
      diagnostics.notifyMemoryPressure();
      expect(notified, isTrue);

      diagnostics.removeMemoryPressureListener(listener);
      notified = false;
      diagnostics.notifyMemoryPressure();
      expect(notified, isFalse);
    });

    test('formats error details with stack trace', () {
      final diagnostics = AppDiagnostics.instance;
      try {
        throw StateError('Test error for diagnostics');
      } catch (e, st) {
        diagnostics.recordError(e, st, category: 'test');
      }
      expect(diagnostics.breadcrumbs.last.level, BreadcrumbLevel.error);
      expect(
        diagnostics.breadcrumbs.last.message,
        contains('Test error for diagnostics'),
      );
    });
  });

  group('BoundedPageCache', () {
    test('evicts least recently used pages when capacity is exceeded', () async {
      final cache = BoundedPageCache(maxCapacity: 3);
      final dummyBytes = Uint8List.fromList([1, 2, 3]);

      await cache.putIfAbsent(1, () async => dummyBytes);
      await cache.putIfAbsent(2, () async => dummyBytes);
      await cache.putIfAbsent(3, () async => dummyBytes);
      expect(cache.length, 3);
      expect(cache.contains(1), isTrue);

      // Accessing page 1 moves it to most recently used
      await cache.putIfAbsent(1, () async => dummyBytes);

      // Adding page 4 should evict page 2 (since 1 was accessed again)
      await cache.putIfAbsent(4, () async => dummyBytes);
      expect(cache.length, 3);
      expect(cache.contains(2), isFalse);
      expect(cache.contains(1), isTrue);
      expect(cache.contains(3), isTrue);
      expect(cache.contains(4), isTrue);

      cache.dispose();
    });

    test('clears cache on memory pressure', () async {
      final cache = BoundedPageCache(maxCapacity: 5);
      final dummyBytes = Uint8List.fromList([1, 2, 3]);
      await cache.putIfAbsent(1, () async => dummyBytes);
      await cache.putIfAbsent(2, () async => dummyBytes);
      expect(cache.length, 2);

      AppDiagnostics.instance.notifyMemoryPressure();
      expect(cache.length, 0);

      cache.dispose();
    });

    test('evicts oldest pages when byte limit is exceeded', () async {
      final cache = BoundedPageCache(maxCapacity: 10, maxBytes: 100);
      final bigBytes = Uint8List(60);

      await cache.putIfAbsent(1, () async => bigBytes);
      await cache.putIfAbsent(2, () async => bigBytes);
      expect(cache.contains(1), isFalse);
      expect(cache.contains(2), isTrue);

      cache.dispose();
    });
  });

  group('FeatureFlagService', () {
    test('defaults to enabled and allows dynamic kill switches', () {
      final flags = FeatureFlagService.instance;
      flags.reset();
      expect(flags.isToolEnabled('doc_ocr'), isTrue);

      flags.emergencyKillTool('doc_ocr', reason: 'High memory crash on GPU');
      expect(flags.isToolEnabled('doc_ocr'), isFalse);
      expect(flags.getToolDisabledReason('doc_ocr'), 'High memory crash on GPU');

      flags.reset();
      expect(flags.isToolEnabled('doc_ocr'), isTrue);
    });

    test('applies remote config mapping', () async {
      final flags = FeatureFlagService.instance;
      flags.reset();

      await flags.applyConfig({
        'tool:doc_convert': false,
        'feature:experimental_ui': true,
      }, persist: false);

      expect(flags.isToolEnabled('doc_convert'), isFalse);
      expect(flags.isFeatureEnabled('feature:experimental_ui'), isTrue);
      flags.reset();
    });
  });

  group('TelemetryManager', () {
    test('broadcasts events and errors to registered sinks', () {
      final mock = MockTelemetrySink();
      final manager = TelemetryManager.instance;
      manager.registerSink(mock);

      manager.track('document_opened', {'pages': 10});
      expect(mock.events, contains('document_opened'));

      manager.captureException(Exception('Failed render'), null);
      expect(mock.errors.length, 1);

      manager.setContext('user_tier', 'free');
      expect(mock.customKeys['user_tier'], 'free');

      manager.unregisterSink(mock);
    });
  });

  group('ReviewPromptManager', () {
    test('respects milestone count and error suppresses prompt', () async {
      final manager = ReviewPromptManager.instance;
      manager.reset();

      // Milestones 1 and 2 should not prompt
      expect(await manager.recordMilestone('save_1'), isFalse);
      expect(await manager.recordMilestone('save_2'), isFalse);

      // Milestone 3 prompts
      expect(await manager.recordMilestone('save_3'), isTrue);

      // If an error occurred in session, prompting is blocked
      manager.markSessionError();
      expect(await manager.recordMilestone('save_4'), isFalse);

      manager.reset();
    });
  });

  group('DiagnosticsSheet', () {
    testWidgets('renders breadcrumbs and copy button', (tester) async {
      AppDiagnostics.instance.record(
        category: 'test_ui',
        message: 'Diagnostics rendered successfully',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DiagnosticsSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Diagnostics & Activity Log'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Diagnostics rendered successfully'), findsOneWidget);
    });
  });
}
