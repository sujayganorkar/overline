import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overline/bridge/api.dart' as bridge;
import 'package:overline/services/text_edit_session.dart';
import 'package:overline/widgets/text_edit_sheet.dart';

import 'viewer_initialization_test.dart' show FakePdfEngine;

final textPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAD0lEQVR4nGP4jwQYiOMAANuQL9FuRbCyAAAAAElFTkSuQmCC',
);

class TextEngine extends FakePdfEngine {
  String source = 'Original paragraph';
  final copies = <int, String>{};
  final closed = <int>[];
  final writes = <(int, String)>[];
  int nextHandle = 2, cancelled = 0;
  bool failPreview = false, failCommit = false;
  Completer<void>? previewGate, commitGate;
  @override
  Future<int> open({
    required String name,
    required Uint8List bytes,
    String? password,
  }) async {
    final handle = nextHandle++;
    copies[handle] = utf8.decode(bytes);
    return handle;
  }

  @override
  Future<bridge.SaveSnapshot> saveSnapshot({required int handle}) async =>
      bridge.SaveSnapshot(
        token: 1,
        bytes: Uint8List.fromList(utf8.encode(source)),
      );
  @override
  Future<void> cancelSave({required int handle, required int token}) async {
    cancelled++;
  }

  @override
  Future<void> close({required int handle, bool discardChanges = false}) async {
    copies.remove(handle);
    closed.add(handle);
  }

  @override
  Future<Uint8List> renderPagePng({
    required int handle,
    required int page1Based,
    required int dpi,
  }) async => textPng;
  @override
  Future<bridge.OperationResponse> executeTool({
    required int handle,
    required String tool,
    required String argumentsJson,
  }) async {
    final args = jsonDecode(argumentsJson);
    if (tool == 'text_edit' || tool == 'page_add_text') {
      final gate = handle == 1 ? commitGate : previewGate;
      if (gate != null) await gate.future;
      if (handle == 1 && failCommit || handle != 1 && failPreview) {
        throw StateError('Cannot encode this text');
      }
      final text = args['text'] as String;
      writes.add((handle, text));
      if (handle == 1) {
        source = text;
      } else {
        copies[handle] = text;
      }
    }
    if (tool == 'edit_undo') source = 'Original paragraph';
    final text = handle == 1 ? source : copies[handle]!;
    return bridge.OperationResponse(
      status: bridge.DocumentStatus(
        pageCount: 1,
        dirty: handle == 1 && source != 'Original paragraph',
        editable: true,
        canUndo: source != 'Original paragraph' ? 'Edit text' : '',
        canRedo: '',
      ),
      contents: [
        bridge.OperationContent(
          json: jsonEncode(
            tool == 'text_paragraphs'
                ? {
                    'paragraphs': [
                      {
                        'paragraph': 1,
                        'text': text,
                        'font': 'Times-Roman',
                        'size': 12,
                        'rect': [72, 72, 300, 110],
                      },
                    ],
                  }
                : {
                    'paragraph': {'font': 'Times-Roman'},
                  },
          ),
          png: Uint8List(0),
          width: 0,
          height: 0,
        ),
      ],
    );
  }
}

Future<void> openText(
  WidgetTester tester,
  TextEngine engine, {
  ValueChanged<bridge.DocumentStatus>? notify,
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
            child: const Text('Open'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => TextEditSheet(
                  engine: engine,
                  handle: 1,
                  page: 1,
                  png: textPng,
                  imageWidthPx: 816,
                  imageHeightPx: 1056,
                  onStatusChanged: notify ?? (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Browse text blocks'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Original paragraph'));
  await tester.pumpAndSettle();
}

Future<void> review(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Review PDF'));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 60)),
  );
  await tester.pumpAndSettle();
}

void main() {
  test(
    'preview is isolated, closes copies, applies once and rejects reuse',
    () async {
      final engine = TextEngine();
      final session = TextEditSession(engine: engine, handle: 1, page: 1);
      await session.refresh();
      final candidate = await session.preview('text_edit', {
        'page': 1,
        'paragraph': 1,
        'text': 'New text',
      });
      expect(engine.source, 'Original paragraph');
      expect(engine.copies, isEmpty);
      await session.apply(candidate);
      expect(engine.source, 'New text');
      await expectLater(session.apply(candidate), throwsStateError);
      expect(engine.writes.where((w) => w.$1 == 1), hasLength(1));
      expect(engine.cancelled, 1);
    },
  );
  test(
    'failed preview closes copy; changed source rejects old candidate',
    () async {
      final engine = TextEngine()..failPreview = true;
      final session = TextEditSession(engine: engine, handle: 1, page: 1);
      await session.refresh();
      await expectLater(
        session.preview('text_edit', {'text': 'Draft'}),
        throwsStateError,
      );
      expect(engine.copies, isEmpty);
      engine.failPreview = false;
      final candidate = await session.preview('text_edit', {'text': 'Draft'});
      engine.source = 'Externally changed';
      await expectLater(session.apply(candidate), throwsStateError);
      expect(engine.source, 'Externally changed');
    },
  );
  testWidgets('unchanged selection is inline, clean and does not offer Apply', (
    tester,
  ) async {
    final engine = TextEngine();
    await openText(tester, engine);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('Close text editor'));
    await tester.pumpAndSettle();
    expect(find.byType(TextEditSheet), findsNothing);
    expect(engine.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('failed preview retains draft and requires review before Apply', (
    tester,
  ) async {
    final engine = TextEngine()..failPreview = true;
    await openText(tester, engine);
    await tester.enterText(find.byType(TextField), 'Keep my draft');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.textContaining('Your draft is still here'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Keep my draft',
    );
    engine.failPreview = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Review PDF'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply'))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(engine.source, 'Keep my draft');
    expect(find.byType(TextEditSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('changed draft prompts before exit and keeps text', (
    tester,
  ) async {
    final engine = TextEngine();
    await openText(tester, engine);
    await tester.enterText(find.byType(TextField), 'Unsaved draft');
    await tester.pump();
    await tester.tap(find.byTooltip('Close text editor'));
    await tester.pumpAndSettle();
    expect(find.text('Discard this text edit?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Unsaved draft',
    );
    expect(engine.source, 'Original paragraph');
  });
  testWidgets('pending commit blocks dismissal and notifies once', (
    tester,
  ) async {
    final engine = TextEngine()..commitGate = Completer<void>();
    var notices = 0;
    await openText(tester, engine, notify: (_) => notices++);
    await review(tester, 'Committed text');
    await tester.tap(find.text('Apply'));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(TextEditSheet), findsOneWidget);
    engine.commitGate!.complete();
    await tester.pumpAndSettle();
    expect(notices, 1);
    expect(engine.writes.where((w) => w.$1 == 1), hasLength(1));
    expect(tester.takeException(), isNull);
  });
  testWidgets('late preview cannot apply an older draft', (tester) async {
    final engine = TextEngine()..previewGate = Completer<void>();
    await openText(tester, engine);
    await tester.enterText(find.byType(TextField), 'Old draft');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), 'Latest draft');
    await tester.pump();
    engine.previewGate!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review PDF'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(engine.source, 'Latest draft');
  });
  testWidgets('failed commit keeps the reviewed draft available for retry', (
    tester,
  ) async {
    final engine = TextEngine()..failCommit = true;
    await openText(tester, engine);
    await review(tester, 'Retry this edit');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Your draft is still here'), findsOneWidget);
    expect(engine.source, 'Original paragraph');
    engine.failCommit = false;
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(engine.source, 'Retry this edit');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'editor fits a narrow keyboard-open viewport and keeps the field visible',
    (tester) async {
      final engine = TextEngine();
      await openText(tester, engine);
      tester.view.physicalSize = const Size(320, 640);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'A draft on a phone');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byType(TextField)).dy,
        greaterThanOrEqualTo(0),
      );
      expect(tester.getTopLeft(find.byType(TextField)).dy, lessThan(360));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'pending preview closes its copy after draft is discarded and route exits',
    (tester) async {
      final engine = TextEngine()..previewGate = Completer<void>();
      await openText(tester, engine);
      await tester.enterText(find.byType(TextField), 'Abandoned preview');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byTooltip('Close text editor'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Discard draft'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      engine.previewGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(TextEditSheet), findsNothing);
      expect(engine.copies, isEmpty);
      expect(engine.source, 'Original paragraph');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'cancel a clean selection then place, review and apply new page text',
    (tester) async {
      final engine = TextEngine();
      await openText(tester, engine);
      await tester.tap(find.text('Cancel edit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add text'));
      await tester.pumpAndSettle();
      final center = tester.getCenter(find.byType(InteractiveViewer));
      final first = await tester.startGesture(
        center - const Offset(25, 0),
        pointer: 1,
      );
      final second = await tester.startGesture(
        center + const Offset(25, 0),
        pointer: 2,
      );
      await second.up();
      await first.up();
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      await tester.tapAt(center);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      await review(tester, 'Added text');
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(engine.source, 'Added text');
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Undo text edit'));
      await tester.pumpAndSettle();
      expect(engine.source, 'Original paragraph');
    },
  );
}
