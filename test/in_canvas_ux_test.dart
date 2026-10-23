import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overline/bridge/api.dart' as bridge;
import 'package:overline/main.dart';
import 'package:overline/widgets/reader_controls.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'viewer_initialization_test.dart' show FakePdfEngine;

class TestDocEngine extends FakePdfEngine {
  TestDocEngine({this.pages = 3});
  final int pages;
  final renderedPages = <int>[];

  @override
  Future<int> pageCount({required int handle}) async => pages;

  @override
  Future<bridge.DocumentStatus> status({required int handle}) async =>
      bridge.DocumentStatus(
        pageCount: pages,
        dirty: false,
        editable: true,
        canUndo: '',
        canRedo: '',
      );

  @override
  Future<Uint8List> renderPagePng({
    required int handle,
    required int page1Based,
    required int dpi,
  }) async {
    renderedPages.add(page1Based);
    // 4x4 transparent PNG
    return base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAD0lEQVR4nGP4jwQYiOMAANuQL9FuRbCyAAAAAElFTkSuQmCC',
    );
  }
}

class SelectableEngine extends TestDocEngine {
  @override
  Future<bridge.OperationResponse> executeTool({
    required int handle,
    required String tool,
    required String argumentsJson,
  }) async {
    return bridge.OperationResponse(
      status: await status(handle: handle),
      contents: [
        bridge.OperationContent(
          json: jsonEncode(
            tool == 'text_lines'
                ? {
                    'lines': [
                      {
                        'text': 'Select this text',
                        'rect': [0, 0, 612, 792],
                      },
                    ],
                  }
                : {'comments': []},
          ),
          png: Uint8List(0),
          width: 0,
          height: 0,
        ),
      ],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.overline.pdf/paths');
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('incanvas_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getSupportDir') return tempDir.path;
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets(
    'in-canvas mode switches between Read, Markup, and Sign without route thrashing',
    (tester) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: ViewerPage(
            engineFactory: () async => TestDocEngine(pages: 3),
            initialDocumentBytes: Uint8List(100),
            initialDocumentName: 'TestDocument.pdf',
          ),
        ),
      );
      await tester.pumpAndSettle();
      debugPrint(
        'Found texts after pumpAndSettle: ${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).toList()}',
      );

      // 1. Initial State: Read Mode
      expect(find.text('TestDocument.pdf'), findsOneWidget);
      expect(find.text('Read'), findsOneWidget);
      expect(find.text('Markup'), findsOneWidget);
      expect(find.text('Sign'), findsOneWidget);
      expect(find.text('Pages'), findsOneWidget);
      expect(find.text('Tools'), findsOneWidget);
      expect(find.text('Finish'), findsOneWidget);

      // Floating stepper should show page 1 of 3
      expect(find.text('Page 1 of 3'), findsOneWidget);

      // 2. Switch to Markup Mode
      await tester.tap(find.text('Markup'));
      await tester.pumpAndSettle();

      // AppBar changes to Markup Mode
      expect(find.text('Markup · Page 1'), findsOneWidget);
      expect(find.byTooltip('Cancel markup'), findsOneWidget);
      expect(find.text('Apply'), findsOneWidget);

      // Bottom palette displays drawing tools
      expect(find.text('Pen'), findsOneWidget);
      expect(find.text('Highlighter'), findsOneWidget);
      expect(find.text('Eraser'), findsOneWidget);
      expect(find.byTooltip('Stroke thickness'), findsOneWidget);

      // Read navigation bar is docked/hidden in markup mode
      expect(find.text('Finish'), findsNothing);

      // Cancel markup returns to Read mode
      await tester.tap(find.byTooltip('Cancel markup'));
      await tester.pumpAndSettle();
      expect(find.text('Markup · Page 1'), findsNothing);
      expect(find.text('TestDocument.pdf'), findsOneWidget);
      expect(find.text('Read'), findsOneWidget);

      // 3. Switch to Sign Mode
      await tester.tap(find.text('Sign'));
      await tester.pumpAndSettle();

      // AppBar changes to Sign Mode
      expect(find.text('Place Signature · Page 1'), findsOneWidget);
      expect(find.byTooltip('Cancel placement'), findsOneWidget);
      expect(find.text('Place'), findsOneWidget);

      // Bottom palette displays signature sizing controls
      expect(find.byTooltip('Shrink signature'), findsOneWidget);
      expect(find.byTooltip('Enlarge signature'), findsOneWidget);

      // Cancel sign returns to Read mode
      await tester.tap(find.byTooltip('Cancel placement'));
      await tester.pumpAndSettle();
      expect(find.text('Place Signature · Page 1'), findsNothing);
      expect(find.text('TestDocument.pdf'), findsOneWidget);
    },
  );
  testWidgets(
    'long press replaces reader controls with a non-overlapping selection dock',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: ViewerPage(
            engineFactory: () async => SelectableEngine(),
            initialDocumentBytes: Uint8List(100),
            initialDocumentName: 'Selection.pdf',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zoom'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Zoom in'), findsOneWidget);
      await tester.longPressAt(
        tester.getCenter(find.byType(InteractiveViewer)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextSelectionActions), findsOneWidget);
      expect(find.byType(ReaderControls), findsNothing);
      expect(find.byTooltip('Zoom in'), findsNothing);
      expect(
        tester.getTopLeft(find.byType(TextSelectionActions)).dy,
        greaterThanOrEqualTo(
          tester.getBottomLeft(find.byType(InteractiveViewer)).dy,
        ),
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(TextSelectionActions), findsNothing);
      expect(find.byType(ReaderControls), findsOneWidget);
      expect(find.text('Selection.pdf'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final mode in ['Vertical scroll', 'Horizontal scroll']) {
    testWidgets('page picker navigates the visible document in $mode', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ViewerPage(
            engineFactory: () async => TestDocEngine(),
            initialDocumentBytes: Uint8List(100),
            initialDocumentName: 'Navigation.pdf',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Reading view'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(mode));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Page 1 of 3'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '3');
      await tester.pump();
      await tester.tap(find.text('Go to page 3'));
      await tester.pumpAndSettle();
      expect(find.text('Page 3 of 3'), findsOneWidget);
      expect(find.text('Page 3').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  Future<void> openReader(WidgetTester tester, TestDocEngine engine) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: ViewerPage(
          engineFactory: () async => engine,
          initialDocumentBytes: Uint8List(100),
          initialDocumentName: 'Gestures.pdf',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final mode in ['Vertical scroll', 'Horizontal scroll']) {
    testWidgets('zoom switches $mode from page scrolling to panning and back', (
      tester,
    ) async {
      await openReader(tester, TestDocEngine());
      await tester.tap(find.byTooltip('Reading view'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(mode));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zoom'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer))
            .panEnabled,
        isFalse,
      );
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer))
            .panEnabled,
        isTrue,
      );
      final list = find.descendant(
        of: find.byType(InteractiveViewer),
        matching: find.byType(ListView),
      );
      expect(
        tester.widget<ListView>(list).physics,
        isA<NeverScrollableScrollPhysics>(),
      );
      await tester.drag(find.byType(InteractiveViewer), const Offset(-50, -40));
      await tester.pumpAndSettle();
      expect(find.text('Page 1 of 3'), findsOneWidget);
      await tester.tap(find.byTooltip('Reset zoom to fit page'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer))
            .panEnabled,
        isFalse,
      );
      expect(
        tester.widget<ListView>(list).physics,
        isA<ClampingScrollPhysics>(),
      );
    });
  }
  testWidgets(
    'facing pages require a deliberate horizontal swipe, not taps or vertical drags',
    (tester) async {
      final engine = TestDocEngine();
      await openReader(tester, engine);
      await tester.tap(find.byTooltip('Reading view'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Facing pages'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Page 1 of 3'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '3');
      await tester.pump();
      await tester.tap(find.text('Go to page 3'));
      await tester.pumpAndSettle();
      engine.renderedPages.clear();
      await tester.tapAt(tester.getCenter(find.byType(InteractiveViewer)));
      await tester.pumpAndSettle();
      expect(engine.renderedPages, isEmpty);
      await tester.drag(find.byType(InteractiveViewer), const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(engine.renderedPages, isEmpty);
      await tester.drag(find.byType(InteractiveViewer), const Offset(110, 0));
      await tester.pumpAndSettle();
      expect(engine.renderedPages, contains(1));
    },
  );
  testWidgets(
    'long-press handles retain finger-sized targets at maximum zoom',
    (tester) async {
      await openReader(tester, SelectableEngine());
      await tester.longPressAt(
        tester.getCenter(find.byType(InteractiveViewer)),
      );
      await tester.pumpAndSettle();
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      viewer.transformationController!.value = Matrix4.identity()
        ..scaleByDouble(8, 8, 1, 1);
      await tester.pump();
      final handle = find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.label == 'Start text selection handle, line 1',
      );
      final render = tester.renderObject<RenderBox>(handle);
      final width =
          (render.localToGlobal(Offset(render.size.width, 0)) -
                  render.localToGlobal(Offset.zero))
              .distance;
      expect(width, closeTo(48, .1));
    },
  );
  testWidgets('new zoom input interrupts a double-tap animation', (
    tester,
  ) async {
    await openReader(tester, TestDocEngine());
    await tester.tap(find.text('Zoom'));
    await tester.pumpAndSettle();
    final center = tester.getCenter(find.byType(InteractiveViewer));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    final transform = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    await tester.tap(find.byTooltip('Zoom out'));
    await tester.pump();
    final scale = transform.value.getMaxScaleOnAxis();
    await tester.pump(const Duration(milliseconds: 400));
    expect(transform.value.getMaxScaleOnAxis(), closeTo(scale, .001));
  });
  testWidgets(
    'continuous long press offers selection on the actual touched page',
    (tester) async {
      await openReader(tester, SelectableEngine());
      await tester.tap(find.byTooltip('Reading view'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vertical scroll'));
      await tester.pumpAndSettle();
      await tester.longPressAt(
        tester.getCenter(find.byType(InteractiveViewer)),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Select text on page 1 in single-page view.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Select text'));
      await tester.pumpAndSettle();
      expect(find.byType(TextSelectionActions), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'facing-page long press selects the right-hand page, not the first page',
    (tester) async {
      final engine = SelectableEngine();
      await openReader(tester, engine);
      await tester.tap(find.byTooltip('Reading view'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Facing pages'));
      await tester.pumpAndSettle();
      final images = find.descendant(
        of: find.byType(InteractiveViewer),
        matching: find.byType(Image),
      );
      await tester.longPressAt(tester.getCenter(images.at(1)));
      await tester.pumpAndSettle();
      expect(
        find.text('Select text on page 2 in single-page view.'),
        findsOneWidget,
      );
      engine.renderedPages.clear();
      await tester.tap(find.text('Select text'));
      await tester.pumpAndSettle();
      expect(engine.renderedPages, contains(2));
      expect(find.byType(TextSelectionActions), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('a pinch cannot finish as a long press after one finger lifts', (
    tester,
  ) async {
    await openReader(tester, SelectableEngine());
    final center = tester.getCenter(find.byType(InteractiveViewer));
    final first = await tester.startGesture(
      center - const Offset(30, 0),
      pointer: 1,
    );
    final second = await tester.startGesture(
      center + const Offset(30, 0),
      pointer: 2,
    );
    await first.moveBy(const Offset(-20, 0));
    await second.moveBy(const Offset(20, 0));
    await second.up();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(TextSelectionActions), findsNothing);
    await first.up();
    await tester.pumpAndSettle();
    await tester.longPressAt(tester.getCenter(find.byType(InteractiveViewer)));
    await tester.pumpAndSettle();
    expect(find.byType(TextSelectionActions), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
