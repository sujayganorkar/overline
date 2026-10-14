import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfcraft_mobile/main.dart';

import 'viewer_initialization_test.dart' show FakePdfEngine;

// Opt-in local preview export; also verifies the home at narrow phone widths.
void main() {
  testWidgets('home and tools fit a phone viewport', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const preview = bool.fromEnvironment('UX_PREVIEW');
    const fontPath = String.fromEnvironment('UX_FONT_PATH');
    if (preview && fontPath.isNotEmpty) {
      await tester.runAsync(() async {
        final fonts = FontLoader('Roboto');
        fonts.addFont(
          Future.value(ByteData.sublistView(File(fontPath).readAsBytesSync())),
        );
        await fonts.load();
        final icons = FontLoader('MaterialIcons');
        icons.addFont(
          Future.value(
            ByteData.sublistView(
              File('${File(fontPath).parent.path}/MaterialIcons-Regular.otf')
                  .readAsBytesSync(),
            ),
          ),
        );
        await icons.load();
      });
    }
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: PdfCraftApp(engineFactory: () async => FakePdfEngine()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    if (preview) {
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('/tmp/pdfcraft-home.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.ensureVisible(find.text('Browse all tools'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Browse all tools'));
    await tester.pumpAndSettle();
    expect(find.text('All tools'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
