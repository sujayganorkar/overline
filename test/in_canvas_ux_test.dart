import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfcraft_mobile/bridge/api.dart' as bridge;
import 'package:pdfcraft_mobile/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'viewer_initialization_test.dart' show FakePdfEngine;

class TestDocEngine extends FakePdfEngine {
  TestDocEngine({this.pages = 3});
  final int pages;

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
    // 4x4 transparent PNG
    return base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAD0lEQVR4nGP4jwQYiOMAANuQL9FuRbCyAAAAAElFTkSuQmCC',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.pdfcraft.pdfcraft_mobile/paths');
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

  testWidgets('in-canvas mode switches between Read, Markup, and Sign without route thrashing', (tester) async {
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
    debugPrint('Found texts after pumpAndSettle: ${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).toList()}');

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
  });
}
