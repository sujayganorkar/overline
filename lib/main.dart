import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'bridge/api.dart' as bridge;
import 'services/pdf_engine.dart';
import 'services/signature_store.dart';
import 'services/recent_documents_store.dart';
import 'widgets/annotate_page.dart';
import 'widgets/agent_command_sheet.dart';
import 'widgets/annotation_geometry.dart' as annotation_geo;
import 'widgets/bookmarks_screen.dart';
import 'widgets/comments_screen.dart';
import 'widgets/document_heading.dart';
import 'widgets/document_insights_sheet.dart';
import 'widgets/export_sheet.dart';
import 'widgets/links_screen.dart';
import 'widgets/find_bar.dart';
import 'widgets/form_screen.dart';
import 'widgets/organize_sheet.dart';
import 'widgets/page_grid.dart';
import 'widgets/page_viewport.dart';
import 'widgets/quick_mark_page.dart';
import 'widgets/recipes_sheet.dart';
import 'widgets/secure_sheet.dart';
import 'widgets/signature_pad.dart';
import 'widgets/signature_placement_page.dart';
import 'widgets/signature_sheet.dart';
import 'widgets/text_edit_sheet.dart';
import 'widgets/output_saver.dart';
import 'widgets/zoom_controls.dart';

void main() {
  runApp(const PdfCraftApp());
}

class PdfCraftApp extends StatelessWidget {
  const PdfCraftApp({super.key, this.engineFactory = createPdfCraftEngine});

  final PdfEngineFactory engineFactory;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PdfCraft Mobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: ViewerPage(engineFactory: engineFactory),
    );
  }
}

enum WorkflowOutcome {
  completed,
  cancelled,
  failed,
  needsInput,
}

class ViewerPage extends StatefulWidget {
  const ViewerPage({super.key, required this.engineFactory});

  final PdfEngineFactory engineFactory;

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> with WidgetsBindingObserver {
  PdfEngineApi? _engine;
  int? _doc;
  int _pageCount = 0;
  int _page = 1; // 1-based
  Uint8List? _png;
  String? _name;
  String _status = 'Starting engine';
  bool _busy = false;
  bool _dirty = false;
  bool _finding = false;
  List<FindMatch> _findMatches = const [];
  int _findActiveIndex = -1;
  final RecentDocumentsStore _recentStore = RecentDocumentsStore();
  List<RecentDocumentEntry> _recentDocuments = const [];
  String? _undoLabel;
  String? _redoLabel;
  List<_Marker> _markers = const [];
  double? _imageWidthPx;
  double? _imageHeightPx;
  List<TextLineBox> _pageTextLines = const [];
  bool _pageTextLoading = false;
  int? _textSelectionAnchor;
  int? _textSelectionExtent;
  String _textSelectionKind = 'highlight';
  String _textSelectionColor = 'yellow';
  bool _recoveredUnsaved = false;
  bool _recoveryAvailable = false;
  int _activeSurface = 0;
  static bool _coachShown = false;
  final TransformationController _viewerTransform = TransformationController();
  final GlobalKey _viewerPageKey = GlobalKey();
  int _viewerPointerCount = 0;
  Offset? _viewerSwipeStart;
  bool _viewerLongPressSelecting = false;
  Timer? _recoveryDebounce;
  Future<void> _recoveryWrites = Future<void>.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initEngine();
    _loadRecents();
  }

  Future<void> _loadRecents() async {
    final list = await _recentStore.loadRecents();
    if (mounted) setState(() => _recentDocuments = list);
  }

  Future<void> _initEngine() async {
    try {
      final engine = await widget.engineFactory();
      if (!mounted) return;
      setState(() {
        _engine = engine;
        _status = 'Engine ready (PdfCraft Rust core)';
      });
      unawaited(_offerRecovery(engine));
      _setupNativeChannels();
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Engine init failed: $e');
    }
  }

  void _setupNativeChannels() {
    const channel = MethodChannel('com.pdfcraft.pdfcraft_mobile/paths');
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onPdfReceived') {
        final args = call.arguments;
        if (args is Map) {
          final name = args['name'] as String?;
          final path = args['path'] as String?;
          if (name != null && path != null) {
            await _openIncomingPdf(name, path);
          }
        }
      }
    });

    channel.invokeMethod<Map<Object?, Object?>>('getInitialPdf').then((pdf) {
      if (pdf != null) {
        final name = pdf['name'] as String?;
        final path = pdf['path'] as String?;
        if (name != null && path != null) {
          _openIncomingPdf(name, path);
        }
      }
    }).catchError((_) {});
  }

  Future<void> _openIncomingPdf(String name, String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return;
      await _openDocumentBytes(name, bytes);
    } catch (e) {
      debugPrint('Could not open incoming PDF: $e');
    }
  }

  Future<void> _openDocumentBytes(String name, Uint8List bytes) async {
    if (!await _confirmReplacingCurrent()) return;
    setState(() {
      _busy = true;
      _status = 'Opening $name\u2026';
    });
    final engine = _engine;
    if (engine == null) throw StateError('engine not initialized');
    final previousDoc = _doc;
    int? openedDoc;
    try {
      openedDoc = await _openDocument(engine, name, bytes);
      if (openedDoc == null) {
        if (mounted) setState(() => _status = 'Open cancelled');
        return;
      }
      final count = await engine.pageCount(handle: openedDoc);
      final status = await engine.status(handle: openedDoc);
      if (!mounted) {
        await engine.close(handle: openedDoc);
        return;
      }
      setState(() {
        _doc = openedDoc;
        _name = name;
        _pageCount = count;
        _page = 1;
        _dirty = status.dirty;
        _recoveredUnsaved = false;
        _recoveryAvailable = false;
        _status = 'Opened $name';
      });
      await _clearRecoveryCheckpoint();
      if (previousDoc != null) {
        try {
          await engine.close(handle: previousDoc);
        } catch (error) {
          debugPrint('Could not close previous PDF document: $error');
        }
      }
      await _render();
      unawaited(
        _recentStore
            .recordOpened(
              name: name,
              pageCount: count,
              bytes: bytes,
            )
            .then((_) => _loadRecents()),
      );
    } catch (e) {
      if (openedDoc != null) {
        try {
          await _engine?.close(handle: openedDoc);
        } catch (closeError) {
          debugPrint(
            'Could not close document after open failure: $closeError',
          );
        }
      }
      if (!mounted) return;
      setState(() => _status = 'Open failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open() async {
    try {
      final files = await FilePickerPlatform.instance.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (!mounted || files.isEmpty) return;
      final file = files.first;
      final fileBytes = await file.readAsBytes();
      if (!mounted || fileBytes.isEmpty) return;
      await _openDocumentBytes(file.name, fileBytes);
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Open failed: $e');
    }
  }

  Future<void> _openRecent(RecentDocumentEntry entry) async {
    if (_busy || entry.cachedFilePath == null) return;
    final file = File(entry.cachedFilePath!);
    if (!await file.exists()) {
      await _recentStore.removeRecent(entry.name);
      await _loadRecents();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File is no longer available.')),
        );
      }
      return;
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return;
    await _openDocumentBytes(entry.name, bytes);
  }

  Future<bool> _confirmReplacingCurrent() async {
    final doc = _doc;
    final engine = _engine;
    if (doc == null || engine == null || !_dirty) return true;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text('Save this PDF before opening another document?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null || choice == 'cancel') return false;
    if (choice == 'save') {
      await _save();
      return mounted && !_dirty;
    }
    await engine.close(handle: doc, discardChanges: true);
    await _clearRecoveryCheckpoint();
    if (!mounted) return false;
    setState(() {
      _doc = null;
      _name = null;
      _pageCount = 0;
      _page = 1;
      _png = null;
      _dirty = false;
      _recoveredUnsaved = false;
      _recoveryAvailable = false;
      _status = 'Changes discarded';
    });
    return true;
  }

  Future<int?> _openDocument(
    PdfEngineApi engine,
    String name,
    Uint8List bytes,
  ) async {
    try {
      return await engine.open(name: name, bytes: bytes, password: null);
    } catch (error) {
      if (!error.toString().toLowerCase().contains('password')) rethrow;
      if (!mounted) return null;
      final password = await _askForPassword(name);
      if (password == null) return null;
      return engine.open(name: name, bytes: bytes, password: password);
    }
  }

  Future<String?> _askForPassword(String name) async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('PDF password required'),
          content: TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            decoration: InputDecoration(labelText: 'Password for $name'),
            onSubmitted: (password) => Navigator.of(context).pop(password),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Open'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _render() async {
    final doc = _doc;
    final engine = _engine;
    if (doc == null || engine == null) return;
    final page = _page;
    setState(() {
      _busy = true;
      _status = 'Rendering page $page\u2026';
    });
    try {
      final png = await engine.renderPagePng(
        handle: doc,
        page1Based: page,
        dpi: 96,
      );
      final pageSize = await engine.pageSize(handle: doc, page1Based: page);
      if (!mounted || _doc != doc || _page != page) return;
      final firstRender = _png == null;
      setState(() {
        _png = png;
        _imageWidthPx = pageSize.width * 96 / 72;
        _imageHeightPx = pageSize.height * 96 / 72;
        _markers = const [];
        _pageTextLines = const [];
        _pageTextLoading = true;
        _status = 'Ready';
      });
      if (firstRender && !_coachShown) {
        _coachShown = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Hold text to select it · Swipe to turn pages · Pinch to zoom',
            ),
            duration: Duration(seconds: 5),
          ),
        );
      }
      await _refreshMarkers(engine, doc, page, pageSize: pageSize);
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Render failed: $e');
      _png = null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Comment markers for the current page, positioned in render pixels so
  /// they scale with the image inside the viewer. Tapping one opens its
  /// thread — closing the loop between seeing and discussing.
  Future<void> _refreshMarkers(
    PdfEngineApi engine,
    int doc,
    int page, {
    bridge.PageSize? pageSize,
  }) async {
    try {
      final size =
          pageSize ?? await engine.pageSize(handle: doc, page1Based: page);
      final response = await engine.executeTool(
        handle: doc,
        tool: 'comment_list',
        argumentsJson: '{"page": $page}',
      );
      if (!mounted || _doc != doc || _page != page) return;
      const dpi = 96.0;
      final widthPx = size.width * dpi / 72.0;
      final heightPx = size.height * dpi / 72.0;
      final markers = <_Marker>[];
      for (final content in response.contents) {
        if (content.json.isEmpty) continue;
        final decoded = jsonDecode(content.json);
        final list = decoded is Map<String, dynamic>
            ? decoded['comments']
            : null;
        if (list is! List) continue;
        for (final item in list) {
          if (item is! Map<String, dynamic>) continue;
          final rect = item['rect'];
          if (rect is! List || rect.length != 4) continue;
          final x0 = (rect[0] as num).toDouble() * dpi / 72.0;
          final y0 = (rect[1] as num).toDouble() * dpi / 72.0;
          markers.add(
            _Marker(
              x: x0.clamp(0, widthPx),
              y: y0.clamp(0, heightPx),
              label: _commentMarkerLabel(
                (item['type'] as String?) ?? 'comment',
              ),
              index: (item['index'] as num?)?.toInt() ?? 0,
            ),
          );
        }
      }
      final lineResponse = await engine.executeTool(
        handle: doc,
        tool: 'text_lines',
        argumentsJson: jsonEncode({'page': page}),
      );
      final pageLines = <TextLineBox>[];
      for (final content in lineResponse.contents) {
        if (content.json.isEmpty) continue;
        final decoded = jsonDecode(content.json);
        final lines = decoded is Map<String, dynamic> ? decoded['lines'] : null;
        if (lines is! List) continue;
        for (final item in lines) {
          if (item is! Map<String, dynamic>) continue;
          final rect = item['rect'];
          if (rect is! List || rect.length != 4) continue;
          pageLines.add(
            TextLineBox(
              text: item['text'] as String? ?? '',
              rect: [for (final value in rect) (value as num).toDouble()],
            ),
          );
        }
      }
      setState(() {
        _imageWidthPx = widthPx;
        _imageHeightPx = heightPx;
        _markers = markers;
        _pageTextLines = pageLines;
        _pageTextLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _pageTextLoading = false);
      debugPrint('Could not load comment markers: $e');
    }
  }

  Future<void> _goto(int page) async {
    if (page < 1 || page > _pageCount || page == _page) return;
    _page = page;
    _textSelectionAnchor = null;
    _textSelectionExtent = null;
    _viewerTransform.value = Matrix4.identity();
    await _render();
  }

  Future<void> _goToPagePrompt() async {
    final controller = TextEditingController(text: '$_page');
    try {
      final entered = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Go to page'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.go,
            decoration: InputDecoration(labelText: 'Page 1–$_pageCount'),
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Go'),
            ),
          ],
        ),
      );
      if (entered == null || !mounted) return;
      final page = int.tryParse(entered.trim());
      if (page == null || page < 1 || page > _pageCount) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Enter a page from 1 to $_pageCount.')),
        );
        return;
      }
      await _goto(page);
    } finally {
      controller.dispose();
    }
  }

  void _onViewerPointerDown(PointerDownEvent event) {
    _viewerPointerCount++;
    if (_viewerPointerCount == 1) _viewerLongPressSelecting = false;
    _viewerSwipeStart = _viewerPointerCount == 1 ? event.position : null;
  }

  void _onViewerPointerUp(PointerEvent event) {
    _viewerPointerCount = math.max(0, _viewerPointerCount - 1);
    if (_viewerPointerCount > 0) return;
    final start = _viewerSwipeStart;
    _viewerSwipeStart = null;
    if (start == null ||
        _busy ||
        _doc == null ||
        _viewerLongPressSelecting ||
        _textSelectionAnchor != null) {
      _viewerLongPressSelecting = false;
      return;
    }
    final delta = event.position - start;
    final destination = pageForSwipe(
      delta,
      currentPage: _page,
      pageCount: _pageCount,
      scale: _viewerTransform.value.getMaxScaleOnAxis(),
    );
    if (destination != null) unawaited(_goto(destination));
  }

  void _beginTextSelection(Offset pageLocalPosition, double fitScale) {
    _viewerLongPressSelecting = true;
    if (_pageTextLoading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Getting this page’s text ready…')),
      );
      return;
    }
    if (_pageTextLines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This page has no selectable text.')),
      );
      return;
    }
    final x = annotation_geo.pxToPt(pageLocalPosition.dx / fitScale, 96);
    final y = annotation_geo.pxToPt(pageLocalPosition.dy / fitScale, 96);
    final line = _nearestTextLine(x, y);
    if (line == null) return;
    setState(() {
      _textSelectionAnchor = line;
      _textSelectionExtent = line;
    });
  }

  void _extendTextSelection(Offset pageLocalPosition, double fitScale) {
    final x = annotation_geo.pxToPt(pageLocalPosition.dx / fitScale, 96);
    final y = annotation_geo.pxToPt(pageLocalPosition.dy / fitScale, 96);
    final line = _nearestTextLine(x, y);
    if (line != null) setState(() => _textSelectionExtent = line);
  }

  void _moveTextSelectionHandle(
    DragUpdateDetails details,
    double fitScale, {
    required bool anchor,
  }) {
    final render = _viewerPageKey.currentContext?.findRenderObject();
    if (render is! RenderBox) return;
    final local = render.globalToLocal(details.globalPosition);
    final x = annotation_geo.pxToPt(local.dx / fitScale, 96);
    final y = annotation_geo.pxToPt(local.dy / fitScale, 96);
    final line = _nearestTextLine(x, y);
    if (line == null) return;
    setState(() {
      if (anchor) {
        _textSelectionAnchor = line;
      } else {
        _textSelectionExtent = line;
      }
    });
  }

  int? _nearestTextLine(double x, double y) {
    var bestIndex = -1;
    var bestDistance = double.infinity;
    for (var index = 0; index < _pageTextLines.length; index++) {
      final rect = _pageTextLines[index].rect;
      if (rect.length != 4) continue;
      final dx = x < rect[0]
          ? rect[0] - x
          : x > rect[2]
          ? x - rect[2]
          : 0.0;
      final dy = y < rect[1]
          ? rect[1] - y
          : y > rect[3]
          ? y - rect[3]
          : 0.0;
      final distance = dx * dx + dy * dy;
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = index;
      }
    }
    return bestIndex >= 0 && bestDistance <= 64 * 64 ? bestIndex : null;
  }

  Future<void> _copyTextSelection() async {
    final anchor = _textSelectionAnchor;
    final extent = _textSelectionExtent;
    if (anchor == null || extent == null) return;
    final start = math.min(anchor, extent);
    final end = math.max(anchor, extent);
    final text = [
      for (var index = start; index <= end; index++) _pageTextLines[index].text,
    ].join('\n').trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('These lines hold no copyable text.')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Selected text copied.')));
  }

  Future<void> _applyTextSelection() async {
    final anchor = _textSelectionAnchor;
    final extent = _textSelectionExtent;
    final engine = _engine;
    final doc = _doc;
    if (anchor == null || extent == null || engine == null || doc == null) {
      return;
    }
    final start = math.min(anchor, extent);
    final end = math.max(anchor, extent);
    final quads = <List<double>>[];
    for (var index = start; index <= end; index++) {
      final rect = _pageTextLines[index].rect;
      quads.add([
        rect[0],
        rect[1],
        rect[2],
        rect[1],
        rect[0],
        rect[3],
        rect[2],
        rect[3],
      ]);
    }
    if (quads.isEmpty) return;
    setState(() => _busy = true);
    try {
      final response = await engine.executeTool(
        handle: doc,
        tool: 'comment_add',
        argumentsJson: jsonEncode({
          'page': _page,
          'type': _textSelectionKind,
          'quads': quads,
          if (_textSelectionKind == 'highlight') 'color': _textSelectionColor,
        }),
      );
      if (!mounted) return;
      setState(() {
        _textSelectionAnchor = null;
        _textSelectionExtent = null;
      });
      _onOperationStatus(response.status);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Marked ${quads.length} selected line${quads.length == 1 ? '' : 's'}.',
          ),
          action: SnackBarAction(label: 'Undo', onPressed: _undo),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _status = 'Could not mark selected text: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Color _selectionColorForName(String name) => switch (name) {
    'green' => Colors.green,
    'blue' => Colors.blue,
    'red' => Colors.red,
    _ => Colors.yellow,
  };

  void _onViewerPointerCancel(PointerCancelEvent event) {
    _viewerPointerCount = math.max(0, _viewerPointerCount - 1);
    _viewerSwipeStart = null;
  }

  Future<void> _save() async {
    final doc = _doc;
    final engine = _engine;
    if (doc == null || engine == null || _name == null) return;
    bridge.SaveSnapshot? snapshot;
    var externalSaved = false;
    _recoveryDebounce?.cancel();
    await _recoveryWrites;
    setState(() => _busy = true);
    try {
      snapshot = await engine.saveSnapshot(handle: doc);
      final safeName = _name!.replaceAll(RegExp(r'[/\\]'), '_');
      final uri = await FilePickerPlatform.instance.saveFile(
        fileName: safeName,
        bytes: snapshot.bytes,
        mimeType: 'application/pdf',
        dialogTitle: 'Save PDF As',
      );
      if (!mounted) return;
      if (uri == null) {
        await engine.cancelSave(handle: doc, token: snapshot.token);
        snapshot = null;
        setState(() => _status = 'Save cancelled');
      } else {
        externalSaved = true;
        final savedBytes = snapshot.bytes;
        await engine.commitSave(handle: doc, token: snapshot.token);
        snapshot = null;
        final status = await engine.status(handle: doc);
        await _clearRecoveryCheckpoint();
        unawaited(
          _recentStore
              .recordOpened(
                name: _name!,
                pageCount: _pageCount,
                bytes: savedBytes,
              )
              .then((_) => _loadRecents()),
        );
        if (!mounted) return;
        setState(() {
          _dirty = status.dirty;
          _recoveredUnsaved = false;
          _recoveryAvailable = false;
          _status = 'Saved $safeName through Files';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved $safeName through Files')),
        );
      }
    } catch (e) {
      if (snapshot != null) {
        try {
          await engine.cancelSave(handle: doc, token: snapshot.token);
        } catch (cancelError) {
          debugPrint('Could not cancel pending save snapshot: $cancelError');
        }
      }
      if (!mounted) return;
      setState(
        () => _status = externalSaved
            ? 'File was written, but engine save state failed: $e'
            : 'Save failed: $e',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareCurrentPdf() async {
    final doc = _doc;
    final engine = _engine;
    final currentName = _name;
    if (doc == null || engine == null || currentName == null || _busy) return;
    bridge.SaveSnapshot? snapshot;
    setState(() {
      _busy = true;
      _status = 'Preparing PDF to share…';
    });
    try {
      _recoveryDebounce?.cancel();
      await _recoveryWrites;
      snapshot = await engine.saveSnapshot(handle: doc);
      final baseName = currentName.replaceAll(RegExp(r'[/\\]'), '_');
      final fileName = baseName.toLowerCase().endsWith('.pdf')
          ? baseName
          : '$baseName.pdf';
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              snapshot.bytes,
              mimeType: 'application/pdf',
              name: fileName,
            ),
          ],
          subject: fileName,
          text: 'Shared from PdfCraft Mobile',
        ),
      );
      if (mounted) setState(() => _status = 'Share sheet opened');
    } catch (error) {
      if (mounted) setState(() => _status = 'Share failed: $error');
    } finally {
      if (snapshot != null) {
        try {
          await engine.cancelSave(handle: doc, token: snapshot.token);
        } catch (error) {
          debugPrint('Could not release shared PDF snapshot: $error');
        }
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Directory> _recoveryDirectory() async {
    const channel = MethodChannel('com.pdfcraft.pdfcraft_mobile/paths');
    final supportPath = await channel.invokeMethod<String>('getSupportDir');
    if (supportPath == null || supportPath.isEmpty) {
      throw StateError('Could not locate app storage for recovery');
    }
    final directory = Directory('$supportPath/recovery');
    await directory.create(recursive: true);
    return directory;
  }

  Future<void> _clearRecoveryCheckpoint() async {
    try {
      final directory = await _recoveryDirectory();
      for (final name in [
        'recovery.pdf',
        'recovery.json',
        'recovery.pdf.tmp',
      ]) {
        final file = File('${directory.path}/$name');
        if (await file.exists()) await file.delete();
      }
      if (mounted) setState(() => _recoveryAvailable = false);
    } catch (error) {
      debugPrint('Could not clear recovery checkpoint: $error');
    }
  }

  void _scheduleRecoveryCheckpoint() {
    if (!_dirty || _doc == null) return;
    _recoveryDebounce?.cancel();
    _recoveryDebounce = Timer(
      const Duration(milliseconds: 700),
      () => unawaited(_queueRecoveryCheckpoint()),
    );
  }

  Future<void> _queueRecoveryCheckpoint() {
    final next = _recoveryWrites.then((_) => _writeRecoveryCheckpoint());
    _recoveryWrites = next.catchError((Object error) {
      debugPrint('Could not checkpoint PDF recovery: $error');
    });
    return _recoveryWrites;
  }

  Future<void> _writeRecoveryCheckpoint() async {
    final doc = _doc;
    final engine = _engine;
    final name = _name;
    if (doc == null || engine == null || name == null || !_dirty) return;
    bridge.SaveSnapshot? snapshot;
    try {
      snapshot = await engine.saveSnapshot(handle: doc);
      if (!mounted || _doc != doc) return;
      final directory = await _recoveryDirectory();
      final file = File('${directory.path}/recovery.pdf');
      await File('${file.path}.tmp').writeAsBytes(snapshot.bytes, flush: true);
      await File('${file.path}.tmp').rename(file.path);
      await File('${directory.path}/recovery.json').writeAsString(
        jsonEncode({'name': name, 'savedAt': DateTime.now().toIso8601String()}),
        flush: true,
      );
      if (mounted) setState(() => _recoveryAvailable = true);
    } finally {
      if (snapshot != null) {
        try {
          await engine.cancelSave(handle: doc, token: snapshot.token);
        } catch (error) {
          debugPrint('Could not release recovery snapshot: $error');
        }
      }
    }
  }

  Future<void> _offerRecovery(PdfEngineApi engine) async {
    try {
      final directory = await _recoveryDirectory();
      final file = File('${directory.path}/recovery.pdf');
      if (!await file.exists() || !mounted || _doc != null) return;
      var originalName = 'document.pdf';
      final metadata = File('${directory.path}/recovery.json');
      if (await metadata.exists()) {
        try {
          final decoded = jsonDecode(await metadata.readAsString());
          if (decoded is Map<String, dynamic> && decoded['name'] is String) {
            originalName = decoded['name'] as String;
          }
        } catch (_) {
          // A torn metadata write must not make a valid PDF checkpoint unusable.
        }
      }
      if (!mounted) return;
      final choice = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Unsaved work found'),
          content: Text(
            'PdfCraft recovered an automatic copy of $originalName. Restore it now?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'later'),
              child: const Text('Keep for later'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'discard'),
              child: const Text('Discard copy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'restore'),
              child: const Text('Restore'),
            ),
          ],
        ),
      );
      if (!mounted || choice == null) return;
      if (choice == 'discard') {
        await _clearRecoveryCheckpoint();
        return;
      }
      if (choice != 'restore') return;
      final bytes = await file.readAsBytes();
      final doc = await engine.open(
        name: 'Recovered - $originalName',
        bytes: bytes,
      );
      final count = await engine.pageCount(handle: doc);
      if (!mounted) {
        await engine.close(handle: doc, discardChanges: true);
        return;
      }
      setState(() {
        _doc = doc;
        _name = 'Recovered - $originalName';
        _page = 1;
        _pageCount = count;
        _dirty = true;
        _recoveredUnsaved = true;
        _recoveryAvailable = true;
        _status = 'Recovered unsaved work — save to keep these changes';
      });
      await _render();
    } catch (error) {
      if (mounted) {
        setState(() => _status = 'Could not restore recovery copy: $error');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_busy) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _recoveryDebounce?.cancel();
      unawaited(_queueRecoveryCheckpoint());
    }
  }

  void _onOperationStatus(bridge.DocumentStatus status) {
    if (!mounted) return;
    setState(() {
      _pageCount = status.pageCount;
      _dirty = status.dirty || _recoveredUnsaved;
      if (_dirty) _recoveryAvailable = false;
      _undoLabel = status.canUndo.isEmpty ? null : status.canUndo;
      _redoLabel = status.canRedo.isEmpty ? null : status.canRedo;
      if (_page > _pageCount && _pageCount > 0) _page = _pageCount;
      _status = status.dirty ? 'Unsaved changes' : 'Operation complete';
      if (status.pageCount == 0) _png = null;
    });
    if (_dirty) _scheduleRecoveryCheckpoint();
    if (_pageCount > 0) unawaited(_render());
  }

  Future<void> _undo() async {
    final doc = _doc;
    final engine = _engine;
    if (doc == null || engine == null) return;
    setState(() => _busy = true);
    try {
      final response = await engine.executeTool(
        handle: doc,
        tool: 'edit_undo',
        argumentsJson: '{}',
      );
      if (!mounted) return;
      _onOperationStatus(response.status);
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Undo failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undoRecentEdits(int count) async {
    final doc = _doc;
    final engine = _engine;
    if (doc == null || engine == null || count < 1 || _busy) return;
    setState(() => _busy = true);
    try {
      bridge.DocumentStatus? status;
      var undone = 0;
      while (undone < count) {
        final response = await engine.executeTool(
          handle: doc,
          tool: 'edit_undo',
          argumentsJson: '{}',
        );
        status = response.status;
        undone++;
        if (status.canUndo.isEmpty) break;
      }
      if (!mounted) return;
      if (status != null) _onOperationStatus(status);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Undid $undone change${undone == 1 ? '' : 's'}.'),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _status = 'Undo failed: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _redo() async {
    final doc = _doc;
    final engine = _engine;
    if (doc == null || engine == null) return;
    setState(() => _busy = true);
    try {
      final response = await engine.executeTool(
        handle: doc,
        tool: 'edit_redo',
        argumentsJson: '{}',
      );
      if (!mounted) return;
      _onOperationStatus(response.status);
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Redo failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _annotateDpi = 96;

  Future<void> _openAnnotate({
    AnnotateMode initialMode = AnnotateMode.ink,
  }) async {
    final doc = _doc;
    final engine = _engine;
    final png = _png;
    if (doc == null || engine == null || png == null) return;
    setState(() => _busy = true);
    try {
      final size = await engine.pageSize(handle: doc, page1Based: _page);
      if (!mounted) return;
      final status = await Navigator.push<bridge.DocumentStatus>(
        context,
        MaterialPageRoute(
          builder: (context) => AnnotatePage(
            engine: engine,
            handle: doc,
            page: _page,
            png: png,
            imageWidthPx: size.width * _annotateDpi / 72.0,
            imageHeightPx: size.height * _annotateDpi / 72.0,
            dpi: _annotateDpi,
            initialMode: initialMode,
            onStatusChanged: _onOperationStatus,
          ),
        ),
      );
      if (status != null) _onOperationStatus(status);
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Annotate failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<WorkflowOutcome> _highlightPhrase() async {
    final doc = _doc;
    final engine = _engine;
    if (doc == null || engine == null) return WorkflowOutcome.failed;
    final controller = TextEditingController();
    var allMatches = true;
    var entireDocument = false;
    try {
      final entered = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Find text to highlight'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    labelText: 'Words or phrase',
                    border: OutlineInputBorder(),
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Highlight every match'),
                  value: allMatches,
                  onChanged: (value) =>
                      setDialogState(() => allMatches = value ?? true),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Search every page'),
                  subtitle: const Text('Leave off to work only on this page.'),
                  value: entireDocument,
                  onChanged: (value) =>
                      setDialogState(() => entireDocument = value ?? false),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Find matches'),
              ),
            ],
          ),
        ),
      );
      if (entered != true) return WorkflowOutcome.cancelled;
      if (!mounted) return WorkflowOutcome.cancelled;
      final phrase = controller.text.trim();
      if (phrase.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enter the words you want to highlight.'),
          ),
        );
        return WorkflowOutcome.cancelled;
      }
      setState(() => _busy = true);
      bridge.DocumentStatus? latestStatus;
      try {
        final matches = <Map<String, dynamic>>[];
        var startPage = entireDocument ? 1 : _page;
        var skip = 0;
        while (true) {
          final found = await engine.executeTool(
            handle: doc,
            tool: 'text_find',
            argumentsJson: jsonEncode({
              'query': phrase,
              'limit': 500,
              'start_page': startPage,
              'skip': skip,
            }),
          );
          final source = found.contents
              .where((content) => content.json.isNotEmpty)
              .map((content) => content.json)
              .firstOrNull;
          final data = source == null ? null : jsonDecode(source);
          if (data is! Map<String, dynamic>) {
            throw StateError('Could not search this PDF.');
          }
          final batch = data['matches'];
          if (batch is List) {
            matches.addAll(batch.whereType<Map<String, dynamic>>());
          }
          if (data['complete'] == true) break;
          if (matches.length >= 5000) {
            throw StateError(
              'More than 5,000 matches were found. Narrow the phrase before highlighting.',
            );
          }
          final next = data['next'];
          if (next is! Map<String, dynamic> ||
              next['start_page'] is! int ||
              next['skip'] is! int) {
            throw StateError('Could not continue searching this PDF.');
          }
          if (!entireDocument && (next['start_page'] as int) > _page) {
            break;
          }
          startPage = next['start_page'] as int;
          skip = next['skip'] as int;
        }
        final matchingPages =
            matches
                .where((match) => entireDocument || match['page'] == _page)
                .map((match) => match['page'])
                .whereType<int>()
                .toSet()
                .toList()
              ..sort();
        final visibleMatches = matches
            .where((match) => entireDocument || match['page'] == _page)
            .toList();
        if (visibleMatches.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No matches found in this PDF.')),
            );
          }
          return WorkflowOutcome.cancelled;
        }
        final matchCount = allMatches
            ? visibleMatches.length
            : matchingPages.length;
        if (!mounted) return WorkflowOutcome.cancelled;
        final approved = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              '$matchCount match${matchCount == 1 ? '' : 'es'} found',
            ),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pages ${matchingPages.join(', ')}. ${allMatches ? 'Every match' : 'The first match on each page'} will be highlighted.',
                  ),
                  const SizedBox(height: 10),
                  for (final match in visibleMatches.take(4))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        'Page ${match['page']}: ${match['text']}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('Highlight $matchCount'),
              ),
            ],
          ),
        );
        if (approved != true || !mounted) return WorkflowOutcome.cancelled;
        setState(() => _status = 'Adding reviewed highlights…');
        for (final page in matchingPages) {
          final response = await engine.executeTool(
            handle: doc,
            tool: 'comment_add',
            argumentsJson: jsonEncode({
              'page': page,
              'type': 'highlight',
              'find': phrase,
              if (allMatches) 'all': true,
            }),
          );
          latestStatus = response.status;
        }
        if (!mounted) return WorkflowOutcome.completed;
        if (latestStatus != null) _onOperationStatus(latestStatus);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Highlighted $matchCount match${matchCount == 1 ? '' : 'es'}${entireDocument ? ' across ${matchingPages.length} pages' : ' on page $_page'}.',
            ),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => _undoRecentEdits(matchingPages.length),
            ),
          ),
        );
        return WorkflowOutcome.completed;
      } catch (e) {
        if (!mounted) return WorkflowOutcome.failed;
        if (latestStatus != null) _onOperationStatus(latestStatus);
        setState(() => _status = 'Highlight failed: $e');
        return WorkflowOutcome.failed;
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    } finally {
      controller.dispose();
    }
  }

  Future<WorkflowOutcome> _openForms() async {
    final engine = _engine;
    final doc = _doc;
    if (engine == null || doc == null) return WorkflowOutcome.failed;
    final applied = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => FormScreen(
          engine: engine,
          handle: doc,
          onStatusChanged: _onOperationStatus,
        ),
      ),
    );
    return applied == true
        ? WorkflowOutcome.completed
        : WorkflowOutcome.cancelled;
  }

  Future<WorkflowOutcome> _openSignature() async {
    final engine = _engine;
    final doc = _doc;
    if (engine == null || doc == null) return WorkflowOutcome.failed;
    final store = SignatureStore();
    final savedTyped = await store.loadTypedName();
    final savedDrawn = await store.loadDrawn();
    if (!mounted) return WorkflowOutcome.cancelled;
    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Add to this PDF',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 4),
              if (savedTyped != null || savedDrawn != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      'Saved on this device',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ),
              if (savedTyped != null)
                ListTile(
                  leading: const Icon(Icons.history_outlined),
                  title: Text('Use “$savedTyped”'),
                  subtitle: const Text('Tap to place it'),
                  onTap: () => Navigator.pop(context, 'saved_typed'),
                ),
              if (savedDrawn != null)
                ListTile(
                  leading: const Icon(Icons.history_outlined),
                  title: const Text('Use saved drawing'),
                  subtitle: const Text('Tap to place it'),
                  onTap: () => Navigator.pop(context, 'saved_drawn'),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    'Create new',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.draw_outlined),
                title: const Text('Type a signature'),
                subtitle: const Text('Place a typed name on a page'),
                onTap: () => Navigator.pop(context, 'type'),
              ),
              ListTile(
                leading: const Icon(Icons.gesture),
                title: const Text('Draw a signature'),
                subtitle: const Text('Sign with your finger'),
                onTap: () => Navigator.pop(context, 'draw'),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    'Quick marks',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.calendar_today_outlined),
                title: const Text('Place today’s date'),
                subtitle: const Text('Tap the page where it belongs'),
                onTap: () => Navigator.pop(context, 'date'),
              ),
              ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: const Text('Add a checkmark or mark'),
                subtitle: const Text('Check, cross, dot, or line'),
                onTap: () => Navigator.pop(context, 'mark'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return WorkflowOutcome.cancelled;
    if (choice == 'date') {
      await _openQuickMark();
      return WorkflowOutcome.completed;
    }
    if (choice == 'mark') {
      final mark = await showModalBottomSheet<({String type, String label})>(
        context: context,
        useSafeArea: true,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in const [
                (type: 'check', label: 'Check ✓'),
                (type: 'cross', label: 'Cross ✕'),
                (type: 'dot', label: 'Dot ●'),
                (type: 'line', label: 'Line ―'),
              ])
                ListTile(
                  leading: Text(
                    option.label.split(' ').last,
                    style: const TextStyle(fontSize: 22),
                  ),
                  title: Text(option.label.split(' ').first),
                  onTap: () => Navigator.pop(context, option),
                ),
            ],
          ),
        ),
      );
      if (!mounted || mark == null) return WorkflowOutcome.cancelled;
      await _openQuickMark(markType: mark.type, markLabel: mark.label);
      return WorkflowOutcome.completed;
    }
    if (choice == 'saved_typed' && savedTyped != null) {
      final outcome = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (context) => SignaturePlacementPage(
            engine: engine,
            handle: doc,
            initialPage: _page,
            pageCount: _pageCount,
            onStatusChanged: _onOperationStatus,
            typedText: savedTyped,
          ),
        ),
      );
      if (outcome == 'share' && mounted) {
        await _shareCurrentPdf();
      }
      return outcome != null
          ? WorkflowOutcome.completed
          : WorkflowOutcome.cancelled;
    }
    if (choice == 'saved_drawn' && savedDrawn != null) {
      setState(() => _busy = true);
      try {
        final staged = await engine.stageFile(
          name: 'signature.png',
          bytes: savedDrawn,
        );
        if (!mounted) return WorkflowOutcome.cancelled;
        final outcome = await Navigator.push<String>(
          context,
          MaterialPageRoute(
            builder: (context) => SignaturePlacementPage(
              engine: engine,
              handle: doc,
              initialPage: _page,
              pageCount: _pageCount,
              onStatusChanged: _onOperationStatus,
              imagePath: staged,
              imageBytes: savedDrawn,
            ),
          ),
        );
        if (outcome == 'share' && mounted) {
          await _shareCurrentPdf();
        }
        return outcome != null
            ? WorkflowOutcome.completed
            : WorkflowOutcome.cancelled;
      } catch (e) {
        if (!mounted) return WorkflowOutcome.failed;
        setState(() => _status = 'Signature failed: $e');
        return WorkflowOutcome.failed;
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    if (choice == 'draw') {
      final png = await showModalBottomSheet<Uint8List>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => const SignaturePad(),
      );
      if (!mounted || png == null || png.isEmpty) {
        return WorkflowOutcome.cancelled;
      }
      await store.saveDrawn(png);
      setState(() => _busy = true);
      try {
        final staged = await engine.stageFile(
          name: 'signature.png',
          bytes: png,
        );
        if (!mounted) return WorkflowOutcome.cancelled;
        final outcome = await Navigator.push<String>(
          context,
          MaterialPageRoute(
            builder: (context) => SignaturePlacementPage(
              engine: engine,
              handle: doc,
              initialPage: _page,
              pageCount: _pageCount,
              onStatusChanged: _onOperationStatus,
              imagePath: staged,
              imageBytes: png,
            ),
          ),
        );
        if (outcome == 'share' && mounted) {
          await _shareCurrentPdf();
        }
        return outcome != null
            ? WorkflowOutcome.completed
            : WorkflowOutcome.cancelled;
      } catch (e) {
        if (!mounted) return WorkflowOutcome.failed;
        setState(() => _status = 'Signature failed: $e');
        return WorkflowOutcome.failed;
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    if (choice == 'type') {
      final name = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => const SignatureSheet(),
      );
      if (!mounted || name == null || name.trim().isEmpty) {
        return WorkflowOutcome.cancelled;
      }
      await store.saveTypedName(name.trim());
      if (!mounted) return WorkflowOutcome.cancelled;
      final outcome = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (context) => SignaturePlacementPage(
            engine: engine,
            handle: doc,
            initialPage: _page,
            pageCount: _pageCount,
            onStatusChanged: _onOperationStatus,
            typedText: name.trim(),
          ),
        ),
      );
      if (outcome == 'share' && mounted) {
        await _shareCurrentPdf();
      }
      return outcome != null
          ? WorkflowOutcome.completed
          : WorkflowOutcome.cancelled;
    }
    return WorkflowOutcome.completed;
  }

  Future<WorkflowOutcome> _openPages() async {
    final engine = _engine;
    final doc = _doc;
    if (engine == null || doc == null) return WorkflowOutcome.failed;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => PageGrid(
        engine: engine,
        handle: doc,
        pageCount: _pageCount,
        currentPage: _page,
        onStatusChanged: _onOperationStatus,
        onJumpToPage: _goto,
      ),
    );
    return WorkflowOutcome.completed;
  }

  Future<void> _openQuickMark({String? markType, String? markLabel}) async {
    final engine = _engine;
    final doc = _doc;
    final png = _png;
    if (engine == null || doc == null || png == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => QuickMarkPage(
          engine: engine,
          handle: doc,
          page: _page,
          pageCount: _pageCount,
          png: png,
          onStatusChanged: _onOperationStatus,
          markType: markType,
          markLabel: markLabel,
        ),
      ),
    );
  }

  Future<void> _openComments({int? page, int? focusIndex}) async {
    final engine = _engine;
    final doc = _doc;
    if (engine == null || doc == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => CommentsScreen(
          engine: engine,
          handle: doc,
          onStatusChanged: _onOperationStatus,
          onJumpToPage: _goto,
          onAddComment: () => _openAnnotate(initialMode: AnnotateMode.note),
          initialPage: page,
          focusIndex: focusIndex,
        ),
      ),
    );
  }

  Future<void> _openBookmarks() async {
    final engine = _engine;
    final doc = _doc;
    if (engine == null || doc == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => BookmarksScreen(
          engine: engine,
          handle: doc,
          currentPage: _page,
          onStatusChanged: _onOperationStatus,
          onJumpToPage: _goto,
        ),
      ),
    );
  }

  Future<void> _openLinks() async {
    final engine = _engine;
    final doc = _doc;
    if (engine == null || doc == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => LinksScreen(
          engine: engine,
          handle: doc,
          onStatusChanged: _onOperationStatus,
          onJumpToPage: _goto,
        ),
      ),
    );
  }

  Future<void> _openInsights({String? initialQuestion}) async {
    final engine = _engine;
    final doc = _doc;
    if (engine == null || doc == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => DocumentInsightsSheet(
        engine: engine,
        handle: doc,
        initialQuestion: initialQuestion,
        onJumpToPage: _goto,
      ),
    );
  }

  Future<WorkflowOutcome> _openSecure() async {
    final engine = _engine;
    final doc = _doc;
    if (engine == null || doc == null) return WorkflowOutcome.failed;
    var statusChanged = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SecureSheet(
        engine: engine,
        handle: doc,
        onStatusChanged: (status) {
          statusChanged = true;
          _onOperationStatus(status);
        },
      ),
    );
    return statusChanged ? WorkflowOutcome.completed : WorkflowOutcome.cancelled;
  }

  Future<WorkflowOutcome> _openOrganize() async {
    final engine = _engine;
    final doc = _doc;
    if (engine == null) return WorkflowOutcome.failed;
    var statusChanged = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => OrganizeSheet(
        engine: engine,
        handle: doc ?? 0,
        pageCount: _pageCount,
        hasDocument: doc != null,
        documentName: _name,
        onOpenPages: () async => await _openPages(),
        onStatusChanged: (status) {
          statusChanged = true;
          _onOperationStatus(status);
        },
      ),
    );
    return statusChanged ? WorkflowOutcome.completed : WorkflowOutcome.cancelled;
  }

  Future<WorkflowOutcome> _openExport() async {
    final engine = _engine;
    final doc = _doc;
    if (engine == null || doc == null) return WorkflowOutcome.failed;
    var statusChanged = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => ExportSheet(
        engine: engine,
        handle: doc,
        page: _page,
        pageCount: _pageCount,
        onStatusChanged: (status) {
          statusChanged = true;
          _onOperationStatus(status);
        },
      ),
    );
    return statusChanged ? WorkflowOutcome.completed : WorkflowOutcome.cancelled;
  }

  Future<void> _openTextEdit() async {
    final engine = _engine;
    final doc = _doc;
    final png = _png;
    if (engine == null || doc == null || png == null) return;
    final size = await engine.pageSize(handle: doc, page1Based: _page);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => TextEditSheet(
        engine: engine,
        handle: doc,
        page: _page,
        png: png,
        imageWidthPx: size.width * _annotateDpi / 72,
        imageHeightPx: size.height * _annotateDpi / 72,
        onStatusChanged: _onOperationStatus,
      ),
    );
  }

  Future<WorkflowOutcome> _openRecipes({String? initialAction}) async {
    final engine = _engine;
    final doc = _doc;
    if (engine == null || doc == null) return WorkflowOutcome.failed;
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => RecipesSheet(
        engine: engine,
        handle: doc,
        pageCount: _pageCount,
        initialAction: initialAction,
        onStatusChanged: _onOperationStatus,
      ),
    );
    if (!mounted || action == null) return WorkflowOutcome.cancelled;
    switch (action) {
      case 'pages':
        return await _openPages();
      case 'reviewPhones':
        return await _openSecure();
      case 'compress':
      case 'compare':
        return await _openExport();
      default:
        return WorkflowOutcome.completed;
    }
  }

  Future<String?> _chooseSurfaceAction(
    String title,
    List<({String id, String label, String detail, IconData icon})> actions,
  ) => showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 4),
            if (actions.length > 2)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final action in actions.take(3))
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ActionChip(
                            avatar: Icon(action.icon, size: 18),
                            label: Text(action.label),
                            onPressed: () => Navigator.pop(context, action.id),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                physics: const ClampingScrollPhysics(),
                children: [
                  for (final action in actions)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      leading: CircleAvatar(
                        radius: 20,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: Icon(
                          action.icon,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      title: Text(
                        action.label,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text(action.detail),
                      onTap: () => Navigator.pop(context, action.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _openSurface(int index) async {
    if (_busy) return;
    setState(() => _activeSurface = index);
    if (index == 3) {
      await _openAgentCommand();
      return;
    }
    final actions = switch (index) {
      0 => <({String id, String label, String detail, IconData icon})>[
        (
          id: 'find',
          label: 'Find in PDF',
          detail: 'Search and step through matches',
          icon: Icons.search,
        ),
        (
          id: 'bookmarks',
          label: 'Bookmarks',
          detail: 'Jump to saved sections',
          icon: Icons.bookmark_outline,
        ),
        (
          id: 'comments',
          label: 'Comments',
          detail: 'Review notes and threads',
          icon: Icons.comment_outlined,
        ),
        (
          id: 'insights',
          label: 'Summary & evidence',
          detail: 'Find sourced excerpts or get an extractive summary',
          icon: Icons.summarize_outlined,
        ),
        (
          id: 'links',
          label: 'Links',
          detail: 'Open or remove links in this document',
          icon: Icons.link_outlined,
        ),
      ],
      1 => <({String id, String label, String detail, IconData icon})>[
        (
          id: 'draw',
          label: 'Draw & annotate',
          detail: 'Write, mark, and point directly on the page',
          icon: Icons.brush_outlined,
        ),
        (
          id: 'selectText',
          label: 'Select text to mark',
          detail: 'Drag across text; PdfCraft snaps the preview to full lines',
          icon: Icons.select_all,
        ),
        (
          id: 'highlight',
          label: 'Highlight text',
          detail: 'Find a phrase and preview all matches',
          icon: Icons.highlight_outlined,
        ),
        (
          id: 'sign',
          label: 'Sign & date',
          detail: 'Type, draw, checkmarks, or place today’s date',
          icon: Icons.draw_outlined,
        ),
        (
          id: 'forms',
          label: 'Fill form',
          detail: 'Use full-width controls instead of tiny PDF fields',
          icon: Icons.ballot_outlined,
        ),
        (
          id: 'pages',
          label: 'Pages',
          detail: 'Preview, reorder, rotate, duplicate, or delete',
          icon: Icons.grid_view_outlined,
        ),
        (
          id: 'text',
          label: 'Edit existing text',
          detail: 'Tap a paragraph, review, then replace',
          icon: Icons.edit_outlined,
        ),
      ],
      _ => <({String id, String label, String detail, IconData icon})>[
        (
          id: 'files',
          label: 'Create, combine & split',
          detail: 'Images to PDF, merge, extract, split',
          icon: Icons.merge_outlined,
        ),
        (
          id: 'export',
          label: 'Export & compress',
          detail: 'Convert, compare, OCR, reach a target size',
          icon: Icons.output_outlined,
        ),
        (
          id: 'secure',
          label: 'Protect & redact',
          detail: 'Mark, inspect, apply, or add passwords',
          icon: Icons.lock_outline,
        ),
      ],
    };
    final action = await _chooseSurfaceAction(
      const ['Read', 'Edit', 'Organize'][index],
      actions,
    );
    if (!mounted) return;
    switch (action) {
      case 'find':
        setState(() => _finding = true);
      case 'bookmarks':
        await _openBookmarks();
      case 'comments':
        await _openComments();
      case 'insights':
        await _openInsights();
      case 'links':
        await _openLinks();
      case 'draw':
        await _openAnnotate();
      case 'selectText':
        await _openAnnotate(initialMode: AnnotateMode.select);
      case 'highlight':
        await _highlightPhrase();
      case 'forms':
        await _openForms();
      case 'sign':
        await _openSignature();
      case 'text':
        await _openTextEdit();
      case 'pages':
        await _openPages();
      case 'files':
        await _openOrganize();
      case 'export':
        await _openExport();
      case 'secure':
        await _openSecure();
    }
  }

  Future<void> _openAgentCommand() async {
    if (_doc == null) return;
    final request = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const AgentCommandSheet(),
    );
    if (!mounted || request == null) return;
    if (request.startsWith('insights:')) {
      final query = request.substring('insights:'.length);
      await _openInsights(initialQuestion: query == 'summary' ? null : query);
      return;
    }
    final WorkflowOutcome outcome;
    switch (request) {
      case 'phones':
      case 'dates':
        outcome = await _openRecipes(initialAction: request);
      case 'compress':
      case 'compare':
      case 'export':
      case 'ocr':
        outcome = await _openExport();
      case 'combine':
        outcome = await _openOrganize();
      case 'pages':
        outcome = await _openPages();
      case 'forms':
        outcome = await _openForms();
      case 'highlight':
        outcome = await _highlightPhrase();
      case 'secure':
        outcome = await _openSecure();
      case 'sign':
        outcome = await _openSignature();
      default:
        await _explainUnsupportedRequest(request);
        return;
    }
    if (!mounted) return;
    if (outcome == WorkflowOutcome.completed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Done — ${_agentTaskLabel(request)}.')),
      );
    } else if (outcome == WorkflowOutcome.failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not complete ${_agentTaskLabel(request)}.')),
      );
    }
  }

  String _agentTaskLabel(String request) => switch (request) {
    'phones' => 'phone numbers reviewed',
    'dates' => 'dates reviewed',
    'compress' || 'export' || 'ocr' => 'export finished',
    'compare' => 'comparison finished',
    'combine' => 'files organized',
    'pages' => 'pages reviewed',
    'forms' => 'form visited',
    'highlight' => 'highlight finished',
    'secure' => 'security reviewed',
    'sign' => 'signature flow visited',
    _ => 'task finished',
  };

  Future<void> _explainUnsupportedRequest(String request) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('That task is not available yet'),
        content: Text(
          '“${request.replaceFirst('unsupported:', '')}” is not available yet. Try reviewing pages, highlighting dates, finding phone numbers to redact, filling a form, compressing to a size, comparing PDFs, or asking a question about this document.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _viewerTransform.dispose();
    _recoveryDebounce?.cancel();
    final engine = _engine;
    final doc = _doc;
    if (engine != null && doc != null) {
      unawaited(
        engine.close(handle: doc).catchError((Object error) {
          debugPrint('Could not close PDF during viewer disposal: $error');
        }),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedLineCount =
        _textSelectionAnchor == null || _textSelectionExtent == null
        ? 0
        : (math.max(_textSelectionAnchor!, _textSelectionExtent!) -
              math.min(_textSelectionAnchor!, _textSelectionExtent!) +
              1);
    return Scaffold(
      appBar: AppBar(
        title: const Text('PdfCraft Mobile'),
        actions: [
          if (_doc != null)
            IconButton(
              onPressed: _busy || _undoLabel == null ? null : _undo,
              icon: const Icon(Icons.undo),
              tooltip: _undoLabel == null
                  ? 'Nothing to undo'
                  : 'Undo $_undoLabel',
            ),
          if (_doc != null)
            IconButton(
              onPressed: _busy || _redoLabel == null ? null : _redo,
              icon: const Icon(Icons.redo),
              tooltip: _redoLabel == null
                  ? 'Nothing to redo'
                  : 'Redo $_redoLabel',
            ),
          if (_doc != null)
            IconButton(
              onPressed: _busy ? null : () => setState(() => _finding = true),
              icon: const Icon(Icons.search),
              tooltip: 'Find in document',
            ),
          if (_doc != null)
            IconButton(
              onPressed: _busy ? null : _openAgentCommand,
              icon: const Icon(Icons.auto_awesome),
              tooltip: 'Ask PdfCraft',
            ),
          if (_doc != null)
            IconButton(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.save),
              tooltip: 'Save (engine incremental save)',
            ),
          if (_doc != null)
            IconButton(
              onPressed: _busy ? null : _shareCurrentPdf,
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share a copy of this PDF',
            ),
          IconButton(
            onPressed: _busy ? null : _open,
            icon: const Icon(Icons.folder_open),
            tooltip: 'Open PDF',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          _name == null
                              ? _status
                              : documentHeading(_name!, _pageCount),
                          style: Theme.of(context).textTheme.titleSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_doc != null) ...[
                        const SizedBox(width: 8),
                        Semantics(
                          label: _dirty
                              ? 'Unsaved changes${_recoveryAvailable ? ', recovery checkpoint saved' : ''}'
                              : 'All changes saved',
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _dirty
                                  ? Theme.of(context)
                                      .colorScheme
                                      .errorContainer
                                      .withValues(alpha: 0.7)
                                  : Theme.of(context)
                                      .colorScheme
                                      .secondaryContainer
                                      .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _dirty
                                    ? Theme.of(context)
                                        .colorScheme
                                        .error
                                        .withValues(alpha: 0.4)
                                    : Theme.of(context)
                                        .colorScheme
                                        .secondary
                                        .withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _dirty
                                      ? Icons.edit_note
                                      : Icons.check_circle_outline,
                                  size: 14,
                                  color: _dirty
                                      ? Theme.of(context).colorScheme.error
                                      : Theme.of(context)
                                          .colorScheme
                                          .secondary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _dirty
                                      ? 'Unsaved${_recoveryAvailable ? ' · recovery' : ''}'
                                      : 'Saved',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: _dirty
                                            ? Theme.of(context)
                                                .colorScheme
                                                .error
                                            : Theme.of(context)
                                                .colorScheme
                                                .secondary,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_busy)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _png == null
                ? _doc == null
                      ? _emptyDocumentHome()
                      : Center(child: Text(_status))
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final sourceWidth = _imageWidthPx ?? 1;
                      final sourceHeight = _imageHeightPx ?? 1;
                      final fitScale = fitPageScale(
                        viewportWidth: constraints.maxWidth,
                        viewportHeight: constraints.maxHeight,
                        pageWidth: sourceWidth,
                        pageHeight: sourceHeight,
                      );
                      final pageWidth = sourceWidth * fitScale;
                      final pageHeight = sourceHeight * fitScale;
                      final selectionStart =
                          _textSelectionAnchor == null ||
                              _textSelectionExtent == null
                          ? null
                          : math.min(
                              _textSelectionAnchor!,
                              _textSelectionExtent!,
                            );
                      final selectionEnd =
                          _textSelectionAnchor == null ||
                              _textSelectionExtent == null
                          ? null
                          : math.max(
                              _textSelectionAnchor!,
                              _textSelectionExtent!,
                            );

                      Widget selectionHandle(int index, bool anchor) {
                        final rect = _pageTextLines[index].rect;
                        final x =
                            (anchor ? rect[0] : rect[2]) *
                            96 /
                            72 *
                            fitScale;
                        final y = rect[3] * 96 / 72 * fitScale;
                        return Positioned(
                          left: x - 24,
                          top: y - 24,
                          child: Semantics(
                            label: anchor
                                ? 'Start text selection handle, line ${index + 1}'
                                : 'End text selection handle, line ${index + 1}',
                            slider: true,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanStart: (_) {
                                _viewerLongPressSelecting = true;
                                HapticFeedback.selectionClick();
                              },
                              onPanUpdate: (details) =>
                                  _moveTextSelectionHandle(
                                    details,
                                    fitScale,
                                    anchor: anchor,
                                  ),
                              onPanEnd: (_) =>
                                  _viewerLongPressSelecting = false,
                              child: SizedBox(
                                width: 48,
                                height: 48,
                                child: Center(
                                  child: Container(
                                    width: 18,
                                    height: 18,
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Colors.black26,
                                          blurRadius: 3,
                                          offset: Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }

                      return Stack(
                        fit: StackFit.expand,
                        clipBehavior: Clip.none,
                        children: [
                          // Base layer: Interactive viewer with PDF canvas
                          Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: _onViewerPointerDown,
                            onPointerUp: _onViewerPointerUp,
                            onPointerCancel: _onViewerPointerCancel,
                            child: InteractiveViewer(
                              transformationController: _viewerTransform,
                              minScale: 1,
                              maxScale: 8,
                              clipBehavior: Clip.none,
                              child: Center(
                                child: SizedBox(
                                  width: pageWidth,
                                  height: pageHeight,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onDoubleTapDown: (details) {
                                      final currentScale =
                                          _viewerTransform.value
                                              .getMaxScaleOnAxis();
                                      if (currentScale > 1.05) {
                                        _viewerTransform.value =
                                            Matrix4.identity();
                                      } else {
                                        const targetScale = 2.0;
                                        final focal = details.localPosition;
                                        final pageOriginX =
                                            (constraints.maxWidth - pageWidth) / 2;
                                        final pageOriginY =
                                            (constraints.maxHeight - pageHeight) / 2;
                                        final screenFocalX =
                                            pageOriginX + focal.dx;
                                        final screenFocalY =
                                            pageOriginY + focal.dy;
                                        final dx = constraints.maxWidth / 2 -
                                            screenFocalX * targetScale;
                                        final dy = constraints.maxHeight / 2 -
                                            screenFocalY * targetScale;
                                        _viewerTransform.value = Matrix4.identity()
                                          ..translate(dx, dy)
                                          ..scale(targetScale);
                                      }
                                    },
                                    onDoubleTap: () {},
                                        onLongPressStart: (details) =>
                                            _beginTextSelection(
                                              details.localPosition,
                                              fitScale,
                                            ),
                                        onLongPressMoveUpdate: (details) =>
                                            _extendTextSelection(
                                              details.localPosition,
                                              fitScale,
                                            ),
                                        onLongPressEnd: (_) =>
                                            _viewerLongPressSelecting = false,
                                        child: Stack(
                                          key: _viewerPageKey,
                                          fit: StackFit.expand,
                                          children: [
                                            Semantics(
                                              image: true,
                                              label:
                                                  'Document page $_page of $_pageCount',
                                              child: Image.memory(
                                                _png!,
                                                fit: BoxFit.fill,
                                                gaplessPlayback: true,
                                              ),
                                            ),
                                            if (_finding &&
                                                _findMatches.isNotEmpty)
                                              for (
                                                var matchIdx = 0;
                                                matchIdx <
                                                    _findMatches.length;
                                                matchIdx++
                                              )
                                                if (_findMatches[matchIdx]
                                                        .page ==
                                                    _page)
                                                  for (final rect
                                                      in _findMatches[matchIdx]
                                                          .rects)
                                                    if (rect.length == 4)
                                                      Positioned(
                                                        left:
                                                            math.min(
                                                              rect[0],
                                                              rect[2],
                                                            ) *
                                                            96 /
                                                            72 *
                                                            fitScale,
                                                        top:
                                                            math.min(
                                                              rect[1],
                                                              rect[3],
                                                            ) *
                                                            96 /
                                                            72 *
                                                            fitScale,
                                                        width:
                                                            (rect[2] - rect[0])
                                                                .abs() *
                                                            96 /
                                                            72 *
                                                            fitScale,
                                                        height:
                                                            (rect[3] - rect[1])
                                                                .abs() *
                                                            96 /
                                                            72 *
                                                            fitScale,
                                                        child: IgnorePointer(
                                                          child: DecoratedBox(
                                                            decoration:
                                                                BoxDecoration(
                                                              color:
                                                                  matchIdx ==
                                                                      _findActiveIndex
                                                                  ? const Color(
                                                                      0xFFFF9800,
                                                                    ).withValues(
                                                                      alpha:
                                                                          0.50,
                                                                    )
                                                                  : Colors
                                                                      .yellow
                                                                      .withValues(
                                                                        alpha:
                                                                            0.35,
                                                                      ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    2,
                                                                  ),
                                                              border: Border.all(
                                                                color:
                                                                    matchIdx ==
                                                                        _findActiveIndex
                                                                    ? Colors
                                                                        .deepOrange
                                                                    : const Color(
                                                                        0xFFC79100,
                                                                      ),
                                                                width:
                                                                    matchIdx ==
                                                                        _findActiveIndex
                                                                    ? 2.0
                                                                    : 1.0,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                            if (selectionStart != null &&
                                                selectionEnd != null)
                                              for (
                                                var line = selectionStart;
                                                line <= selectionEnd;
                                                line++
                                              )
                                                if (_pageTextLines[line]
                                                        .rect
                                                        .length ==
                                                    4)
                                                  Positioned(
                                                    left:
                                                        _pageTextLines[line]
                                                            .rect[0] *
                                                        96 /
                                                        72 *
                                                        fitScale,
                                                    top:
                                                        _pageTextLines[line]
                                                            .rect[1] *
                                                        96 /
                                                        72 *
                                                        fitScale,
                                                    width:
                                                        (_pageTextLines[line]
                                                                .rect[2] -
                                                            _pageTextLines[line]
                                                                .rect[0]) *
                                                        96 /
                                                        72 *
                                                        fitScale,
                                                    height:
                                                        (_pageTextLines[line]
                                                                .rect[3] -
                                                            _pageTextLines[line]
                                                                .rect[1]) *
                                                        96 /
                                                        72 *
                                                        fitScale,
                                                    child: IgnorePointer(
                                                      child: DecoratedBox(
                                                        decoration: BoxDecoration(
                                                          color:
                                                              _textSelectionKind ==
                                                                  'highlight'
                                                              ? _selectionColorForName(
                                                                  _textSelectionColor,
                                                                ).withValues(
                                                                  alpha: 0.38,
                                                                )
                                                              : Colors.blue
                                                                    .withValues(
                                                                      alpha:
                                                                          0.10,
                                                                    ),
                                                          border: Border.all(
                                                            color:
                                                                _textSelectionKind ==
                                                                    'highlight'
                                                                ? (_textSelectionColor ==
                                                                        'yellow'
                                                                    ? const Color(
                                                                        0xFFC79100,
                                                                      )
                                                                    : _selectionColorForName(
                                                                        _textSelectionColor,
                                                                      ))
                                                                : Colors.blue,
                                                            width: 1.5,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                            if (selectionStart != null &&
                                                selectionEnd != null) ...[
                                              selectionHandle(
                                                selectionStart,
                                                true,
                                              ),
                                              selectionHandle(
                                                selectionEnd,
                                                false,
                                              ),
                                            ],
                                            for (final marker in _markers)
                                              Positioned(
                                                left: marker.x * fitScale - 24,
                                                top: marker.y * fitScale - 24,
                                                child: Semantics(
                                                  button: true,
                                                  label:
                                                      '${marker.label} on page $_page. Double tap to view comments.',
                                                  child: GestureDetector(
                                                    behavior:
                                                        HitTestBehavior.opaque,
                                                    onTap: () => _openComments(
                                                      page: _page,
                                                      focusIndex: marker.index,
                                                    ),
                                                    child: SizedBox(
                                                      width: 48,
                                                      height: 48,
                                                      child: Center(
                                                        child: Tooltip(
                                                          message: marker.label,
                                                          child: Container(
                                                            width: 32,
                                                            height: 32,
                                                            decoration: BoxDecoration(
                                                              color: Theme.of(context)
                                                                  .colorScheme
                                                                  .primaryContainer,
                                                              shape:
                                                                  BoxShape.circle,
                                                              border: Border.all(
                                                                color:
                                                                    Theme.of(
                                                                          context,
                                                                        )
                                                                        .colorScheme
                                                                        .primary,
                                                              ),
                                                            ),
                                                            child: Icon(
                                                              Icons.comment,
                                                              size: 17,
                                                              color:
                                                                  Theme.of(
                                                                        context,
                                                                      )
                                                                      .colorScheme
                                                                      .primary,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                          // Floating Overlay: Accessible single-pointer zoom HUD
                          Positioned(
                            left: 16,
                            bottom: 16,
                            child: ZoomControlsHud(
                              transformController: _viewerTransform,
                              minScale: 1,
                              maxScale: 8,
                              viewportSize: Size(
                                constraints.maxWidth,
                                constraints.maxHeight,
                              ),
                            ),
                          ),

                          // Floating Overlay: Find Bar HUD
                          if (_finding && _doc != null)
                            Positioned(
                              top: 12,
                              left: 16,
                              right: 16,
                              child: FindBar(
                                engine: _engine!,
                                handle: _doc!,
                                onJumpToPage: _goto,
                                onMatchesChanged: (matches) =>
                                    setState(() => _findMatches = matches),
                                onActiveIndexChanged: (index) =>
                                    setState(() => _findActiveIndex = index),
                                onClose: () => setState(() {
                                  _finding = false;
                                  _findMatches = const [];
                                  _findActiveIndex = -1;
                                }),
                              ),
                            ),

                          // Floating Overlay: Text selection styling deck
                          if (_textSelectionAnchor != null &&
                              _textSelectionExtent != null)
                            Positioned(
                              left: 16,
                              right: 16,
                              bottom: 16,
                              child: Material(
                                elevation: 6,
                                shadowColor: Colors.black26,
                                borderRadius: BorderRadius.circular(16),
                                color: Theme.of(context)
                                    .colorScheme
                                    .surface
                                    .withValues(alpha: 0.96),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    8,
                                    14,
                                    10,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '$selectedLineCount ${selectedLineCount == 1 ? 'line' : 'lines'} selected',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Copy selected text',
                                            onPressed: _copyTextSelection,
                                            icon: const Icon(Icons.copy_outlined),
                                          ),
                                          IconButton(
                                            tooltip: 'Clear selection',
                                            onPressed: () => setState(() {
                                              _textSelectionAnchor = null;
                                              _textSelectionExtent = null;
                                            }),
                                            icon: const Icon(Icons.close),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      SegmentedButton<String>(
                                        segments: const [
                                          ButtonSegment(
                                            value: 'highlight',
                                            label: Text('Highlight'),
                                          ),
                                          ButtonSegment(
                                            value: 'underline',
                                            label: Text('Underline'),
                                          ),
                                          ButtonSegment(
                                            value: 'strikeout',
                                            label: Text('Strike'),
                                          ),
                                        ],
                                        selected: {_textSelectionKind},
                                        onSelectionChanged: (values) =>
                                            setState(
                                              () =>
                                                  _textSelectionKind =
                                                      values.first,
                                            ),
                                      ),
                                      if (_textSelectionKind == 'highlight') ...[
                                        const SizedBox(height: 6),
                                        Wrap(
                                          alignment: WrapAlignment.center,
                                          spacing: 6,
                                          children: [
                                            for (final color in const [
                                              'yellow',
                                              'green',
                                              'blue',
                                              'red',
                                            ])
                                              ChoiceChip(
                                                avatar: CircleAvatar(
                                                  radius: 8,
                                                  backgroundColor:
                                                      _selectionColorForName(
                                                        color,
                                                      ),
                                                ),
                                                label: Text(
                                                  color[0].toUpperCase() +
                                                      color.substring(1),
                                                ),
                                                selected:
                                                    _textSelectionColor ==
                                                    color,
                                                onSelected: (_) => setState(
                                                  () =>
                                                      _textSelectionColor =
                                                          color,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                      const SizedBox(height: 8),
                                      SizedBox(
                                        width: double.infinity,
                                        child: FilledButton(
                                          onPressed: _busy
                                              ? null
                                              : _applyTextSelection,
                                          child: Text(
                                            'Apply ${_textSelectionKind == 'strikeout' ? 'strikeout' : _textSelectionKind}',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          if (_doc != null)
            NavigationBar(
              height: 68,
              selectedIndex: _activeSurface,
              onDestinationSelected: _openSurface,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.chrome_reader_mode_outlined),
                  label: 'Read',
                ),
                NavigationDestination(
                  icon: Icon(Icons.edit_outlined),
                  label: 'Edit',
                ),
                NavigationDestination(
                  icon: Icon(Icons.folder_copy_outlined),
                  label: 'Organize',
                ),
                NavigationDestination(
                  icon: Icon(Icons.auto_awesome_outlined),
                  label: 'Agent',
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _status,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_doc != null)
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Previous page',
                        onPressed: _busy || _page <= 1
                            ? null
                            : () => _goto(_page - 1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Semantics(
                        button: true,
                        hint: 'Double tap to enter page number',
                        child: TextButton(
                          onPressed: _busy ? null : _goToPagePrompt,
                          child: Text('$_page / $_pageCount'),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next page',
                        onPressed: _busy || _page >= _pageCount
                            ? null
                            : () => _goto(_page + 1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _newBlankPdf() async {
    final engine = _engine;
    if (engine == null || _busy) return;
    final controller = TextEditingController(text: '1');
    int? pages;
    try {
      final text = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('New blank PDF'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Pages (1–100)',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Create'),
            ),
          ],
        ),
      );
      if (text == null || !mounted) return;
      pages = int.tryParse(text.trim());
      if (pages == null || pages < 1 || pages > 100) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Enter 1 to 100 pages.')));
        return;
      }
    } finally {
      controller.dispose();
    }
    setState(() => _busy = true);
    try {
      final response = await engine.executeTool(
        handle: 0,
        tool: 'doc_create',
        argumentsJson: jsonEncode({
          'from': 'blank',
          'pages': pages,
          'out': 'outputs/blank.pdf',
        }),
      );
      if (!mounted) return;
      await saveToolOutputs(context, engine, [
        for (final c in response.contents) c.json,
      ]);
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Could not create a blank PDF: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _emptyDocumentHome() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.picture_as_pdf_outlined,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(_status, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            if (_recentDocuments.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Recent Documents',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _recentDocuments.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = _recentDocuments[index];
                    return Semantics(
                      button: true,
                      label:
                          'Open recent document ${item.name}, ${item.pageCount} pages',
                      child: ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .primaryContainer,
                          child: Icon(
                            Icons.description_outlined,
                            size: 18,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                        ),
                        title: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text(
                          '${item.pageCount} ${item.pageCount == 1 ? "page" : "pages"}${item.byteLength != null && item.byteLength! > 0 ? " • ${(item.byteLength! / 1024).toStringAsFixed(0)} KB" : ""}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        trailing: Semantics(
                          button: true,
                          label: 'Remove ${item.name} from recents',
                          child: IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            tooltip: 'Remove from recents',
                            onPressed: () async {
                              await _recentStore.removeRecent(item.name);
                              await _loadRecents();
                            },
                          ),
                        ),
                        onTap: _busy || _engine == null
                            ? null
                            : () => _openRecent(item),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy || _engine == null ? null : _open,
                icon: const Icon(Icons.folder_open),
                label: const Text('Open a PDF'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy || _engine == null ? null : _openOrganize,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Create PDF from photos'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy || _engine == null ? null : _newBlankPdf,
                icon: const Icon(Icons.note_add_outlined),
                label: const Text('Start a blank PDF'),
              ),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: _busy || _engine == null ? null : _openOrganize,
              icon: const Icon(Icons.merge_outlined),
              label: const Text('Combine PDF files'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A tappable comment marker, positioned in render pixels over the page
/// image so it scales together with the page inside the viewer.
class _Marker {
  const _Marker({
    required this.x,
    required this.y,
    required this.label,
    required this.index,
  });

  final double x;
  final double y;
  final String label;
  final int index;
}

String _commentMarkerLabel(String type) => switch (type.toLowerCase()) {
  'text' => 'Note',
  'freetext' || 'typewriter' => 'Text box',
  'strikeout' || 'strike_out' => 'Strikethrough',
  'square' || 'rectangle' => 'Rectangle',
  _ => '${type[0].toUpperCase()}${type.substring(1).toLowerCase()}',
};
