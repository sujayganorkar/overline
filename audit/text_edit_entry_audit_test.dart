// Characterization of the current reading-mode entry failure, not acceptance.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overline/main.dart';
import 'package:overline/widgets/text_edit_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'text_edit_audit_test.dart' show AuditTextEngine;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  const channel = MethodChannel('com.pdfcraft.pdfcraft_mobile/paths');
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('text-audit-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async =>
              call.method == 'getSupportDir' ? directory.path : null,
        );
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  for (final mode in ['Vertical scroll', 'Horizontal scroll']) {
    testWidgets('audit: Edit text silently opens nothing in $mode', (
      tester,
    ) async {
      // Audit harness lives outside test/ to avoid running defect reproductions in CI.
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        MaterialApp(
          home: ViewerPage(
            engineFactory: () async => AuditTextEngine(),
            initialDocumentBytes: Uint8List(100),
            initialDocumentName: 'Audit.pdf',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Reading view'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(mode));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tools'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'paragraph');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit text'));
      await tester.pumpAndSettle();
      expect(find.byType(TextEditSheet), findsNothing);
      expect(find.text('Audit.pdf'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
