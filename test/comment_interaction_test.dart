import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overline/bridge/api.dart' as bridge;
import 'package:overline/widgets/comment_composer.dart';
import 'package:overline/widgets/annotate_page.dart';
import 'package:overline/widgets/comments_screen.dart';

import 'viewer_initialization_test.dart' show FakePdfEngine;

class CommentEngine extends FakePdfEngine {
  final notes = <Map<String, dynamic>>[
    for (var i = 1; i <= 35; i++)
      {
        'id': 'note-$i',
        'page': 1,
        'index': i,
        'type': 'note',
        'contents': 'Note $i',
      },
    {
      'id': 'second-page',
      'page': 2,
      'index': 35,
      'type': 'note',
      'contents': 'Target conversation',
    },
  ];
  final mutations = <(String, Map<String, dynamic>)>[];
  bool fail = false;
  List<Map<String, dynamic>>? deleted;
  @override
  Future<bridge.OperationResponse> executeTool({
    required int handle,
    required String tool,
    required String argumentsJson,
  }) async {
    final args = jsonDecode(argumentsJson) as Map<String, dynamic>;
    if (tool != 'comment_list') {
      if (fail) throw StateError('Save failed');
      mutations.add((tool, args));
      if (tool == 'edit_undo') {
        notes
          ..clear()
          ..addAll(deleted!);
      } else {
        final note = notes.firstWhere((n) => n['id'] == args['id']);
        if (tool == 'comment_delete') {
          deleted = List.of(notes);
          notes.remove(note);
        }
        if (tool == 'comment_set_status') note['status'] = args['status'];
        if (tool == 'comment_lock') note['locked'] = args['locked'];
        if (tool == 'comment_edit') note['contents'] = args['contents'];
        if (tool == 'comment_reply') {
          note['replies'] = [
            {'contents': args['text']},
          ];
        }
      }
    }
    return bridge.OperationResponse(
      contents: [
        bridge.OperationContent(
          json: jsonEncode({'comments': notes}),
          png: Uint8List(0),
          width: 0,
          height: 0,
        ),
      ],
      status: await status(handle: handle),
    );
  }
}

class NoteEngine extends FakePdfEngine {
  int writes = 0;
  @override
  Future<bridge.OperationResponse> executeTool({
    required int handle,
    required String tool,
    required String argumentsJson,
  }) async {
    if (tool == 'comment_add') writes++;
    return super.executeTool(
      handle: handle,
      tool: tool,
      argumentsJson: argumentsJson,
    );
  }
}

Future<void> openThreads(WidgetTester tester, CommentEngine engine) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: CommentsScreen(
        engine: engine,
        handle: 1,
        currentPage: 2,
        pageCount: 2,
        initialPage: 2,
        focusIndex: 35,
        onStatusChanged: (_) {},
        onJumpToPage: (_) {},
        onAddComment: (_) async {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('marker opens the exact conversation and resolves by stable ID', (
    tester,
  ) async {
    final engine = CommentEngine();
    await openThreads(tester, engine);
    expect(find.text('Conversation'), findsOneWidget);
    expect(find.text('Target conversation'), findsOneWidget);
    expect(find.text('Note 35'), findsNothing);
    await tester.tap(find.text('Resolve'));
    await tester.pumpAndSettle();
    expect(engine.mutations.single.$1, 'comment_set_status');
    expect(engine.mutations.single.$2, {
      'id': 'second-page',
      'status': 'completed',
    });
    expect(find.text('Reopen'), findsOneWidget);
    await tester.tap(find.text('Reopen'));
    await tester.pumpAndSettle();
    expect(engine.mutations.last.$2['status'], 'none');
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed reply retains draft and retry creates only one reply', (
    tester,
  ) async {
    final engine = CommentEngine()..fail = true;
    await openThreads(tester, engine);
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Keep this reply');
    await tester.pump();
    await tester.tap(find.text('Add reply'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Your draft is still here'), findsOneWidget);
    expect(find.text('Keep this reply'), findsOneWidget);
    engine.fail = false;
    await tester.tap(find.text('Add reply'));
    await tester.pumpAndSettle();
    expect(find.byType(CommentComposer), findsNothing);
    expect(find.text('Keep this reply'), findsOneWidget);
    expect(engine.mutations, hasLength(1));
  });

  testWidgets('locked conversation prevents edits and can be unlocked', (
    tester,
  ) async {
    final engine = CommentEngine();
    engine.notes.last['locked'] = true;
    await openThreads(tester, engine);
    final reply = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Reply'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(reply.onPressed, isNull);
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PopupMenuItem<String>>(
            find.ancestor(
              of: find.text('Edit note'),
              matching: find.byType(PopupMenuItem<String>),
            ),
          )
          .enabled,
      isFalse,
    );
    await tester.tap(find.text('Unlock note'));
    await tester.pumpAndSettle();
    expect(engine.mutations.single.$1, 'comment_lock');
    expect(engine.mutations.single.$2, {'id': 'second-page', 'locked': false});
  });

  testWidgets('delete returns to list and undo restores the conversation', (
    tester,
  ) async {
    final engine = CommentEngine();
    await openThreads(tester, engine);
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete conversation'));
    await tester.pumpAndSettle();
    expect(engine.mutations, isEmpty);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Notes & comments'), findsOneWidget);
    expect(find.text('Target conversation'), findsNothing);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Target conversation'), findsOneWidget);
    expect(engine.mutations.last.$1, 'edit_undo');
  });

  testWidgets('search survives opening a thread and returning to the list', (
    tester,
  ) async {
    final engine = CommentEngine();
    await openThreads(tester, engine);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Target');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Target conversation'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Target',
    );
    expect(find.text('Target conversation'), findsOneWidget);
    await tester.tap(find.text('Resolved'));
    await tester.pumpAndSettle();
    expect(find.text('Target conversation'), findsNothing);
  });

  testWidgets(
    'placing a note returns after one successful save without an extra Done step',
    (tester) async {
      final engine = NoteEngine();
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAD0lEQVR4nGP4jwQYiOMAANuQL9FuRbCyAAAAAElFTkSuQmCC',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Place a note'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => AnnotatePage(
                      engine: engine,
                      handle: 1,
                      page: 1,
                      png: png,
                      dpi: 96,
                      imageWidthPx: 400,
                      imageHeightPx: 500,
                      initialMode: AnnotateMode.note,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Place a note'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getCenter(find.byType(InteractiveViewer)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'A note on this spot');
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(CommentComposer),
          matching: find.text('Add note'),
        ),
      );
      await tester.pumpAndSettle();
      expect(engine.writes, 1);
      expect(find.byType(AnnotatePage), findsNothing);
      expect(find.text('Place a note'), findsOneWidget);
    },
  );

  testWidgets('draft guards discard and blocks duplicate submission', (
    tester,
  ) async {
    final pending = Completer<void>();
    var saves = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => CommentComposer.show(
                context,
                title: 'Add a note',
                page: 1,
                submitLabel: 'Add note',
                onSubmit: (_) {
                  saves++;
                  return pending.future;
                },
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final submit = find.widgetWithText(FilledButton, 'Add note');
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'My draft');
    await tester.tap(find.byTooltip('Close draft'));
    await tester.pumpAndSettle();
    expect(find.text('Discard this draft?'), findsOneWidget);
    await tester.tap(find.text('Keep writing'));
    await tester.pumpAndSettle();
    expect(find.text('My draft'), findsOneWidget);
    await tester.tap(submit);
    await tester.pump();
    expect(saves, 1);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CommentComposer), findsNothing);
  });
}
