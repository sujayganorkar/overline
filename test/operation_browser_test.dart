import 'dart:async';
import 'dart:convert';

import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overline/bridge/api.dart' as bridge;
import 'package:overline/widgets/operation_browser.dart';
import 'package:overline/widgets/output_saver.dart';

import 'viewer_initialization_test.dart' show FakePdfEngine;

class _Engine extends FakePdfEngine {
  @override
  Future<Uint8List> renderPagePng({
    required int handle,
    required int page1Based,
    required int dpi,
  }) async => base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+rNMkAAAAASUVORK5CYII=',
  );

  final calls = <(String, Map<String, dynamic>)>[];
  @override
  Future<bridge.OperationResponse> executeTool({
    required int handle,
    required String tool,
    required String argumentsJson,
  }) async {
    final args = jsonDecode(argumentsJson) as Map<String, dynamic>;
    calls.add((tool, args));
    final payload = switch (tool) {
      'comments_copy' => {'xfdf': '<xfdf><annots/></xfdf>', 'comments': 1},
      'comment_list' => {
        'comments': [
          {'page': 2, 'index': 1, 'type': 'Note', 'contents': 'Read this'},
        ],
      },
      'doc_rename' => {'path': 'imports/finished.pdf', 'name': 'finished.pdf'},
      'object_list' => {
        'objects': [
          {'kind': 'text', 'index': 2, 'text': 'Introduction'},
        ],
        'generation': 9,
      },
      'doc_export_office' => {
        'path': args['path'],
        'warnings': [
          {'message': 'Test warning'},
        ],
      },
      _ => {'written': true},
    };
    return bridge.OperationResponse(
      contents: [
        bridge.OperationContent(
          json: jsonEncode(payload),
          png: Uint8List(0),
          width: 0,
          height: 0,
        ),
      ],
      status: await status(handle: handle),
    );
  }
}

class _Picker extends FilePickerPlatform {
  _Picker([this.fileName = 'sample.pdf']);
  final String fileName;
  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => _File(fileName);
}

final class _File extends PlatformFile {
  _File(this.name);
  @override
  final String name;
  @override
  Future<Uint8List> readAsBytes() async => Uint8List.fromList([37, 80, 68, 70]);
  @override
  Stream<Uint8List> readAsByteStream() => Stream.fromFuture(readAsBytes());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _open(
  WidgetTester t,
  _Engine engine,
  String tool,
  Map<String, dynamic> props,
  List<String> required, {
  bool destructive = false,
  bool requiresDocument = true,
  ValueChanged<String>? onRename,
}) async {
  await t.pumpWidget(
    MaterialApp(
      home: OperationScreen(
        key: ValueKey(tool),
        onRename: onRename,
        engine: engine,
        handle: requiresDocument ? 1 : 0,
        currentPage: 2,
        onStatusChanged: (_) {},
        operation: bridge.OperationInfo(
          id: tool,
          title: tool,
          description: '',
          inputSchemaJson: jsonEncode({
            'type': 'object',
            'properties': props,
            'required': required,
            'additionalProperties': false,
          }),
          readOnly: !destructive,
          destructive: destructive,
          commandId: '',
          requiresDocument: requiresDocument,
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> _tap(WidgetTester t, Finder target) async {
  await t.ensureVisible(target);
  await t.tap(target);
  await t.pumpAndSettle();
}

Finder _field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

void main() {
  testWidgets('printer profile list accepts a selected ICC before scanning', (
    t,
  ) async {
    final old = FilePickerPlatform.instance;
    FilePickerPlatform.instance = _Picker('printer.icc');
    addTearDown(() => FilePickerPlatform.instance = old);
    final engine = _Engine();
    await _open(
      t,
      engine,
      'print_color_profiles',
      {},
      [],
      requiresDocument: false,
    );
    await _tap(t, find.text('Import an ICC profile'));
    expect(find.text('Imported printer.icc'), findsOneWidget);
    await _tap(t, find.byKey(const ValueKey('execute-operation')));
    expect(engine.calls.single.$1, 'print_color_profiles');
    expect(engine.calls.single.$2, isEmpty);
  });
  testWidgets('a union field can change from a name to a numeric layer', (
    t,
  ) async {
    final engine = _Engine();
    await _open(
      t,
      engine,
      'layer_set',
      {
        'layer': {
          'type': ['string', 'integer'],
        },
      },
      ['layer'],
    );
    expect(t.takeException(), isNull);
    await _tap(t, find.text('Text'));
    await _tap(t, find.text('Whole number').last);
    await t.enterText(_field('Layer'), '2');
    await _tap(t, find.byKey(const ValueKey('execute-operation')));
    expect(t.takeException(), isNull);
    expect(engine.calls.single.$2, {'layer': 2});
  });
  for (final cancelled in [false, true]) {
    testWidgets('Android batch folder, cancel = $cancelled', (t) async {
      final engine = _Engine();
      const paths = MethodChannel('app.overline.pdf/paths');
      final calls = <MethodCall>[];
      final stage = Completer<Map<String, Object?>>();
      final platform = t.binding.defaultBinaryMessenger;
      platform.setMockMethodCallHandler(paths, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'pickBatchSources':
            expect(call.arguments['folder'], true);
            return [
              {'token': 'granted', 'name': 'Nested PDFs', 'folder': true},
            ];
          case 'stageBatchSources':
            expect(call.arguments, {
              'tokens': ['granted'],
              'recursive': true,
            });
            return stage.future;
          case 'cancelBatchImport':
            stage.completeError(
              PlatformException(
                code: 'CANCELLED',
                message: 'Folder import cancelled.',
              ),
            );
            return null;
          case 'releaseBatchStage':
            expect(call.arguments, {'token': 'copied'});
            return null;
          case 'forgetBatchSources':
            expect(call.arguments, {
              'tokens': ['granted'],
            });
            return null;
          default:
            throw StateError(call.method);
        }
      });
      addTearDown(() => platform.setMockMethodCallHandler(paths, null));
      await _open(
        t,
        engine,
        'doc_batch',
        {
          'paths': {
            'type': 'array',
            'items': {'type': 'string'},
            'minItems': 1,
          },
          'recursive': {'type': 'boolean'},
          'steps': {
            'type': 'array',
            'minItems': 1,
            'uniqueItems': true,
            'items': {
              'type': 'string',
              'enum': ['convert', 'ocr', 'optimize'],
            },
          },
        },
        ['paths', 'recursive', 'steps'],
        requiresDocument: false,
      );
      await _tap(t, find.text('Choose folder'));
      await _tap(t, find.text('Choose folder'));
      expect(find.text('Nested PDFs'), findsOneWidget);
      await _tap(t, find.text('ocr'));
      await _tap(t, find.text('optimize'));
      await _tap(t, find.text('ocr'));
      await t.tap(find.byKey(const ValueKey('execute-operation')));
      await t.pump();
      expect(find.text('Cancel import'), findsOneWidget);
      expect(engine.calls, isEmpty);
      if (cancelled) {
        await t.tap(find.text('Cancel import'));
      } else {
        stage.complete({
          'token': 'copied',
          'paths': ['imports/batch-copied/0/Nested PDFs'],
        });
      }
      await t.pumpAndSettle();
      if (cancelled) {
        expect(engine.calls, isEmpty);
        expect(find.textContaining('Folder import cancelled'), findsOneWidget);
      } else {
        expect(engine.calls.single.$2, {
          'paths': ['imports/batch-copied/0/Nested PDFs'],
          'recursive': true,
          'steps': ['convert', 'optimize'],
        });
        expect(
          calls.where((c) => c.method == 'releaseBatchStage'),
          hasLength(1),
        );
      }
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      expect(calls.last.method, 'forgetBatchSources');
    });
  }
  testWidgets('formats, confined output, validation and nested findings', (
    t,
  ) async {
    final engine = _Engine();
    await _open(
      t,
      engine,
      'doc_export_office',
      {
        'path': {'type': 'string'},
        'rich': {'type': 'boolean'},
      },
      ['path'],
    );
    await _tap(t, find.text('PPTX'));
    expect(
      t.widget<TextField>(_field('Output file name')).controller!.text,
      endsWith('.pptx'),
    );
    await t.enterText(_field('Output file name'), '../bad.pptx');
    await _tap(t, find.byKey(const ValueKey('execute-operation')));
    expect(engine.calls, isEmpty);
    expect(find.textContaining('without a path'), findsOneWidget);
    await t.enterText(_field('Output file name'), 'deck.pptx');
    await _tap(t, find.byKey(const ValueKey('execute-operation')));
    expect(engine.calls.single.$2, {'path': 'outputs/deck.pptx'});
    expect(find.text('deck.pptx'), findsOneWidget);
    await _tap(t, find.text('Warnings (1)'));
    expect(find.text('Test warning (1)'), findsOneWidget);
    await _tap(t, find.text('Edit settings'));
    expect(
      t.widget<TextField>(_field('Output file name')).controller!.text,
      'deck.pptx',
    );
  });
  testWidgets('stages nested file inputs and confirms before editing', (
    t,
  ) async {
    final old = FilePickerPlatform.instance;
    FilePickerPlatform.instance = _Picker();
    addTearDown(() => FilePickerPlatform.instance = old);
    final engine = _Engine();
    await _open(
      t,
      engine,
      'doc_bates_multi',
      {
        'files': {
          'type': 'array',
          'minItems': 1,
          'items': {
            'type': 'object',
            'properties': {
              'input': {'type': 'string'},
              'output': {'type': 'string'},
              'password': {'type': 'string'},
            },
            'required': ['input', 'output'],
            'additionalProperties': false,
          },
        },
      },
      ['files'],
      destructive: true,
      requiresDocument: false,
    );
    await _tap(t, find.text('Choose a file'));
    await t.enterText(_field('Output file name'), 'stamped.pdf');
    await _tap(t, find.byKey(const ValueKey('execute-operation')));
    await _tap(t, find.text('Cancel'));
    expect(engine.calls, isEmpty);
    await _tap(t, find.byKey(const ValueKey('execute-operation')));
    await _tap(t, find.text('Continue'));
    expect(engine.calls.single.$2, {
      'files': [
        {'input': 'imports/sample.pdf', 'output': 'outputs/stamped.pdf'},
      ],
    });
  });
  testWidgets('choosing an object sends its document generation and index', (
    t,
  ) async {
    final engine = _Engine();
    await _open(
      t,
      engine,
      'object_copy',
      {
        'page': {'type': 'integer', 'minimum': 1},
        'generation': {'type': 'integer'},
        'objects': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'kind': {'type': 'string'},
              'index': {'type': 'integer'},
            },
            'required': ['kind', 'index'],
          },
        },
        'cut': {'type': 'boolean'},
      },
      ['page'],
    );
    await _tap(t, find.text('Choose page objects'));
    await _tap(t, find.text('text 2'));
    await _tap(t, find.text('Use selection (1)'));
    await _tap(t, find.byKey(const ValueKey('execute-operation')));
    expect(engine.calls.first.$1, 'object_list');
    expect(engine.calls.first.$2, {'page': 2});
    expect(engine.calls.last.$2, {
      'page': 2,
      'generation': 9,
      'objects': [
        {'kind': 'text', 'index': 2},
      ],
    });
  });

  testWidgets('copy and paste comments across screens without entering XFDF', (
    t,
  ) async {
    final engine = _Engine();
    await _open(
      t,
      engine,
      'comments_copy',
      {
        'comments': {
          'type': 'array',
          'items': {
            'type': 'array',
            'items': {'type': 'integer'},
            'minItems': 2,
            'maxItems': 2,
          },
          'minItems': 1,
        },
      },
      ['comments'],
    );
    await _tap(t, find.text('Choose comments'));
    await _tap(t, find.text('Read this'));
    await _tap(t, find.text('Use selection (1)'));
    await _tap(t, find.byKey(const ValueKey('execute-operation')));
    expect(engine.calls.last.$2, {
      'comments': [
        [2, 1],
      ],
    });
    expect(find.text('Copy XFDF to clipboard'), findsOneWidget);
    await _open(
      t,
      engine,
      'comments_paste',
      {
        'page': {'type': 'integer'},
        'xfdf': {'type': 'string'},
      },
      ['page', 'xfdf'],
    );
    expect(find.text('Copied comments'), findsOneWidget);
    expect(_field('Xfdf'), findsNothing);
    await _tap(t, find.byKey(const ValueKey('execute-operation')));
    expect(engine.calls.last.$2, {'page': 2, 'xfdf': '<xfdf><annots/></xfdf>'});
  });

  testWidgets(
    'compact keyboard leaves apply reachable and uses confirmed rename',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(360, 640);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetViewInsets);
      final engine = _Engine();
      String? renamed;
      await _open(
        t,
        engine,
        'doc_rename',
        {
          'name': {'type': 'string'},
          'optional': {'type': 'boolean'},
        },
        ['name'],
        onRename: (s) => renamed = s,
      );
      t.view.viewInsets = const FakeViewPadding(bottom: 282);
      await t.tap(_field('Name'));
      await t.enterText(_field('Name'), 'finished');
      await t.pumpAndSettle();
      expect(find.byType(SwitchListTile), findsNothing);
      final action = find.byKey(const ValueKey('execute-operation'));
      expect(t.getBottomRight(action).dy, lessThanOrEqualTo(640 - 282));
      await t.tap(action);
      await t.pumpAndSettle();
      expect(renamed, 'finished.pdf');
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('image hit test uses points tapped on the displayed PDF', (
    t,
  ) async {
    final engine = _Engine();
    await _open(
      t,
      engine,
      'image_hit',
      {
        'page': {'type': 'integer'},
        'point': {
          'type': 'array',
          'items': {'type': 'number'},
          'minItems': 2,
          'maxItems': 2,
        },
      },
      ['page', 'point'],
    );
    await _tap(t, find.text('Tap a position'));
    final rect = t.getRect(find.byType(Image));
    await t.tapAt(rect.topLeft + Offset(rect.width * .25, rect.height * .75));
    await t.pumpAndSettle();
    await _tap(t, find.text('Use selection'));
    await _tap(t, find.byKey(const ValueKey('execute-operation')));
    expect(engine.calls.last.$2, {
      'page': 2,
      'point': [153.0, 594.0],
    });
  });

  test('planned, failed and external files are excluded from delivery', () {
    expect(
      outputPathsIn('{"dry_run":true,"files":[{"output":"outputs/a.pdf"}]}'),
      isEmpty,
    );
    expect(
      outputPathsIn(
        '{"files":[{"status":"error","output":"outputs/a.pdf"},{"status":"ok","output":"outputs/b.pdf"},{"path":"secret.db"}]}',
      ),
      ['outputs/b.pdf'],
    );
    expect(isOfferableOutput(r'outputs/..\secret'), isFalse);
    expect(mimeTypeFor('deck.pptx'), contains('presentation'));
    expect(mimeTypeFor('notes.md'), 'text/markdown');
  });
}
