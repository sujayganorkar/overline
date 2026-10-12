import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfcraft_mobile/bridge/api.dart' as bridge;
import 'package:pdfcraft_mobile/services/pdf_engine.dart';
import 'package:pdfcraft_mobile/widgets/page_grid.dart';

void main() {
  testWidgets(
    'long-press then tap selects multiple pages before confirm-delete',
    (tester) async {
      final engine = _PageGridEngine();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PageGrid(
              engine: engine,
              handle: 1,
              pageCount: 3,
              currentPage: 1,
              onStatusChanged: (_) {},
              onJumpToPage: (_) {},
            ),
          ),
        ),
      );

      final cards = find.byWidgetPredicate(
        (widget) => widget is GestureDetector && widget.onLongPress != null,
      );
      await tester.longPress(cards.at(0));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('1 selected'), findsOneWidget);

      await tester.tap(cards.at(1));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(find.text('Delete 2').first);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Delete 2 pages?'), findsOneWidget);
      await tester.tap(find.text('Delete 2').last);
      await tester.pump(const Duration(milliseconds: 400));

      expect(engine.lastTool, 'page_delete');
      expect(jsonDecode(engine.lastArguments!)['pages'], [1, 2]);
      expect(find.text('Pages (1)'), findsOneWidget);
    },
  );

  testWidgets('page reorder offers direct up/down moves for touch precision', (
    tester,
  ) async {
    final engine = _PageGridEngine();
    await tester.pumpWidget(_pageGridApp(engine));
    await tester.tap(find.text('Reorder'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      find.text('Drag pages or use the arrows. Each move can be undone.'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Move later').first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(engine.lastTool, 'page_move');
    expect(jsonDecode(engine.lastArguments!)['pages'], [1]);
    expect(jsonDecode(engine.lastArguments!)['to'], 2);
  });
}

Widget _pageGridApp(_PageGridEngine engine) => MaterialApp(
  home: Scaffold(
    body: PageGrid(
      engine: engine,
      handle: 1,
      pageCount: engine.pageTotal,
      currentPage: 1,
      onStatusChanged: (_) {},
      onJumpToPage: (_) {},
    ),
  ),
);

class _PageGridEngine implements PdfEngineApi {
  String? lastTool;
  String? lastArguments;
  int pageTotal = 3;

  @override
  Future<bridge.OperationResponse> executeTool({
    required int handle,
    required String tool,
    required String argumentsJson,
  }) async {
    lastTool = tool;
    lastArguments = argumentsJson;
    if (tool == 'page_delete') {
      final args = jsonDecode(argumentsJson) as Map<String, dynamic>;
      pageTotal -= (args['pages'] as List).length;
    }
    return bridge.OperationResponse(
      contents: [],
      status: bridge.DocumentStatus(
        pageCount: pageTotal,
        dirty: true,
        editable: true,
        canUndo: 'Delete pages',
        canRedo: '',
      ),
    );
  }

  @override
  Future<Uint8List> renderPagePng({
    required int handle,
    required int page1Based,
    required int dpi,
  }) => Completer<Uint8List>().future;

  @override
  Future<int> open({
    required String name,
    required Uint8List bytes,
    String? password,
  }) => throw UnimplementedError();
  @override
  Future<int> pageCount({required int handle}) async => pageTotal;
  @override
  Future<bridge.DocumentStatus> status({required int handle}) =>
      throw UnimplementedError();
  @override
  Future<bridge.PageSize> pageSize({
    required int handle,
    required int page1Based,
  }) => throw UnimplementedError();
  @override
  Future<List<bridge.OperationInfo>> operationCatalog() =>
      throw UnimplementedError();
  @override
  Future<bridge.SaveSnapshot> saveSnapshot({required int handle}) =>
      throw UnimplementedError();
  @override
  Future<void> commitSave({required int handle, required int token}) =>
      throw UnimplementedError();
  @override
  Future<void> cancelSave({required int handle, required int token}) =>
      throw UnimplementedError();
  @override
  Future<String> stageFile({required String name, required Uint8List bytes}) =>
      throw UnimplementedError();
  @override
  Future<Uint8List> readOutput({required String path}) =>
      throw UnimplementedError();
  @override
  Future<void> close({required int handle, bool discardChanges = false}) =>
      throw UnimplementedError();
}
