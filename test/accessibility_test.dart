import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfcraft_mobile/widgets/find_bar.dart';
import 'package:pdfcraft_mobile/widgets/zoom_controls.dart';

void main() {
  group('ZoomControlsHud Accessibility & Touch Target Tests', () {
    testWidgets(
      'renders zoom controls with minimum 44dp touch targets and tooltips',
      (tester) async {
        final controller = TransformationController();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ZoomControlsHud(transformController: controller),
            ),
          ),
        );

        // Verify initial state display
        expect(find.text('100%'), findsOneWidget);

        // Find buttons by tooltip
        final zoomInFinder = find.byTooltip('Zoom in');
        final zoomOutFinder = find.byTooltip('Zoom out');

        expect(zoomInFinder, findsOneWidget);
        expect(zoomOutFinder, findsOneWidget);
        // Reset control only appears once zoomed in.
        expect(find.byTooltip('Reset zoom to fit page'), findsNothing);

        // Tap Zoom In: the controller matrix must scale up.
        await tester.tap(zoomInFinder);
        await tester.pump();
        expect(controller.value.getMaxScaleOnAxis(), greaterThan(1.0));

        // Reset control appears once zoomed in.
        final resetFinder = find.byTooltip('Reset zoom to fit page');
        expect(resetFinder, findsOneWidget);

        // Tap Reset: back to identity.
        await tester.tap(resetFinder);
        await tester.pump();
        expect(controller.value.getMaxScaleOnAxis(), closeTo(1.0, 0.001));

        // Verify touch target sizes >= 44dp on each interactive element.
        final zoomInSize = tester.getSize(zoomInFinder);
        final zoomOutSize = tester.getSize(zoomOutFinder);

        expect(zoomInSize.width, greaterThanOrEqualTo(44.0));
        expect(zoomInSize.height, greaterThanOrEqualTo(44.0));
        expect(zoomOutSize.width, greaterThanOrEqualTo(44.0));
        expect(zoomOutSize.height, greaterThanOrEqualTo(44.0));
      },
    );
  });

  group('FindBar Accessibility & Live Region Tests', () {
    testWidgets('find bar has accessible label, tooltips, and match count', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'contract');
      var prevTapped = false;
      var nextTapped = false;
      var closed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FindBar(
              controller: controller,
              matchIndex: 1,
              matchCount: 4,
              onPrevious: () => prevTapped = true,
              onNext: () => nextTapped = true,
              onClose: () => closed = true,
            ),
          ),
        ),
      );

      // Verify label text
      expect(find.text('Find in PDF'), findsOneWidget);
      expect(find.text('2 of 4'), findsOneWidget);

      // Verify navigation buttons
      final prevFinder = find.byTooltip('Previous match');
      final nextFinder = find.byTooltip('Next match');
      final closeFinder = find.byTooltip('Close search');

      expect(prevFinder, findsOneWidget);
      expect(nextFinder, findsOneWidget);
      expect(closeFinder, findsOneWidget);

      await tester.tap(prevFinder);
      expect(prevTapped, isTrue);

      await tester.tap(nextFinder);
      expect(nextTapped, isTrue);

      await tester.tap(closeFinder);
      expect(closed, isTrue);
    });
  });
}
