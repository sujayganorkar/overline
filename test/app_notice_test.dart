import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfcraft_mobile/widgets/app_notice.dart';

void main() {
  late BuildContext source;
  Future<void> open(WidgetTester tester, {bool accessible = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [NoticeNavigatorObserver()],
        home: Builder(
          builder: (context) {
            return MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(accessibleNavigation: accessible),
              child: Builder(
                builder: (context) {
                  source = context;
                  return const Scaffold(body: Center(child: Text('Document')));
                },
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('latest feedback replaces old messages without a backlog', (
    tester,
  ) async {
    await open(tester);
    AppNotice.show(
      source,
      const AppNotice(message: 'First', kind: NoticeKind.success),
    );
    await tester.pump();
    AppNotice.show(
      source,
      const AppNotice(message: 'Latest', kind: NoticeKind.success),
    );
    await tester.pump();
    expect(find.text('First'), findsNothing);
    expect(find.text('Latest'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(find.text('Latest'), findsNothing);
    expect(find.text('First'), findsNothing);
  });

  testWidgets('errors persist, disclose details on demand, and dismiss', (
    tester,
  ) async {
    await open(tester);
    AppNotice.show(
      source,
      const AppNotice(
        message: 'Could not save your PDF.',
        details: 'Storage provider returned an error.',
        kind: NoticeKind.error,
      ),
    );
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('Could not save your PDF.'), findsOneWidget);
    expect(find.text('Storage provider returned an error.'), findsNothing);
    await tester.tap(find.text('Show details'));
    await tester.pump();
    expect(find.text('Storage provider returned an error.'), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss notification'));
    await tester.pump();
    expect(find.text('Could not save your PDF.'), findsNothing);
  });

  testWidgets('Undo stays available and runs once', (tester) async {
    await open(tester);
    var calls = 0;
    AppNotice.show(
      source,
      AppNotice(
        message: 'Page rotated.',
        kind: NoticeKind.success,
        action: NoticeAction(label: 'Undo', onPressed: () => calls++),
      ),
    );
    await tester.pump(const Duration(seconds: 30));
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(calls, 1);
    expect(find.text('Page rotated.'), findsNothing);
  });

  testWidgets('screen reader feedback does not expire and announces changes', (
    tester,
  ) async {
    await open(tester, accessible: true);
    AppNotice.show(
      source,
      const AppNotice(message: 'Text copied.', kind: NoticeKind.success),
    );
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('Text copied.'), findsOneWidget);
    final semantics = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.text('Text copied.'),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(semantics.properties.liveRegion, isTrue);
    AppNotice.dismiss(source);
    await tester.pump();
  });

  testWidgets('notification is usable above an open modal sheet', (
    tester,
  ) async {
    await open(tester);
    late BuildContext sheetContext;
    showModalBottomSheet<void>(
      context: source,
      builder: (context) {
        sheetContext = context;
        return const SizedBox(
          height: 300,
          child: Center(child: Text('Export options')),
        );
      },
    );
    await tester.pumpAndSettle();
    AppNotice.show(
      sheetContext,
      const AppNotice(message: 'Could not export.', kind: NoticeKind.error),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Dismiss notification'));
    await tester.pump();
    expect(find.text('Could not export.'), findsNothing);
    expect(find.text('Export options'), findsOneWidget);
  });

  testWidgets('leaving an edit screen removes its Undo action', (tester) async {
    await open(tester);
    late BuildContext editContext;
    Navigator.of(source).push(
      MaterialPageRoute<void>(
        builder: (context) {
          editContext = context;
          return const Scaffold(body: Text('Edit page'));
        },
      ),
    );
    await tester.pumpAndSettle();
    var calls = 0;
    AppNotice.show(
      editContext,
      AppNotice(
        message: 'Signature placed.',
        action: NoticeAction(label: 'Undo', onPressed: () => calls++),
      ),
    );
    await tester.pump();
    Navigator.pop(editContext);
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsNothing);
    expect(calls, 0);
  });

  testWidgets('large text and long details fit narrow screens', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester);
    AppNotice.show(
      source,
      AppNotice(
        message: 'Could not save this document. Your changes are still open.',
        details: List.filled(30, 'Provider information.').join(' '),
        kind: NoticeKind.error,
      ),
    );
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -450),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Show details'));
    await tester.tap(find.text('Show details'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Hide details'), findsOneWidget);
    AppNotice.dismiss(source);
    await tester.pump();
  });

  testWidgets('disposing the app cancels notification timers', (tester) async {
    await open(tester);
    AppNotice.show(
      source,
      const AppNotice(message: 'Copied', kind: NoticeKind.success),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  testWidgets('repeated confirmations do not prolong or duplicate the notice', (
    tester,
  ) async {
    await open(tester);
    const notice = AppNotice(message: 'Copied', kind: NoticeKind.success);
    AppNotice.show(source, notice);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    AppNotice.show(source, notice);
    await tester.pump();
    expect(find.text('Copied'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Copied'), findsNothing);
  });

  testWidgets('notification leaves the rest of the document interactive', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            source = context;
            return Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => taps++,
                  child: const Text('Document control'),
                ),
              ),
            );
          },
        ),
      ),
    );
    AppNotice.show(
      source,
      const AppNotice(message: 'Could not save.', kind: NoticeKind.error),
    );
    await tester.pump();
    await tester.tap(find.text('Document control'));
    expect(taps, 1);
    expect(find.text('Could not save.'), findsOneWidget);
    AppNotice.dismiss(source);
    await tester.pump();
  });
}
