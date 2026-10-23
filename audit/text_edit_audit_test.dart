// Characterization tests for the text-edit UX audit, not acceptance criteria.
// These reproduce current gaps; replace the assertions when each gap is fixed.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overline/bridge/api.dart' as bridge;
import 'package:overline/widgets/text_edit_sheet.dart';

import '../test/viewer_initialization_test.dart' show FakePdfEngine;

class AuditTextEngine extends FakePdfEngine {
  bool fail = false;
  Completer<void>? pending;
  int edits = 0, renders = 0;
  @override
  Future<Uint8List> renderPagePng({
    required int handle,
    required int page1Based,
    required int dpi,
  }) async {
    renders++;
    return pagePng;
  }

  @override
  Future<bridge.OperationResponse> executeTool({
    required int handle,
    required String tool,
    required String argumentsJson,
  }) async {
    if (tool == 'text_edit') {
      edits++;
      if (pending != null) await pending!.future;
      if (fail) throw StateError('Unsupported glyph');
    }
    return bridge.OperationResponse(
      status: await status(handle: handle),
      contents: [
        bridge.OperationContent(
          json: jsonEncode({
            'paragraphs': [
              {
                'paragraph': 1,
                'text': 'Original paragraph',
                'font': 'Times-Roman',
                'size': 12,
                'rect': [72, 72, 300, 100],
              },
            ],
          }),
          png: Uint8List(0),
          width: 0,
          height: 0,
        ),
      ],
    );
  }
}

final pagePng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAD0lEQVR4nGP4jwQYiOMAANuQL9FuRbCyAAAAAElFTkSuQmCC',
);
Future<void> openEditor(
  WidgetTester tester,
  AuditTextEngine engine, {
  ValueChanged<bridge.DocumentStatus>? onStatus,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            child: const Text('Open editor'),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => TextEditSheet(
                engine: engine,
                handle: 1,
                page: 1,
                png: pagePng,
                imageWidthPx: 816,
                imageHeightPx: 1056,
                onStatusChanged: onStatus ?? (_) {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open editor'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Browse text blocks'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Original paragraph'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Edit selected text'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'audit: typing uses a generic dialog and never renders a draft on the page',
    (tester) async {
      final engine = AuditTextEngine();
      await openEditor(tester, engine);
      await tester.enterText(
        find.byType(TextField),
        'A much longer replacement with different wrapping',
      );
      await tester.pumpAndSettle();
      expect(
        find.ancestor(
          of: find.byType(TextField),
          matching: find.byType(AlertDialog),
        ),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(find.byType(TextField)).style, isNull);
      expect(engine.edits, 0);
      expect(engine.renders, 0);
    },
  );
  testWidgets('audit: failed replacement drops the entered draft', (
    tester,
  ) async {
    final engine = AuditTextEngine()..fail = true;
    await openEditor(tester, engine);
    await tester.enterText(find.byType(TextField), 'My replacement draft');
    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();
    expect(find.text('Edit failed.'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Edit selected text'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Original paragraph',
    );
  });
  testWidgets('audit: cancelling a changed draft has no discard confirmation', (
    tester,
  ) async {
    final engine = AuditTextEngine();
    await openEditor(tester, engine);
    await tester.enterText(find.byType(TextField), 'Unsaved draft');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Unsaved draft'), findsNothing);
    expect(engine.edits, 0);
  });
  testWidgets(
    'audit: closing editor during mutation suppresses document status callback',
    (tester) async {
      final engine = AuditTextEngine()..pending = Completer<void>();
      var notifications = 0;
      await openEditor(tester, engine, onStatus: (_) => notifications++);
      await tester.enterText(find.byType(TextField), 'Edited while closing');
      await tester.tap(find.text('Replace'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.byTooltip('Close text editor'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(TextEditSheet), findsNothing);
      engine.pending!.complete();
      await tester.pumpAndSettle();
      expect(engine.edits, 1);
      expect(notifications, 0);
    },
  );
  testWidgets(
    'audit: unchanged text still invokes a mutation and exits editing',
    (tester) async {
      final engine = AuditTextEngine();
      await openEditor(tester, engine);
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();
      expect(engine.edits, 1);
      expect(find.byType(TextEditSheet), findsNothing);
    },
  );
}
