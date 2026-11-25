import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:overline/main.dart';
import 'package:overline/services/pdf_engine.dart';
import 'package:overline/widgets/document_review_screen.dart';
import 'package:overline/widgets/engine_task_labels.dart';
import 'package:overline/widgets/operation_browser.dart';

import 'support/text_pdf.dart';

Future<void> waitFor(WidgetTester tester, Finder finder) async {
  final timer = Stopwatch()..start();
  while (finder.evaluate().isEmpty &&
      timer.elapsed < const Duration(seconds: 15)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsWidgets);
}

final _engine = createPdfCraftEngine();

Future<void> openSample(WidgetTester tester) async {
  await tester.pumpWidget(
    OverlineApp(
      engineFactory: () => _engine,
      initialDocumentName: 'Orchard.pdf',
      initialDocumentBytes: textPdf([
        ['Apricot orchard'],
        ['Apricot harvest'],
      ]),
    ),
  );
  await waitFor(tester, find.byType(InteractiveViewer));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Reading view'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Single page'));
  await tester.pumpAndSettle();
}

Future<void> openTool(WidgetTester tester, String name) async {
  await tester.tap(find.text('Tools'));
  await waitFor(tester, find.byType(TextField));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), name);
  final item = find.widgetWithText(ListTile, name);
  await waitFor(tester, item);
  await tester.tap(item);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('pinch, swipe, pan and draw stay on the intended page', (
    tester,
  ) async {
    await openSample(tester);
    final canvas = find.byType(InteractiveViewer);
    const left = Offset(-120, 0);
    await tester.drag(canvas, const Offset(0, -90));
    await tester.pumpAndSettle();
    expect(find.text('Page 1 of 2'), findsOneWidget);

    await tester.tap(find.text('Zoom'));
    await tester.pumpAndSettle();
    final center = tester.getCenter(canvas);
    final first = await tester.startGesture(center - const Offset(35, 0));
    final second = await tester.startGesture(center + const Offset(35, 0));
    for (final distance in [50.0, 70.0, 85.0]) {
      await first.moveTo(center - Offset(distance, 0));
      await second.moveTo(center + Offset(distance, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    final transform = tester
        .widget<InteractiveViewer>(canvas)
        .transformationController!;
    expect(transform.value.getMaxScaleOnAxis(), greaterThan(1.2));
    expect(find.text('Page 1 of 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Reset zoom to fit page'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pumpAndSettle();
    await tester.drag(canvas, left);
    await tester.pumpAndSettle();
    expect(find.text('Page 1 of 2'), findsOneWidget);
    expect(find.text('130%'), findsOneWidget);
    await tester.tap(find.byTooltip('Reset zoom to fit page'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close zoom'));
    await tester.pumpAndSettle();
    await tester.drag(canvas, left);
    await waitFor(tester, find.text('Page 2 of 2'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Markup'));
    await tester.pumpAndSettle();
    await tester.drag(canvas, -left);
    await tester.pumpAndSettle();
    expect(find.text('Markup · Page 2'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply'))
          .enabled,
      isTrue,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Page 2 of 2'), findsOneWidget);
  });

  testWidgets(
    'catalog search opens PDF search and follows matches across pages',
    (tester) async {
      await openSample(tester);
      await tester.tap(find.byTooltip('Reading view'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vertical scroll'));
      await tester.pumpAndSettle();
      await openTool(tester, 'Find in PDF');
      await waitFor(tester, find.byTooltip('Search'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Apricot');
      await tester.tap(find.byTooltip('Search'));
      await waitFor(tester, find.text('1 of 2'));
      await tester.tap(find.byTooltip('Next match'));
      await waitFor(tester, find.text('Page 2 of 2'));
      expect(find.text('2 of 2'), findsOneWidget);
      await tester.tap(find.byTooltip('Close search'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Next match'), findsNothing);
      expect(find.text('Page 2 of 2'), findsOneWidget);
    },
  );

  testWidgets('every labeled engine workflow is discoverable by touch search', (
    tester,
  ) async {
    await openSample(tester);
    await tester.tap(find.text('Tools'));
    await waitFor(tester, find.byType(TextField));
    for (final label in engineTaskLabels.values) {
      await tester.enterText(find.byType(TextField), label.title);
      await tester.pump();
      expect(
        find.widgetWithText(ListTile, label.title),
        findsOneWidget,
        reason: 'Missing Android tool: ${label.title}',
      );
    }
    await tester.tap(find.byTooltip('Close tools'));
    await tester.pumpAndSettle();
    for (final entry in engineTaskLabels.entries) {
      final id = entry.key;
      if (isDocumentReviewTool(id) || id == 'printer_papers') continue;
      await openTool(tester, entry.value.title);
      await waitFor(
        tester,
        find.byWidgetPredicate(
          (widget) => widget is OperationScreen && widget.operation.id == id,
        ),
      );
      expect(
        find.byKey(const ValueKey('execute-operation')).hitTestable(),
        findsOneWidget,
        reason: 'The action for ${entry.value.title} must be reachable',
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Page 1 of 2'), findsOneWidget);
    }
  });

  testWidgets('word count runs on both pages with the default settings', (
    tester,
  ) async {
    await openSample(tester);
    await openTool(tester, 'Count words');
    await tester.tap(find.byKey(const ValueKey('execute-operation')));
    await waitFor(tester, find.text('Done'));
    final totals = find.textContaining(RegExp(r'^Total \('));
    await tester.ensureVisible(totals);
    await tester.tap(totals);
    await tester.pumpAndSettle();
    expect(
      find.textContaining(RegExp(r'Words\s+4'), findRichText: true),
      findsWidgets,
    );
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Page 1 of 2'), findsOneWidget);
  });

  testWidgets(
    'find and replace reports both changes and Undo restores searchable text',
    (tester) async {
      await openSample(tester);
      await openTool(tester, 'Find and replace');
      for (final field in [('Find', 'Apricot'), ('Replace', 'Peach')]) {
        final input = find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == field.$1,
        );
        await tester.ensureVisible(input);
        await tester.enterText(input, field.$2);
      }
      await tester.tap(find.byKey(const ValueKey('execute-operation')));
      await tester.pumpAndSettle();
      if (find.text('Continue').evaluate().isNotEmpty) {
        await tester.tap(find.text('Continue'));
      }
      final undo = find.ancestor(
        of: find.textContaining(RegExp(r'^Undo ')),
        matching: find.byType(OutlinedButton),
      );
      await waitFor(tester, undo);
      expect(
        find.textContaining(RegExp(r'Replaced\s+2'), findRichText: true),
        findsWidgets,
      );
      await tester.tap(undo);
      await waitFor(tester, find.byKey(const ValueKey('execute-operation')));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await openTool(tester, 'Find in PDF');
      await tester.enterText(find.byType(TextField), 'Apricot');
      await tester.tap(find.byTooltip('Search'));
      await waitFor(tester, find.text('1 of 2'));
      await tester.tap(find.byTooltip('Close search'));
      await tester.pumpAndSettle();
    },
  );
}
