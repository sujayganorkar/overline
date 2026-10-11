import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfcraft_mobile/bridge/api.dart' as bridge;
import 'package:pdfcraft_mobile/main.dart';
import 'package:pdfcraft_mobile/services/pdf_engine.dart';

class FakePdfEngine implements PdfEngineApi {
  @override
  Future<int> open({
    required String name,
    required Uint8List bytes,
    String? password,
  }) async => 1;

  @override
  Future<int> pageCount({required int handle}) async => 1;

  @override
  Future<bridge.DocumentStatus> status({required int handle}) async =>
      const bridge.DocumentStatus(
        pageCount: 1,
        dirty: false,
        editable: true,
        canUndo: '',
        canRedo: '',
      );

  @override
  Future<bridge.PageSize> pageSize({
    required int handle,
    required int page1Based,
  }) async => const bridge.PageSize(width: 612, height: 792);

  @override
  Future<Uint8List> renderPagePng({
    required int handle,
    required int page1Based,
    required int dpi,
  }) async => Uint8List(0);

  @override
  Future<List<bridge.OperationInfo>> operationCatalog() async => const [];

  @override
  Future<bridge.OperationResponse> executeTool({
    required int handle,
    required String tool,
    required String argumentsJson,
  }) async => bridge.OperationResponse(
    contents: const [],
    status: await status(handle: handle),
  );

  @override
  Future<bridge.SaveSnapshot> saveSnapshot({required int handle}) async =>
      bridge.SaveSnapshot(token: 1, bytes: Uint8List(0));

  @override
  Future<void> commitSave({required int handle, required int token}) async {}

  @override
  Future<void> cancelSave({required int handle, required int token}) async {}

  @override
  Future<String> stageFile({
    required String name,
    required Uint8List bytes,
  }) async => 'imports/$name';

  @override
  Future<Uint8List> readOutput({required String path}) async => Uint8List(0);

  @override
  Future<void> close({
    required int handle,
    bool discardChanges = false,
  }) async {}
}

void main() {
  testWidgets('viewer reports that the PdfCraft engine is ready', (
    tester,
  ) async {
    await tester.pumpWidget(
      PdfCraftApp(engineFactory: () async => FakePdfEngine()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Engine ready (PdfCraft Rust core)'), findsWidgets);
    expect(find.text('PdfCraft Mobile'), findsOneWidget);
  });

  testWidgets('viewer shows an engine initialization error', (tester) async {
    await tester.pumpWidget(
      PdfCraftApp(
        engineFactory: () => Future.error(StateError('native loader failure')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Engine init failed'), findsWidgets);
  });
}
