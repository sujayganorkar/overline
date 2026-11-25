import 'dart:ui' as ui;
import 'dart:typed_data';

import 'support/text_pdf.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:overline/main.dart';
import 'package:overline/services/pdf_engine.dart';
import 'package:overline/widgets/document_review_screen.dart';
import 'package:overline/widgets/task_catalog.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pdf;

Future<void> waitFor(WidgetTester tester, Finder finder) async {
  final clock = Stopwatch()..start();
  while (finder.evaluate().isEmpty &&
      clock.elapsed < const Duration(seconds: 90)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsWidgets);
}

Future<void> main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final engine = createPdfCraftEngine();

  Future<void> openTask(
    WidgetTester tester,
    Uint8List bytes,
    String title,
  ) async {
    await tester.pumpWidget(
      OverlineApp(
        engineFactory: () => engine,
        initialDocumentName: 'Review.pdf',
        initialDocumentBytes: bytes,
      ),
    );
    await waitFor(tester, find.byType(InteractiveViewer));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tools'));
    await waitFor(tester, find.byType(TaskCatalog));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), title);
    await waitFor(tester, find.widgetWithText(ListTile, title));
    await tester.tap(find.widgetWithText(ListTile, title));
    await waitFor(tester, find.byType(DocumentReviewScreen));
  }

  Future<void> closeEditedFixture(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close document'));
    await waitFor(tester, find.text('Discard'));
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close document'), findsNothing);
  }

  testWidgets('preview and apply screen reader tags from Tools', (
    tester,
  ) async {
    final bytes = textPdf([
      [
        'Quarterly report',
        'Ordinary body text is longer than the heading so it defines the body font used in this report.',
      ],
    ], firstLineIsHeading: true);
    await openTask(tester, bytes, 'Tag for screen readers');
    await waitFor(tester, find.text('Tag entire document'));
    await tester.tap(find.text('Tag entire document'));
    await waitFor(tester, find.text('Done'));
    expect(find.textContaining('document is tagged'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await waitFor(tester, find.textContaining('Unsaved changes'));
    await closeEditedFixture(tester);
  });

  testWidgets('an unsupported PDF stays open and clean after tagging fails', (
    tester,
  ) async {
    final document = pdf.Document();
    document.addPage(pdf.Page(build: (_) => pdf.Text('Quarterly report')));
    await openTask(tester, await document.save(), 'Tag for screen readers');
    await waitFor(tester, find.text('Tag entire document'));
    await tester.tap(find.text('Tag entire document'));
    await waitFor(
      tester,
      find.textContaining('unsupported or painted operator'),
    );
    await tester.pageBack();
    await waitFor(tester, find.text('Tools'));
    expect(find.textContaining('Unsaved changes'), findsNothing);
  });

  testWidgets('tapping a redaction finding opens its page', (tester) async {
    final native = await engine;
    final doc = await native.open(
      name: 'audit.pdf',
      bytes: textPdf([
        ['Cover page'],
        ['Confidential reference'],
      ]),
    );
    late Uint8List input;
    try {
      await native.executeTool(
        handle: doc,
        tool: 'redact_mark',
        argumentsJson: '{"find":"Confidential","page":2}',
      );
      final snapshot = await native.saveSnapshot(handle: doc);
      input = snapshot.bytes;
      await native.cancelSave(handle: doc, token: snapshot.token);
    } finally {
      await native.close(handle: doc, discardChanges: true);
    }
    await openTask(tester, input, 'Audit redactions');
    final finding = find.byIcon(Icons.visibility_off_outlined);
    await waitFor(tester, finding);
    await tester.tap(finding.first);
    await waitFor(tester, find.text('Page 2 of 2'));
  });

  testWidgets(
    'correct a word in an image-only scan using bundled offline models',
    (tester) async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder)
        ..drawColor(Colors.white, ui.BlendMode.src);
      final paragraph =
          (ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 50))
                ..pushStyle(ui.TextStyle(color: Colors.black, fontSize: 50))
                ..addText('Receipt total twenty dollars'))
              .build()
            ..layout(const ui.ParagraphConstraints(width: 980));
      canvas.drawParagraph(paragraph, const Offset(28, 75));
      final picture = recorder.endRecording();
      final image = await picture.toImage(1000, 240);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      picture.dispose();
      image.dispose();
      paragraph.dispose();
      final document = pdf.Document();
      final scan = pdf.MemoryImage(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      document.addPage(
        pdf.Page(
          pageFormat: const PdfPageFormat(500, 120),
          margin: pdf.EdgeInsets.zero,
          build: (_) => pdf.Image(scan, width: 500, height: 120),
        ),
      );
      await openTask(tester, await document.save(), 'Review recognized words');
      await waitFor(tester, find.text('Enlarge scan'));
      await tester.tap(find.text('Enlarge scan'));
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byType(Image));
      await tester.tapAt(
        rect.topLeft + Offset(rect.width * .11, rect.height * .44),
      );
      await waitFor(tester, find.byType(TextFormField));
      await tester.enterText(find.byType(TextFormField), 'Invoice');
      await tester.pump();
      final remember = find.text('Remember word on this device');
      if (remember.evaluate().isNotEmpty) {
        await tester.ensureVisible(remember);
        await tester.tap(remember);
      }
      await tester.tap(find.text('Keep correction'));
      await waitFor(tester, find.text('Corrected'));
      await tester.tap(find.text('Apply reviewed words'));
      await waitFor(tester, find.text('Done'));
      expect(find.text('Searchable text applied to page 1.'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await waitFor(tester, find.textContaining('Unsaved changes'));
      final saved = await (await engine).executeTool(
        handle: 0,
        tool: 'ocr_dictionary',
        argumentsJson: '{"path":"outputs/ocr-dictionary-en.txt"}',
      );
      expect(saved.contents.first.json, contains('"invoice"'));
      await closeEditedFixture(tester);
    },
  );
}
