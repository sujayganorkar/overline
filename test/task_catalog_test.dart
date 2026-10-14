import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfcraft_mobile/widgets/task_catalog.dart';

void main() {
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
