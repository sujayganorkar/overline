import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfcraft_mobile/main.dart';
import '../test/viewer_initialization_test.dart' show FakePdfEngine;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture baseline', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      PdfCraftApp(engineFactory: () async => FakePdfEngine()),
    );
    await tester.pumpAndSettle();

    await IntegrationTestWidgetsFlutterBinding.instance
        .convertFlutterSurfaceToImage();
    await IntegrationTestWidgetsFlutterBinding.instance
        .takeScreenshot('pdfcraft_home_baseline');
  });
}
