import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overline/widgets/reader_controls.dart';

void main() {
  testWidgets('page slider and zoom are on demand and slider commits once', (
    tester,
  ) async {
    final transform = TransformationController();
    addTearDown(transform.dispose);
    final pages = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: ReaderControls(
            page: 1,
            pageCount: 10,
            transform: transform,
            onNavigate: pages.add,
          ),
        ),
      ),
    );
    expect(find.byType(Slider), findsNothing);
    expect(find.byTooltip('Zoom in'), findsNothing);
    await tester.tap(find.text('Zoom'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Zoom in'), findsOneWidget);
    await tester.tap(find.text('Page 1 of 10'));
    await tester.pumpAndSettle();
    tester.widget<Slider>(find.byType(Slider)).onChanged!(6);
    await tester.pump();
    expect(pages, isEmpty);
    await tester.tap(find.text('Go to page 6'));
    await tester.pumpAndSettle();
    expect(pages, [6]);
    expect(find.byType(Slider), findsNothing);
  });
  testWidgets('selection controls wrap at narrow widths with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var applied = '';
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            bottomNavigationBar: TextSelectionActions(
              busy: false,
              color: 'yellow',
              onApply: (v) => applied = v,
              onCopy: () {},
              onClear: () {},
              onColor: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Underline'));
    expect(applied, 'underline');
    for (final label in [
      'Underline',
      'Strikethrough',
      'Copy text',
      'Clear selection',
    ]) {
      expect(
        tester.getSize(find.byTooltip(label)).height,
        greaterThanOrEqualTo(48),
      );
    }
  });
}
