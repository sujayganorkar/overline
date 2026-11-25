import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overline/bridge/api.dart' show OperationInfo;
import 'package:overline/widgets/task_catalog.dart';

void main() {
  testWidgets('engine tools can be located by category and multiple keywords', (
    tester,
  ) async {
    PdfTask? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskCatalog(
            loadOperations: () async => const [
              OperationInfo(
                id: 'text_word_count',
                title: 'Word count',
                description: '',
                inputSchemaJson: '{}',
                readOnly: true,
                destructive: false,
                commandId: '',
                requiresDocument: true,
              ),
            ],
            onSelected: (task) => selected = task,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('All categories'));
    await tester.pumpAndSettle();
    final read = find.widgetWithText(ListTile, 'Read');
    await tester.scrollUntilVisible(
      read,
      120,
      scrollable: find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(read);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'words selection');
    await tester.pump();
    expect(find.text('1 tool'), findsOneWidget);
    await tester.tap(find.text('Count words'));
    expect(selected?.operation?.id, 'text_word_count');
  });

  testWidgets('search finds a specific tool and returns its task identity', (
    tester,
  ) async {
    PdfTask? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskCatalog(onSelected: (task) => selected = task),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'watermark');
    await tester.pump();
    expect(find.text('Sign & date'), findsNothing);
    await tester.tap(find.text('Watermark'));
    expect(selected?.id, 'watermark');
    await tester.enterText(find.byType(TextField), 'not a real tool');
    await tester.pump();
    expect(find.textContaining('No matching tools'), findsOneWidget);
  });

  testWidgets('tools remain usable at phone width and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(body: TaskCatalog(onSelected: (_) {})),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
