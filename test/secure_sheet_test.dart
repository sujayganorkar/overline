import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overline/bridge/api.dart' as bridge;
import 'package:overline/widgets/secure_sheet.dart';

import 'viewer_initialization_test.dart' show FakePdfEngine;

class _RedactionEngine extends FakePdfEngine {
  _RedactionEngine(this.result);

  final Map<String, Object?> result;
  int applications = 0;

  @override
  Future<bridge.OperationResponse> executeTool({
    required int handle,
    required String tool,
    required String argumentsJson,
  }) async {
    expect(tool, 'redact_apply');
    expect(handle, 1);
    applications++;
    return bridge.OperationResponse(
      contents: [
        bridge.OperationContent(
          json: jsonEncode(result),
          png: Uint8List(0),
          width: 0,
          height: 0,
        ),
      ],
      status: await status(handle: handle),
    );
  }
}

void main() {
  for (final scenario in [
    (
      name: 'a bookmark still holds the redacted text',
      result: {
        'still_holding': {'bookmarks': 1, 'total': 1, 'unsearched': false},
        'warnings': ['The redacted text also appears in 1 bookmark title.'],
      },
      expectedMessages: ['1 other place', '1 bookmark title'],
    ),
    (
      name: 'some document content could not be searched',
      result: {
        'still_holding': {'total': 0, 'unsearched': true},
        'warnings': <String>[],
      },
      expectedMessages: ['Some document content could not be checked.'],
    ),
  ]) {
    testWidgets('privacy tools stay open when ${scenario.name}', (
      tester,
    ) async {
      final engine = _RedactionEngine(scenario.result);
      await tester.pumpWidget(
        MaterialApp(
          initialRoute: '/privacy',
          routes: {
            '/': (_) => const Scaffold(body: Text('Reader')),
            '/privacy': (_) => Scaffold(
              body: SecureSheet(
                engine: engine,
                handle: 1,
                onStatusChanged: (_) {},
              ),
            ),
          },
        ),
      );
      await tester.pumpAndSettle();
      final apply = find.text('Apply redactions');
      await tester.scrollUntilVisible(apply, 150);
      await tester.tap(apply);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
        // The sheet's progress indicator keeps animating until the warning is acknowledged.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Review the redaction results'), findsOneWidget);
      for (final message in scenario.expectedMessages) {
        expect(find.textContaining(message), findsOneWidget);
      }
      await tester.tap(find.text('Back to privacy tools'));
      await tester.pumpAndSettle();

      expect(engine.applications, 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(apply, findsOneWidget);
      expect(find.text('Reader'), findsNothing);
    });
  }
}
