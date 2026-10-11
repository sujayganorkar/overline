import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../bridge/api.dart' as bridge;
import '../bridge/frb_generated.dart';

abstract interface class PdfEngineApi {
  Future<int> open({
    required String name,
    required Uint8List bytes,
    String? password,
  });

  Future<int> pageCount({required int handle});

  Future<bridge.DocumentStatus> status({required int handle});

  Future<bridge.PageSize> pageSize({
    required int handle,
    required int page1Based,
  });

  Future<Uint8List> renderPagePng({
    required int handle,
    required int page1Based,
    required int dpi,
  });

  Future<List<bridge.OperationInfo>> operationCatalog();

  Future<bridge.OperationResponse> executeTool({
    required int handle,
    required String tool,
    required String argumentsJson,
  });

  Future<bridge.SaveSnapshot> saveSnapshot({required int handle});

  Future<void> commitSave({required int handle, required int token});

  Future<void> cancelSave({required int handle, required int token});

  Future<String> stageFile({required String name, required Uint8List bytes});

  Future<Uint8List> readOutput({required String path});

  Future<void> close({required int handle, bool discardChanges = false});
}

class PdfCraftEngine implements PdfEngineApi {
  PdfCraftEngine(this._engine);

  final bridge.Engine _engine;

  @override
  Future<int> open({
    required String name,
    required Uint8List bytes,
    String? password,
  }) => _engine.open(name: name, bytes: bytes, password: password);

  @override
  Future<int> pageCount({required int handle}) =>
      _engine.pageCount(handle: handle);

  @override
  Future<bridge.DocumentStatus> status({required int handle}) =>
      _engine.status(handle: handle);

  @override
  Future<bridge.PageSize> pageSize({
    required int handle,
    required int page1Based,
  }) => _engine.pageSize(handle: handle, page1Based: page1Based);

  @override
  Future<Uint8List> renderPagePng({
    required int handle,
    required int page1Based,
    required int dpi,
  }) => _engine.renderPagePng(handle: handle, page1Based: page1Based, dpi: dpi);

  @override
  Future<List<bridge.OperationInfo>> operationCatalog() =>
      _engine.operationCatalog();

  @override
  Future<bridge.OperationResponse> executeTool({
    required int handle,
    required String tool,
    required String argumentsJson,
  }) => _engine.executeTool(
    handle: handle,
    tool: tool,
    argumentsJson: argumentsJson,
  );

  @override
  Future<bridge.SaveSnapshot> saveSnapshot({required int handle}) =>
      _engine.saveSnapshot(handle: handle);

  @override
  Future<void> commitSave({required int handle, required int token}) =>
      _engine.commitSave(handle: handle, token: token);

  @override
  Future<void> cancelSave({required int handle, required int token}) =>
      _engine.cancelSave(handle: handle, token: token);

  @override
  Future<String> stageFile({required String name, required Uint8List bytes}) =>
      _engine.stageFile(name: name, bytes: bytes);

  @override
  Future<Uint8List> readOutput({required String path}) =>
      _engine.readOutput(path: path);

  @override
  Future<void> close({required int handle, bool discardChanges = false}) =>
      _engine.close(handle: handle, discardChanges: discardChanges);
}

typedef PdfEngineFactory = Future<PdfEngineApi> Function();

Future<PdfEngineApi> createPdfCraftEngine() async {
  final support = await getApplicationSupportDirectory();
  final workspace = Directory('${support.path}/pdfcraft-workspace');
  await workspace.create(recursive: true);
  await RustLib.init();
  return PdfCraftEngine(bridge.Engine(workspace: workspace.path));
}
