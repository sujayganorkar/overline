import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../bridge/api.dart' as bridge;
import '../bridge/frb_generated.dart';
import 'offline_ocr.dart';

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

  Future<bridge.SaveSnapshot> prepareSaveAs({required int handle});

  Future<void> commitSave({required int handle, required int token});

  Future<void> cancelSave({required int handle, required int token});

  Future<String> stageFile({required String name, required Uint8List bytes});

  Future<Uint8List> readOutput({required String path});

  Future<void> close({required int handle, bool discardChanges = false});
}

class PdfCraftEngine implements PdfEngineApi {
  PdfCraftEngine(this._engine);

  final bridge.Engine _engine;
  Future<void>? _ocrReady;

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
  }) async {
    if (tool == 'printer_papers') {
      const paths = MethodChannel('app.overline.pdf/paths');
      final papers = await paths.invokeListMethod<Object?>(
        'getStandardPaperSizes',
      );
      return bridge.OperationResponse(
        status: const bridge.DocumentStatus(
          pageCount: 0,
          dirty: false,
          editable: false,
          canUndo: '',
          canRedo: '',
        ),
        contents: [
          bridge.OperationContent(
            json: jsonEncode({
              'source': 'Android standard media sizes',
              'papers': papers,
              'note': 'Choose a printer in Android print preview to see the sizes it supports.',
            }),
            png: Uint8List(0),
            width: 0,
            height: 0,
          ),
        ],
      );
    }
    if (tool.startsWith('ocr_') || tool == 'doc_batch') {
      try {
        await (_ocrReady ??= prepareOfflineOcr());
      } catch (_) {
        _ocrReady = null;
        rethrow;
      }
    }
    return _engine.executeTool(
      handle: handle,
      tool: tool,
      argumentsJson: argumentsJson,
    );
  }

  @override
  Future<bridge.SaveSnapshot> saveSnapshot({required int handle}) =>
      _engine.saveSnapshot(handle: handle);

  @override
  Future<bridge.SaveSnapshot> prepareSaveAs({required int handle}) =>
      _engine.prepareSaveAs(handle: handle);

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
  // First-party channel (see MainActivity.kt): avoids plugins that ship
  // prebuilt native libraries for ABIs without a PdfCraft build.
  if (!Platform.isAndroid) {
    throw UnsupportedError(
      'Overline currently supports Android only; iOS packaging is a later milestone.',
    );
  }
  const channel = MethodChannel('app.overline.pdf/paths');
  final workspace = await channel.invokeMethod<String>('getSupportDir');
  if (workspace == null || workspace.isEmpty) {
    throw StateError('Could not locate the app support directory');
  }
  await RustLib.init();
  return PdfCraftEngine(bridge.Engine(workspace: workspace));
}
