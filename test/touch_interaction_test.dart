import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overline/widgets/annotate_page.dart';
import 'package:overline/widgets/touch_session.dart';

import 'viewer_initialization_test.dart' show FakePdfEngine;

void main() {
  test(
    'pinch stays interrupted after fingers lift and resets on next contact',
    () {
      final touch = TouchSession();
      touch.down(1);
      expect(touch.canEdit, isTrue);
      touch.down(2);
      touch.up(2);
      expect(touch.canEdit, isFalse);
      touch.up(1);
      expect(touch.canEdit, isFalse);
      touch.down(3);
      expect(touch.canEdit, isTrue);
      touch.cancel(3);
      expect(touch.canEdit, isFalse);
    },
  );

  Future<void> openNotes(
    WidgetTester tester, {
    AnnotateMode mode = AnnotateMode.note,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAD0lEQVR4nGP4jwQYiOMAANuQL9FuRbCyAAAAAElFTkSuQmCC',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AnnotatePage(
          engine: FakePdfEngine(),
          handle: 1,
          page: 1,
          png: png,
          dpi: 96,
          imageWidthPx: 400,
          imageHeightPx: 500,
          initialMode: mode,
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'note waits for a completed tap, and a drag does not open a note',
    (tester) async {
      await openNotes(tester);
      final page = find.byType(InteractiveViewer);
      final center = tester.getCenter(page);
      final gesture = await tester.startGesture(center);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Add a note'), findsNothing);
      await gesture.moveBy(const Offset(70, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('Add a note'), findsNothing);
      await tester.tapAt(center);
      await tester.pumpAndSettle();
      expect(find.text('Add a note'), findsOneWidget);
    },
  );

  testWidgets('note mode offers navigation, and pinch never opens a note', (
    tester,
  ) async {
    await openNotes(tester);
    final center = tester.getCenter(find.byType(InteractiveViewer));
    final first = await tester.startGesture(
      center - const Offset(30, 0),
      pointer: 1,
    );
    final second = await tester.startGesture(
      center + const Offset(30, 0),
      pointer: 2,
    );
    await first.moveBy(const Offset(-40, 0));
    await second.moveBy(const Offset(40, 0));
    await second.up();
    await first.up();
    await tester.pumpAndSettle();
    expect(find.text('Add a note'), findsNothing);
    await tester.tap(find.text('Move & zoom'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .scaleEnabled,
      isTrue,
    );
    await tester.tapAt(center);
    await tester.pumpAndSettle();
    expect(find.text('Add a note'), findsNothing);
  });
  testWidgets('selection tools fit a phone without overflow', (tester) async {
    await openNotes(tester, mode: AnnotateMode.select);
    expect(tester.takeException(), isNull);
  });
}
