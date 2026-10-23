import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';

import 'widgets/app_notice.dart';

import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';

import 'bridge/api.dart' as bridge;
import 'services/pdf_engine.dart';
import 'services/theme_preference.dart';
import 'services/view_preference.dart';
import 'services/signature_store.dart';
import 'services/recent_documents_store.dart';
import 'widgets/annotate_page.dart';
import 'widgets/agent_command_sheet.dart';
import 'widgets/annotation_geometry.dart' as annotation_geo;
import 'widgets/bookmarks_screen.dart';
import 'widgets/comments_screen.dart';
import 'widgets/task_catalog.dart';
import 'widgets/document_insights_sheet.dart';
import 'widgets/export_sheet.dart';
import 'widgets/links_screen.dart';
import 'widgets/find_bar.dart';
import 'widgets/form_screen.dart';
import 'widgets/organize_sheet.dart';
import 'widgets/page_grid.dart';
import 'widgets/page_viewport.dart';
import 'widgets/touch_session.dart';
import 'widgets/quick_mark_page.dart';
import 'widgets/recipes_sheet.dart';
import 'widgets/secure_sheet.dart';
import 'widgets/signature_pad.dart';
import 'widgets/signature_placement_page.dart';
import 'services/app_diagnostics.dart';
import 'services/page_cache.dart';
import 'services/feature_flags.dart';
import 'services/telemetry_sink.dart';
import 'services/review_prompt.dart';
import 'widgets/diagnostics_sheet.dart';
import 'widgets/signature_sheet.dart';
import 'widgets/text_edit_sheet.dart';
import 'widgets/output_saver.dart';
import 'widgets/reader_controls.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppDiagnostics.installGlobalErrorHandlers();
  await FeatureFlagService.instance.initialize();
  runApp(const OverlineApp());
}

typedef PdfCraftApp = OverlineApp;

class OverlineApp extends StatefulWidget {
  const OverlineApp({
    super.key,
    this.engineFactory = createPdfCraftEngine,
    this.initialDocumentBytes,
    this.initialDocumentName,
  });

  final PdfEngineFactory engineFactory;
  final Uint8List? initialDocumentBytes;
  final String? initialDocumentName;

  @override
  State<OverlineApp> createState() => _OverlineAppState();
}

class _OverlineAppState extends State<OverlineApp> {
  ThemePreferenceController? _theme;
  ReadingPreferenceController? _reading;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPreferences());
  }

  Future<void> _loadPreferences() async {
    final theme = await ThemePreferenceController.load();
    final reading = await ReadingPreferenceController.load();
    if (!mounted) return;
    setState(() {
      _theme = theme;
      _reading = reading;
    });
  }

  static ThemeData _themeData(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFB42332),
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: brightness == Brightness.dark
          ? colorScheme.surface
          : const Color(0xFFFAFBFC),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        scrolledUnderElevation: 0,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      useMaterial3: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _theme;
    return ReadingModeScope(
      controller: _reading,
      child: PdfCraftThemeScope(
        controller: controller,
        child: MaterialApp(
          title: 'Overline',
          navigatorObservers: [NoticeNavigatorObserver()],
          debugShowCheckedModeBanner: false,
          theme: _themeData(Brightness.light),
          darkTheme: _themeData(Brightness.dark),
          themeMode: controller?.mode ?? ThemeMode.system,
          home: ViewerPage(
            engineFactory: widget.engineFactory,
            initialDocumentBytes: widget.initialDocumentBytes,
            initialDocumentName: widget.initialDocumentName,
          ),
        ),
      ),
    );
  }
}

class PdfCraftThemeScope extends InheritedNotifier<ThemePreferenceController> {
  const PdfCraftThemeScope({
    super.key,
    required ThemePreferenceController? controller,
    required super.child,
  }) : super(notifier: controller);

  static PdfCraftThemeScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<PdfCraftThemeScope>();
  }
}

class ReadingModeScope extends InheritedNotifier<ReadingPreferenceController> {
  const ReadingModeScope({
    super.key,
    required ReadingPreferenceController? controller,
    required super.child,
  }) : super(notifier: controller);

  static ReadingModeScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ReadingModeScope>();
  }
}

enum WorkflowOutcome { completed, cancelled, failed, needsInput }

class ViewerPage extends StatefulWidget {
  const ViewerPage({
    super.key,
    required this.engineFactory,
    this.initialDocumentBytes,
    this.initialDocumentName,
  });

  final PdfEngineFactory engineFactory;
  final Uint8List? initialDocumentBytes;
  final String? initialDocumentName;

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

enum DocumentInteractionMode { read, markup, sign }

class _ViewerPageState extends State<ViewerPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
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
  bool _launchingTask = false;
  Offset? _doubleTapPosition;
  bool _swipeStartedAtFit = false;
  final TransformationController _viewerTransform = TransformationController();
  AnimationController? _zoomAnimationController;
  final GlobalKey _viewerPageKey = GlobalKey();
  final GlobalKey _readerViewportKey = GlobalKey();
  final ScrollController _continuousScroll = ScrollController();
  double _continuousExtent = 1;
  int _viewerPointerCount = 0;
  final _viewerTouch = TouchSession();
  ReadingMode _readingMode = ReadingMode.single;
  bool _invertDocumentColors = false;

  void _animateViewerTransform(Matrix4 target) {
    HapticFeedback.lightImpact();
    _zoomAnimationController?.stop();
    _zoomAnimationController?.dispose();
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _zoomAnimationController = controller;
    final start = _viewerTransform.value;
    final animation = Matrix4Tween(
      begin: start,
      end: target,
    ).animate(CurvedAnimation(parent: controller, curve: Curves.easeOutCubic));
    animation.addListener(() {
      _viewerTransform.value = animation.value;
    });
    controller.forward();
  }

  final BoundedPageCache _horizontalPageImages = BoundedPageCache(
    maxCapacity: 10,
  );
  ReadingPreferenceController? _readingPreference;
  Uint8List? _secondPng;
  double? _secondImageWidthPx;
  double? _secondImageHeightPx;
  final BoundedPageCache _verticalPageImages = BoundedPageCache(
    maxCapacity: 10,
  );
  Offset? _viewerSwipeStart;
  bool _viewerLongPressSelecting = false;
  Timer? _recoveryDebounce;
  Future<void> _recoveryWrites = Future<void>.value();

  // Unified Canvas & UX state
  DocumentInteractionMode _canvasMode = DocumentInteractionMode.read;
  bool _showChrome = true;

  // In-canvas markup state
  final List<annotation_geo.InkStroke> _canvasStrokes = [];
  List<Offset> _activeStroke = [];
  String _markupTool = 'pen'; // 'pen', 'highlighter', 'eraser'
  String _markupColor = 'yellow';
  double _markupWidth = 4.0;

  // In-canvas signature state
  Offset? _draftSignaturePositionPx;
  double _draftSignatureWidthPx = 160.0;
  double _draftSignatureHeightPx = 60.0;
  String? _activeSignatureTyped;
  Uint8List? _activeSignatureImage;
  bool _activeSignatureIsDate = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initEngine();
    _loadRecents();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = ReadingModeScope.maybeOf(context)?.notifier;
    if (controller != _readingPreference) {
      _readingPreference = controller;
    }
    final mode = controller?.mode;
    if (mode != null && mode != _readingMode) {
      _readingMode = mode;
    }
    final invert = controller?.invertDocumentColors ?? false;
    if (invert != _invertDocumentColors) {
      _invertDocumentColors = invert;
    }
  }

  Future<void> _setReadingMode(ReadingMode mode) async {
    if (_readingMode == mode) return;
    _zoomAnimationController?.stop();
    setState(() {
      _readingMode = mode;
      _textSelectionAnchor = null;
      _textSelectionExtent = null;
      _viewerTransform.value = Matrix4.identity();
      _secondPng = null;
      _secondImageWidthPx = null;
      _secondImageHeightPx = null;
    });
    await _readingPreference?.setMode(mode);
    if (!mounted) return;
    await _render();
  }

  Future<void> _setInvertedColors(bool value) async {
    setState(() => _invertDocumentColors = value);
    await _readingPreference?.setInverted(value);
  }

  void _reportError(String message, Object error) {
    ReviewPromptManager.instance.markSessionError();
    TelemetryManager.instance.captureException(error, null, reason: message);
    AppDiagnostics.instance.recordError(
      error,
      null,
      category: 'viewer',
      message: message,
    );
    if (!mounted) return;
    setState(() => _status = message);
    AppNotice.show(
      context,
      AppNotice(message: message, kind: NoticeKind.error, details: '$error'),
    );
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
        _status = 'Engine ready (Overline Rust core)';
      });
      unawaited(_offerRecovery(engine));
      _setupNativeChannels();
      if (widget.initialDocumentBytes != null) {
        await _openDocumentBytes(
          widget.initialDocumentName ?? 'Document.pdf',
          widget.initialDocumentBytes!,
        );
      }
    } catch (e) {
      if (!mounted) return;
      _reportError('Engine init failed.', e);
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

    channel
        .invokeMethod<Map<Object?, Object?>>('getInitialPdf')
        .then((pdf) {
          if (pdf != null) {
            final name = pdf['name'] as String?;
            final path = pdf['path'] as String?;
            if (name != null && path != null) {
              _openIncomingPdf(name, path);
            }
          }
        })
        .catchError((_) {});
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
    AppNotice.dismiss(context);
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
      unawaited(_clearRecoveryCheckpoint());
      if (previousDoc != null) {
        try {
          await engine.close(handle: previousDoc);
        } catch (error) {
          debugPrint('Could not close previous PDF document: $error');
        }
      }
      _verticalPageImages.clear();
      _horizontalPageImages.clear();
      await _render();
      unawaited(
        _recentStore
            .recordOpened(name: name, pageCount: count, bytes: bytes)
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
      _reportError('Open failed.', e);
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
      _reportError('Open failed.', e);
    }
  }

  Future<void> _openRecent(RecentDocumentEntry entry) async {
    if (_busy || entry.cachedFilePath == null) return;
    final file = File(entry.cachedFilePath!);
    if (!await file.exists()) {
      await _recentStore.removeRecent(entry.name);
      await _loadRecents();
      if (mounted) {
        AppNotice.show(
          context,
          const AppNotice(
            message: 'File is no longer available.',
            kind: NoticeKind.warning,
          ),
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
        content: const Text('Save this PDF before leaving the document?'),
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

    if (_readingMode == ReadingMode.vertical ||
        _readingMode == ReadingMode.horizontalContinuous) {
      setState(() {
        _busy = true;
        _status = 'Rendering pages…';
      });
      if (!mounted) return;
      setState(() {
        _busy = false;
        _png = null;
        _secondPng = null;
        _secondImageWidthPx = null;
        _secondImageHeightPx = null;
        _status = 'Ready';
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _continuousScroll.hasClients) {
          _continuousScroll.jumpTo(
            ((_page - 1) * _continuousExtent).clamp(
              0,
              _continuousScroll.position.maxScrollExtent,
            ),
          );
        }
      });
      return;
    }

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
      Uint8List? secondPng;
      bridge.PageSize? secondPageSize;
      if (_readingMode == ReadingMode.doublePage && page < _pageCount) {
        secondPng = await engine.renderPagePng(
          handle: doc,
          page1Based: page + 1,
          dpi: 96,
        );
        secondPageSize = await engine.pageSize(
          handle: doc,
          page1Based: page + 1,
        );
      }
      if (!mounted || _doc != doc || _page != page) return;
      setState(() {
        _png = png;
        _imageWidthPx = pageSize.width * 96 / 72;
        _imageHeightPx = pageSize.height * 96 / 72;
        _secondPng = secondPng;
        _secondImageWidthPx = secondPageSize == null
            ? null
            : secondPageSize.width * 96 / 72;
        _secondImageHeightPx = secondPageSize == null
            ? null
            : secondPageSize.height * 96 / 72;
        _markers = const [];
        _pageTextLines = const [];
        _pageTextLoading = true;
        _status = 'Ready';
      });
      await _refreshMarkers(engine, doc, page, pageSize: pageSize);
    } catch (e) {
      if (!mounted) return;
      _reportError('Render failed.', e);
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

  Widget _verticalPageList() => _continuousPageList(Axis.vertical);
  Widget _horizontalPageList() => _continuousPageList(Axis.horizontal);

  Widget _continuousPageList(Axis axis) {
    final doc = _doc;
    final engine = _engine;
    if (doc == null || engine == null) return Center(child: Text(_status));
    return LayoutBuilder(
      builder: (context, constraints) {
        _continuousExtent = axis == Axis.vertical
            ? constraints.maxHeight
            : constraints.maxWidth;
        final isZoomed = _viewerTransform.value.getMaxScaleOnAxis() > 1.05;
        return Listener(
          onPointerDown: (e) {
            _zoomAnimationController?.stop();
            _viewerTouch.down(e.pointer);
          },
          onPointerUp: (e) => _viewerTouch.up(e.pointer),
          onPointerCancel: (e) => _viewerTouch.cancel(e.pointer),
          child: InteractiveViewer(
            key: _readerViewportKey,
            transformationController: _viewerTransform,
            minScale: 1,
            maxScale: 8,
            panEnabled: isZoomed,
            scaleEnabled: true,
            onInteractionStart: (_) => _zoomAnimationController?.stop(),
            child: NotificationListener<ScrollEndNotification>(
              onNotification: (_) {
                if (_continuousScroll.hasClients) {
                  final page =
                      (_continuousScroll.offset / _continuousExtent).round() +
                      1;
                  if (page != _page && page >= 1 && page <= _pageCount) {
                    setState(() => _page = page);
                  }
                }
                return false;
              },
              child: ListView.builder(
                controller: _continuousScroll,
                physics: isZoomed
                    ? const NeverScrollableScrollPhysics()
                    : const ClampingScrollPhysics(),
                scrollDirection: axis,
                itemExtent: _continuousExtent,
                itemCount: _pageCount,
                itemBuilder: (context, index) {
                  final page = index + 1;
                  final future = _verticalPageImages.putIfAbsent(
                    page,
                    () => engine.renderPagePng(
                      handle: doc,
                      page1Based: page,
                      dpi: 96,
                    ),
                  );
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Text('Page $page'),
                        const SizedBox(height: 8),
                        Expanded(
                          child: FutureBuilder<Uint8List>(
                            future: future,
                            builder: (context, snapshot) {
                              if (snapshot.hasError) {
                                return Center(
                                  child: Text('Could not render page $page.'),
                                );
                              }
                              if (!snapshot.hasData) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }
                              return LayoutBuilder(
                                builder: (context, imageConstraints) =>
                                    SizedBox.expand(
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onLongPressStart: (details) =>
                                            _offerPageTextSelection(
                                              page,
                                              details.localPosition,
                                              Size(
                                                imageConstraints.maxWidth,
                                                imageConstraints.maxHeight,
                                              ),
                                            ),
                                        child: _documentImage(
                                          snapshot.data!,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _documentImage(
    Uint8List bytes, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.fill,
  }) {
    Widget image = _invertDocumentColors
        ? Image.memory(
            bytes,
            fit: fit,
            gaplessPlayback: true,
            color: Colors.white,
          )
        : Image.memory(bytes, fit: fit, gaplessPlayback: true);
    if (_invertDocumentColors) {
      image = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          -1,
          0,
          0,
          0,
          255,
          0,
          -1,
          0,
          0,
          255,
          0,
          0,
          -1,
          0,
          255,
          0,
          0,
          0,
          1,
          0,
        ]),
        child: image,
      );
    }
    if (width != null || height != null) {
      image = SizedBox(width: width, height: height, child: image);
    }
    return image;
  }

  Future<void> _goto(int page) async {
    if (_busy) return;
    if (page < 1 || page > _pageCount || page == _page) return;
    _zoomAnimationController?.stop();
    _page = page;
    _textSelectionAnchor = null;
    _textSelectionExtent = null;
    _viewerTransform.value = Matrix4.identity();
    await _render();
  }

  void _onViewerPointerDown(PointerDownEvent event) {
    _zoomAnimationController?.stop();
    _viewerTouch.down(event.pointer);
    _viewerPointerCount++;
    if (_viewerPointerCount == 1) {
      _viewerLongPressSelecting = false;
      _swipeStartedAtFit = _viewerTransform.value.getMaxScaleOnAxis() <= 1.05;
    } else {
      _swipeStartedAtFit = false;
    }
    _viewerSwipeStart = _viewerPointerCount == 1 ? event.position : null;
  }

  void _onViewerPointerUp(PointerEvent event) {
    _viewerTouch.up(event.pointer);
    _viewerPointerCount = math.max(0, _viewerPointerCount - 1);
    if (_viewerPointerCount > 0) return;
    final start = _viewerSwipeStart;
    _viewerSwipeStart = null;
    if (start == null ||
        !_swipeStartedAtFit ||
        _busy ||
        _doc == null ||
        _viewerLongPressSelecting ||
        _textSelectionAnchor != null) {
      _viewerLongPressSelecting = false;
      return;
    }
    final delta = event.position - start;
    final swipe = pageForSwipe(
      delta,
      currentPage: _page,
      pageCount: _pageCount,
      scale: _viewerTransform.value.getMaxScaleOnAxis(),
    );
    if (swipe == null) return;
    if (_readingMode == ReadingMode.doublePage && _swipeStartedAtFit) {
      final step = delta.dx < 0 ? 2 : -2;
      final destination = (_page + step).clamp(1, _pageCount);
      if (destination != _page) {
        HapticFeedback.selectionClick();
        unawaited(_goto(destination));
      }
      return;
    }
    final destination = pageForSwipe(
      delta,
      currentPage: _page,
      pageCount: _pageCount,
      scale: _viewerTransform.value.getMaxScaleOnAxis(),
    );
    if (destination != null) {
      HapticFeedback.selectionClick();
      unawaited(_goto(destination));
    }
  }

  Future<void> _offerPageTextSelection(
    int page,
    Offset local,
    Size viewport,
  ) async {
    final engine = _engine;
    final doc = _doc;
    if (engine == null || doc == null || _busy || !_viewerTouch.canEdit) return;
    try {
      final size = await engine.pageSize(handle: doc, page1Based: page);
      final width = size.width * 96 / 72;
      final height = size.height * 96 / 72;
      final fit = fitPageScale(
        viewportWidth: viewport.width,
        viewportHeight: viewport.height,
        pageWidth: width,
        pageHeight: height,
      );
      final point =
          (local -
              Offset(
                (viewport.width - width * fit) / 2,
                (viewport.height - height * fit) / 2,
              )) /
          fit;
      if (!mounted ||
          _doc != doc ||
          !_viewerTouch.canEdit ||
          point.dx < 0 ||
          point.dy < 0 ||
          point.dx > width ||
          point.dy > height) {
        return;
      }
      AppNotice.show(
        context,
        AppNotice(
          message: 'Select text on page $page in single-page view.',
          action: NoticeAction(
            label: 'Select text',
            onPressed: () async {
              if (!mounted || _busy || _doc != doc) return;
              _zoomAnimationController?.stop();
              setState(() {
                _page = page;
                _readingMode = ReadingMode.single;
                _showChrome = true;
                _textSelectionAnchor = null;
                _textSelectionExtent = null;
                _viewerTransform.value = Matrix4.identity();
              });
              await _readingPreference?.setMode(ReadingMode.single);
              if (!mounted) return;
              await _render();
              if (mounted && !_busy && _page == page) {
                _beginTextSelection(point, 1);
              }
            },
          ),
        ),
      );
    } catch (e) {
      if (mounted) _reportError('Could not prepare text selection.', e);
    }
  }

  void _beginTextSelection(Offset pageLocalPosition, double fitScale) {
    if (_busy || !_viewerTouch.canEdit || _viewerPointerCount > 1) return;
    _viewerLongPressSelecting = true;
    if (_pageTextLoading) {
      AppNotice.show(
        context,
        const AppNotice(
          message: 'Getting this page’s text ready…',
          kind: NoticeKind.info,
        ),
      );
      return;
    }
    if (_pageTextLines.isEmpty) {
      AppNotice.show(
        context,
        const AppNotice(
          message: 'This page has no selectable text.',
          kind: NoticeKind.warning,
        ),
      );
      return;
    }
    final x = annotation_geo.pxToPt(pageLocalPosition.dx / fitScale, 96);
    final y = annotation_geo.pxToPt(pageLocalPosition.dy / fitScale, 96);
    final line = _nearestTextLine(
      x,
      y,
      maxDistance:
          18 /
          (fitScale * 96 / 72 * _viewerTransform.value.getMaxScaleOnAxis()),
    );
    if (line == null) return;
    setState(() {
      _textSelectionAnchor = line;
      _textSelectionExtent = line;
    });
  }

  void _extendTextSelection(Offset pageLocalPosition, double fitScale) {
    if (!_viewerTouch.canEdit || _textSelectionAnchor == null) return;
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

  int? _nearestTextLine(double x, double y, {double maxDistance = 64}) {
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
    return bestIndex >= 0 && bestDistance <= maxDistance * maxDistance
        ? bestIndex
        : null;
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
      AppNotice.show(
        context,
        const AppNotice(
          message: 'These lines hold no copyable text.',
          kind: NoticeKind.warning,
        ),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    AppNotice.show(
      context,
      const AppNotice(
        message: 'Selected text copied.',
        kind: NoticeKind.success,
      ),
    );
  }

  Future<void> _applyTextSelection({String? kind, String? color}) async {
    if (kind != null) _textSelectionKind = kind;
    if (color != null) _textSelectionColor = color;
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
      final kindLabel = switch (_textSelectionKind) {
        'highlight' => 'Highlighted',
        'underline' => 'Underlined',
        'strikeout' => 'Struck out',
        _ => 'Marked',
      };
      AppNotice.show(
        context,
        AppNotice(
          message:
              '$kindLabel ${quads.length} selected line${quads.length == 1 ? '' : 's'}.',
          kind: NoticeKind.info,
          action: NoticeAction(label: 'Undo', onPressed: _undo),
        ),
      );
    } catch (error) {
      if (mounted) {
        _reportError('Could not mark selected text.', error);
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
    _viewerTouch.cancel(event.pointer);
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
        unawaited(
          ReviewPromptManager.instance.recordMilestone('save_document'),
        );
        TelemetryManager.instance.track('save_document_success', {
          'name': safeName,
          'pages': _pageCount,
        });
        if (!mounted) return;
        setState(() {
          _dirty = status.dirty;
          _recoveredUnsaved = false;
          _recoveryAvailable = false;
          _status = 'Saved $safeName through Files';
        });
        AppNotice.show(
          context,
          AppNotice(
            message: 'Saved $safeName through Files',
            kind: NoticeKind.success,
          ),
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
      _reportError(
        externalSaved
            ? 'Your file was saved, but the editing session could not confirm it. Keep the saved copy.'
            : 'Could not save the PDF. Your changes are still open.',
        e,
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
          text: 'Shared from Overline',
        ),
      );
      if (mounted) setState(() => _status = 'Share sheet opened');
    } catch (error) {
      if (mounted) _reportError('Share failed.', error);
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

  Future<void> _print() async {
    final doc = _doc;
    final engine = _engine;
    final currentName = _name;
    if (doc == null || engine == null || currentName == null || _busy) return;
    bridge.SaveSnapshot? snapshot;
    setState(() {
      _busy = true;
      _status = 'Preparing PDF to print\u2026';
    });
    try {
      _recoveryDebounce?.cancel();
      await _recoveryWrites;
      snapshot = await engine.saveSnapshot(handle: doc);
      final baseName = currentName.replaceAll(RegExp(r'[/\\]'), '_');
      final fileName = baseName.toLowerCase().endsWith('.pdf')
          ? baseName
          : '$baseName.pdf';
      await Printing.layoutPdf(
        onLayout: (format) async => snapshot!.bytes,
        name: fileName,
      );
      if (!mounted) return;
      setState(() => _status = 'Print sheet opened');
    } catch (error) {
      if (mounted) _reportError('Print failed.', error);
    } finally {
      if (snapshot != null) {
        try {
          await engine.cancelSave(handle: doc, token: snapshot.token);
        } catch (error) {
          debugPrint('Could not release printed PDF snapshot: $error');
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

  void _showAboutAndLicenses(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Overline',
      applicationVersion: '1.0.0',
      applicationIcon: Image.asset(
        'assets/icon/app_logo.png',
        width: 48,
        height: 48,
      ),
      applicationLegalese:
          '© 2026 Overline Contributors.\n\n'
          'Engine powered by PdfCraft (MIT / Apache-2.0, © ArtCraft Team and contributors).\n'
          'Bundles Hayro (Apache-2.0 / MIT), Foxit Type 1 fonts (BSD-3-Clause), '
          'Adobe CMap (BSD-3-Clause), and SIL OFL typefaces.',
    );
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
            'Overline recovered an automatic copy of $originalName. Restore it now?',
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
        _reportError('Could not restore recovery copy.', error);
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

  @override
  void didHaveMemoryPressure() {
    super.didHaveMemoryPressure();
    AppDiagnostics.instance.notifyMemoryPressure();
    _verticalPageImages.clear();
    _horizontalPageImages.clear();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  void _onOperationStatus(bridge.DocumentStatus status) {
    if (!mounted) return;
    TelemetryManager.instance.track('operation_status', {
      'pages': status.pageCount,
      'dirty': status.dirty,
      'canUndo': status.canUndo.isNotEmpty,
    });
    AppNotice.dismissAction(context);
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
      _reportError('Undo failed.', e);
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
      AppNotice.show(
        context,
        AppNotice(
          message: 'Undid $undone change${undone == 1 ? '' : 's'}.',
          kind: NoticeKind.success,
        ),
      );
    } catch (error) {
      if (mounted) {
        _reportError('Undo failed.', error);
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
      _reportError('Redo failed.', e);
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
      _reportError('Annotate failed.', e);
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
        AppNotice.show(
          context,
          const AppNotice(
            message: 'Enter the words you want to highlight.',
            kind: NoticeKind.warning,
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
            AppNotice.show(
              context,
              const AppNotice(
                message: 'No matches found in this PDF.',
                kind: NoticeKind.warning,
              ),
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
        AppNotice.show(
          context,
          AppNotice(
            message:
                'Highlighted $matchCount match${matchCount == 1 ? '' : 'es'}${entireDocument ? ' across ${matchingPages.length} pages' : ' on page $_page'}.',
            kind: NoticeKind.info,
            action: NoticeAction(
              label: 'Undo',
              onPressed: () => _undoRecentEdits(matchingPages.length),
            ),
          ),
        );
        return WorkflowOutcome.completed;
      } catch (e) {
        if (!mounted) return WorkflowOutcome.failed;
        if (latestStatus != null) _onOperationStatus(latestStatus);
        _reportError('Highlight failed.', e);
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
        _reportError('Signature failed.', e);
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
        _reportError('Signature failed.', e);
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

  // --- In-Canvas Unified Modes ---

  void _enterMarkupMode() {
    setState(() {
      _canvasMode = DocumentInteractionMode.markup;
      _canvasStrokes.clear();
      _activeStroke.clear();
      _textSelectionAnchor = null;
      _textSelectionExtent = null;
    });
  }

  void _undoLastCanvasStroke() {
    if (_canvasStrokes.isNotEmpty) {
      setState(() => _canvasStrokes.removeLast());
    }
  }

  void _cancelMarkup() {
    setState(() {
      _canvasStrokes.clear();
      _activeStroke.clear();
      _canvasMode = DocumentInteractionMode.read;
    });
  }

  Future<void> _applyCanvasStrokes() async {
    final engine = _engine;
    final doc = _doc;
    if (engine == null || doc == null || _canvasStrokes.isEmpty) {
      setState(() => _canvasMode = DocumentInteractionMode.read);
      return;
    }
    setState(() => _busy = true);
    try {
      final response = await engine.executeTool(
        handle: doc,
        tool: 'comment_add',
        argumentsJson: jsonEncode(
          annotation_geo.inkArgs(
            page: _page,
            strokes: _canvasStrokes,
            dpi: 96,
            color: _markupColor,
            width: _markupWidth,
          ),
        ),
      );
      _onOperationStatus(response.status);
      final png = await engine.renderPagePng(
        handle: doc,
        page1Based: _page,
        dpi: 96,
      );
      if (!mounted) return;
      setState(() {
        _png = png;
        _canvasStrokes.clear();
        _activeStroke.clear();
        _canvasMode = DocumentInteractionMode.read;
      });
      AppNotice.show(
        context,
        AppNotice(
          message: 'Markup saved on page $_page.',
          kind: NoticeKind.success,
          action: NoticeAction(label: 'Undo', onPressed: _undo),
        ),
      );
    } catch (e) {
      if (mounted) _reportError('Could not save markup.', e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enterSignMode() async {
    final doc = _doc;
    final engine = _engine;
    if (doc == null || engine == null) return;
    setState(() {
      _canvasMode = DocumentInteractionMode.sign;
      _activeSignatureIsDate = false;
      final w = _imageWidthPx ?? 600;
      final h = _imageHeightPx ?? 800;
      _draftSignaturePositionPx = Offset(w * 0.25, h * 0.7);
    });
    try {
      final store = SignatureStore();
      final savedTyped = await store.loadTypedName();
      final savedDrawn = await store.loadDrawn();
      if (!mounted || _canvasMode != DocumentInteractionMode.sign) return;
      setState(() {
        _activeSignatureTyped = savedTyped;
        _activeSignatureImage = savedDrawn;
      });
    } catch (_) {}
  }

  void _cancelSign() {
    setState(() {
      _draftSignaturePositionPx = null;
      _canvasMode = DocumentInteractionMode.read;
    });
  }

  Future<void> _applySignaturePlacement() async {
    final engine = _engine;
    final doc = _doc;
    final draft = _draftSignaturePositionPx;
    if (engine == null || doc == null || draft == null) return;
    setState(() => _busy = true);
    try {
      final at = [
        annotation_geo.pxToPt(draft.dx, 96),
        annotation_geo.pxToPt(draft.dy, 96),
      ];

      bridge.OperationResponse response;
      if (_activeSignatureIsDate) {
        response = await engine.executeTool(
          handle: doc,
          tool: 'fill_sign_add',
          argumentsJson: jsonEncode({'page': _page, 'type': 'date', 'at': at}),
        );
      } else if (_activeSignatureImage != null) {
        final staged = await engine.stageFile(
          name: 'signature.png',
          bytes: _activeSignatureImage!,
        );
        response = await engine.executeTool(
          handle: doc,
          tool: 'fill_sign_add',
          argumentsJson: jsonEncode({
            'page': _page,
            'type': 'signature',
            'at': at,
            'source': staged,
          }),
        );
      } else if (_activeSignatureTyped != null &&
          _activeSignatureTyped!.isNotEmpty) {
        response = await engine.executeTool(
          handle: doc,
          tool: 'fill_sign_add',
          argumentsJson: jsonEncode({
            'page': _page,
            'type': 'signature',
            'at': at,
            'name': _activeSignatureTyped,
          }),
        );
      } else {
        setState(() => _busy = false);
        await _promptCreateSignature();
        return;
      }

      _onOperationStatus(response.status);
      final png = await engine.renderPagePng(
        handle: doc,
        page1Based: _page,
        dpi: 96,
      );
      if (!mounted) return;
      setState(() {
        _png = png;
        _draftSignaturePositionPx = null;
        _canvasMode = DocumentInteractionMode.read;
      });
      AppNotice.show(
        context,
        AppNotice(
          message: 'Signature placed on page $_page.',
          kind: NoticeKind.success,
          action: NoticeAction(label: 'Undo', onPressed: _undo),
        ),
      );
    } catch (e) {
      if (mounted) _reportError('Could not place signature.', e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _promptCreateSignature() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Create signature',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.gesture),
                title: const Text('Draw signature'),
                onTap: () => Navigator.pop(context, 'draw'),
              ),
              ListTile(
                leading: const Icon(Icons.text_fields),
                title: const Text('Type your name'),
                onTap: () => Navigator.pop(context, 'type'),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == 'draw') {
      if (!mounted) return;
      final png = await showModalBottomSheet<Uint8List>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => const SignaturePad(),
      );
      if (png != null && png.isNotEmpty) {
        await SignatureStore().saveDrawn(png);
        if (!mounted) return;
        setState(() {
          _activeSignatureImage = png;
          _activeSignatureTyped = null;
          _activeSignatureIsDate = false;
        });
      }
    } else if (choice == 'type') {
      if (!mounted) return;
      final name = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => const SignatureSheet(),
      );
      if (name != null && name.trim().isNotEmpty) {
        await SignatureStore().saveTypedName(name.trim());
        if (!mounted) return;
        setState(() {
          _activeSignatureTyped = name.trim();
          _activeSignatureImage = null;
          _activeSignatureIsDate = false;
        });
      }
    }
  }

  void _onSelectBottomMode(int index) {
    switch (index) {
      case 0:
        setState(() {
          _canvasMode = DocumentInteractionMode.read;
          _showChrome = true;
        });
      case 1:
        _enterMarkupMode();
      case 2:
        _enterSignMode();
      case 3:
        _openPages();
      case 4:
        _showTools();
    }
  }

  int _canvasModeToIndex([DocumentInteractionMode? mode]) {
    switch (mode ?? _canvasMode) {
      case DocumentInteractionMode.read:
        return 0;
      case DocumentInteractionMode.markup:
        return 1;
      case DocumentInteractionMode.sign:
        return 2;
    }
  }

  Widget _buildReadNavigationBar(BuildContext context) {
    return NavigationBar(
      selectedIndex: _canvasModeToIndex(),
      onDestinationSelected: _onSelectBottomMode,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.menu_book_outlined),
          selectedIcon: Icon(Icons.menu_book),
          label: 'Read',
        ),
        NavigationDestination(
          icon: Icon(Icons.draw_outlined),
          selectedIcon: Icon(Icons.draw),
          label: 'Markup',
        ),
        NavigationDestination(
          icon: Icon(Icons.history_edu_outlined),
          selectedIcon: Icon(Icons.history_edu),
          label: 'Sign',
        ),
        NavigationDestination(
          icon: Icon(Icons.grid_view_outlined),
          selectedIcon: Icon(Icons.grid_view),
          label: 'Pages',
        ),
        NavigationDestination(
          icon: Icon(Icons.tune_outlined),
          selectedIcon: Icon(Icons.tune),
          label: 'Tools',
        ),
      ],
    );
  }

  Widget _buildMarkupBottomPalette(BuildContext context) {
    final theme = Theme.of(context);
    final colors = [
      ('yellow', const Color(0xFFFFD54F)),
      ('red', const Color(0xFFE53935)),
      ('blue', const Color(0xFF1E88E5)),
      ('green', const Color(0xFF43A047)),
      ('black', Colors.black),
    ];
    return Material(
      elevation: 6,
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: 'pen',
                      icon: Icon(Icons.edit_outlined),
                      label: Text('Pen'),
                    ),
                    ButtonSegment(
                      value: 'highlighter',
                      icon: Icon(Icons.border_color_outlined),
                      label: Text('Highlighter'),
                    ),
                    ButtonSegment(
                      value: 'eraser',
                      icon: Icon(Icons.cleaning_services_outlined),
                      label: Text('Eraser'),
                    ),
                  ],
                  selected: {_markupTool},
                  onSelectionChanged: (set) {
                    if (set.isNotEmpty) {
                      setState(() => _markupTool = set.first);
                    }
                  },
                ),
              ),
              if (_markupTool != 'eraser') ...[
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final c in colors)
                        GestureDetector(
                          onTap: () => setState(() => _markupColor = c.$1),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: c.$2,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _markupColor == c.$1
                                    ? theme.colorScheme.primary
                                    : Colors.grey.shade400,
                                width: _markupColor == c.$1 ? 3 : 1.5,
                              ),
                              boxShadow: _markupColor == c.$1
                                  ? [
                                      BoxShadow(
                                        color: c.$2.withValues(alpha: 0.5),
                                        blurRadius: 6,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                      const SizedBox(width: 16),
                      PopupMenuButton<double>(
                        tooltip: 'Stroke thickness',
                        initialValue: _markupWidth,
                        onSelected: (w) => setState(() => _markupWidth = w),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 2.0, child: Text('Fine (2pt)')),
                          PopupMenuItem(
                            value: 4.0,
                            child: Text('Medium (4pt)'),
                          ),
                          PopupMenuItem(value: 8.0, child: Text('Thick (8pt)')),
                          PopupMenuItem(
                            value: 14.0,
                            child: Text('Heavy (14pt)'),
                          ),
                        ],
                        child: Chip(
                          avatar: const Icon(Icons.line_weight, size: 16),
                          label: Text('${_markupWidth.toInt()}pt'),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSignBottomPalette(BuildContext context) {
    final theme = Theme.of(context);
    final hasSignature =
        (_activeSignatureTyped != null && _activeSignatureTyped!.isNotEmpty) ||
        _activeSignatureImage != null;
    return Material(
      elevation: 6,
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            hasSignature
                                ? Icons.check_circle
                                : Icons.warning_amber_rounded,
                            color: hasSignature ? Colors.green : Colors.orange,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              hasSignature
                                  ? (_draftSignaturePositionPx != null
                                        ? 'Tap & drag signature to adjust'
                                        : 'Tap on page to place signature')
                                  : 'No signature configured',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _promptCreateSignature,
                    icon: const Icon(Icons.edit, size: 16),
                    label: Text(hasSignature ? 'Change' : 'Create'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Size: ${_draftSignatureWidthPx.toInt()} × ${_draftSignatureHeightPx.toInt()} pt',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Shrink signature',
                        iconSize: 20,
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          setState(() {
                            _draftSignatureWidthPx =
                                (_draftSignatureWidthPx * 0.85).clamp(
                                  60.0,
                                  400.0,
                                );
                            _draftSignatureHeightPx =
                                (_draftSignatureHeightPx * 0.85).clamp(
                                  30.0,
                                  200.0,
                                );
                          });
                        },
                        icon: const Icon(Icons.zoom_out),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Enlarge signature',
                        iconSize: 20,
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          setState(() {
                            _draftSignatureWidthPx =
                                (_draftSignatureWidthPx * 1.15).clamp(
                                  60.0,
                                  400.0,
                                );
                            _draftSignatureHeightPx =
                                (_draftSignatureHeightPx * 1.15).clamp(
                                  30.0,
                                  200.0,
                                );
                          });
                        },
                        icon: const Icon(Icons.zoom_in),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
          currentPage: _page,
          pageCount: _pageCount,
          onAddComment: (page) async {
            await _goto(page);
            if (mounted && !_busy && _page == page) {
              await _openAnnotate(initialMode: AnnotateMode.note);
            }
          },
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

  Future<WorkflowOutcome> _openSecure({String? initialAction}) async {
    final engine = _engine;
    final doc = _doc;
    if (engine == null || doc == null) return WorkflowOutcome.failed;
    var statusChanged = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SecureSheet(
        documentName: _name,
        initialAction: initialAction,
        engine: engine,
        handle: doc,
        onStatusChanged: (status) {
          statusChanged = true;
          _onOperationStatus(status);
        },
      ),
    );
    return statusChanged
        ? WorkflowOutcome.completed
        : WorkflowOutcome.cancelled;
  }

  Future<WorkflowOutcome> _openOrganize({String? initialAction}) async {
    final engine = _engine;
    final doc = _doc;
    if (engine == null) return WorkflowOutcome.failed;
    var statusChanged = false;
    ({Uint8List bytes, String name})? output;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => OrganizeSheet(
        initialAction: initialAction,
        onOpenDocument: (bytes, name) {
          output = (bytes: bytes, name: name);
          Navigator.pop(sheetContext);
        },
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
    if (output != null && mounted) {
      await _openDocumentBytes(output!.name, output!.bytes);
    }
    return statusChanged
        ? WorkflowOutcome.completed
        : WorkflowOutcome.cancelled;
  }

  Future<WorkflowOutcome> _openExport({String? initialAction}) async {
    final engine = _engine;
    final doc = _doc;
    if (engine == null || doc == null) return WorkflowOutcome.failed;
    var statusChanged = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => ExportSheet(
        documentName: _name,
        initialAction: initialAction,
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
    return statusChanged
        ? WorkflowOutcome.completed
        : WorkflowOutcome.cancelled;
  }

  Future<void> _openTextEdit() async {
    final engine = _engine;
    final doc = _doc;
    final page = _page;
    if (engine == null || doc == null) return;
    setState(() => _busy = true);
    try {
      final size = await engine.pageSize(handle: doc, page1Based: page);
      final png = await engine.renderPagePng(
        handle: doc,
        page1Based: page,
        dpi: 96,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => TextEditSheet(
            engine: engine,
            handle: doc,
            page: page,
            png: png,
            imageWidthPx: size.width * 96 / 72,
            imageHeightPx: size.height * 96 / 72,
            onStatusChanged: _onOperationStatus,
          ),
        ),
      );
    } catch (e) {
      if (mounted) _reportError('Could not open the text editor.', e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
        return await _openExport(initialAction: action);
      default:
        return WorkflowOutcome.completed;
    }
  }

  Future<void> _showTools() async {
    AppNotice.dismiss(context);
    if (_busy || _launchingTask || _engine == null) return;
    final task = await showModalBottomSheet<PdfTask>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: FractionallySizedBox(
          heightFactor: 0.92,
          child: TaskCatalog(
            onSelected: (task) => Navigator.pop(context, task),
          ),
        ),
      ),
    );
    if (task != null && mounted) await _launchTask(task);
  }

  Future<void> _launchTask(PdfTask task) async {
    if (_busy || _launchingTask || _engine == null) return;
    if (!FeatureFlagService.instance.isToolEnabled(task.id)) {
      final reason = FeatureFlagService.instance.getToolDisabledReason(task.id);
      AppNotice.show(
        context,
        AppNotice(
          message: reason ?? 'This tool is temporarily unavailable.',
          kind: NoticeKind.warning,
        ),
      );
      return;
    }
    TelemetryManager.instance.track('task_launched', {
      'task_id': task.id,
      'title': task.title,
    });
    setState(() => _launchingTask = true);
    try {
      if (task.needsDocument && _doc == null) {
        await _open();
        if (!mounted || _doc == null) return;
      }
      if (!mounted) return;
      switch (task.id) {
        case 'blank':
          await _newBlankPdf();
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
        case 'agent':
          await _openAgentCommand();
        case 'secure':
          await _openSecure();
        case 'protect':
        case 'redact':
        case 'sanitize':
        case 'flatten':
          await _openSecure(initialAction: task.id);
        case 'combine':
        case 'images':
        case 'split':
        case 'extract':
        case 'labels':
        case 'headerFooter':
        case 'watermark':
        case 'background':
        case 'removeMarks':
          await _openOrganize(initialAction: task.id);
        default:
          await _openExport(initialAction: task.id);
      }
    } finally {
      if (mounted) setState(() => _launchingTask = false);
    }
  }

  Future<void> _goHome() async {
    AppNotice.dismiss(context);
    if (_busy || _launchingTask) return;
    if (_finding) {
      setState(() => _finding = false);
      return;
    }
    if (_textSelectionAnchor != null) {
      setState(() {
        _textSelectionAnchor = null;
        _textSelectionExtent = null;
      });
      return;
    }
    if (!await _confirmReplacingCurrent() || !mounted) return;
    final doc = _doc;
    if (doc != null) await _engine!.close(handle: doc);
    if (!mounted) return;
    setState(() {
      _doc = null;
      _png = null;
      _name = null;
      _page = 1;
      _pageCount = 0;
      _dirty = false;
      _undoLabel = null;
      _redoLabel = null;
      _markers = [];
      _verticalPageImages.clear();
      _horizontalPageImages.clear();
      _status = 'Choose a task or open a PDF';
    });
  }

  Future<void> _finishDocument() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Save & share',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(_name ?? 'Current PDF'),
              const SizedBox(height: 8),
              Text(
                _dirty
                    ? 'Your changes are ready to save. Sharing sends a copy; it does not save your working document.'
                    : 'Save another copy or share this PDF.',
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, 'save'),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save PDF'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, 'share'),
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share a copy'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Keep editing'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'save') await _save();
    if (action == 'share') await _shareCurrentPdf();
  }

  Future<void> _openAgentCommand() async {
    if (_doc == null) return;
    final request = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => AgentCommandSheet(
        engine: _engine,
        documentHandle: _doc,
        documentName: _name,
        pageCount: _pageCount,
        currentPage: _page,
        onOperationCommitted: _onOperationStatus,
      ),
    );
    if (!mounted || request == null) return;
    if (request == 'agent_executed') return;
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
        outcome = await _openExport(
          initialAction: request == 'export' ? 'office' : request,
        );
      case 'combine':
        outcome = await _openOrganize(initialAction: 'combine');
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
    if (outcome == WorkflowOutcome.failed) {
      AppNotice.show(
        context,
        AppNotice(
          message: 'Could not complete ${_agentTaskLabel(request)}.',
          kind: NoticeKind.error,
        ),
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
    _zoomAnimationController?.dispose();
    _viewerTransform.dispose();
    _continuousScroll.dispose();
    _recoveryDebounce?.cancel();
    _verticalPageImages.dispose();
    _horizontalPageImages.dispose();
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
    return PopScope(
      canPop: _doc == null && !_busy && !_launchingTask,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          if (_textSelectionAnchor != null) {
            setState(() {
              _textSelectionAnchor = null;
              _textSelectionExtent = null;
            });
          } else {
            _goHome();
          }
        }
      },
      child: Scaffold(
        appBar:
            (_doc != null &&
                !_showChrome &&
                _canvasMode == DocumentInteractionMode.read)
            ? null
            : (_canvasMode == DocumentInteractionMode.markup
                  ? AppBar(
                      leading: IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Cancel markup',
                        onPressed: _cancelMarkup,
                      ),
                      title: Text('Markup · Page $_page'),
                      actions: [
                        IconButton(
                          icon: const Icon(Icons.undo),
                          tooltip: 'Undo last stroke',
                          onPressed: _canvasStrokes.isNotEmpty
                              ? _undoLastCanvasStroke
                              : null,
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilledButton(
                            onPressed: _busy || _canvasStrokes.isEmpty
                                ? null
                                : _applyCanvasStrokes,
                            child: const Text('Apply'),
                          ),
                        ),
                      ],
                    )
                  : (_canvasMode == DocumentInteractionMode.sign
                        ? AppBar(
                            leading: IconButton(
                              icon: const Icon(Icons.close),
                              tooltip: 'Cancel placement',
                              onPressed: _cancelSign,
                            ),
                            title: Text('Place Signature · Page $_page'),
                            actions: [
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: FilledButton(
                                  onPressed:
                                      _busy || _draftSignaturePositionPx == null
                                      ? null
                                      : _applySignaturePlacement,
                                  child: const Text('Place'),
                                ),
                              ),
                            ],
                          )
                        : AppBar(
                            leading: _doc == null
                                ? null
                                : IconButton(
                                    onPressed: _busy ? null : _goHome,
                                    tooltip: 'Close document',
                                    icon: const Icon(Icons.arrow_back),
                                  ),
                            title: Text(
                              _name ?? 'Overline',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            actions: [
                              PopupMenuButton<PdfCraftThemeChoice>(
                                tooltip: 'Color theme',
                                icon: Icon(
                                  PdfCraftThemeScope.maybeOf(context)
                                          ?.notifier
                                          ?.choice
                                          .icon ??
                                      Icons.brightness_auto,
                                ),
                                onSelected: (choice) {
                                  unawaited(
                                    PdfCraftThemeScope.maybeOf(context)
                                            ?.notifier
                                            ?.setChoice(choice) ??
                                        Future<void>.value(),
                                  );
                                },
                                itemBuilder: (_) => PdfCraftThemeChoice.values
                                    .map(
                                      (choice) =>
                                          PopupMenuItem<PdfCraftThemeChoice>(
                                            value: choice,
                                            child: Row(
                                              children: [
                                                Icon(choice.icon),
                                                const SizedBox(width: 8),
                                                Text(choice.label),
                                              ],
                                            ),
                                          ),
                                    )
                                    .toList(),
                              ),
                              if (_doc != null) ...[
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                    horizontal: 4,
                                  ),
                                  child: FilledButton.tonal(
                                    onPressed: _busy ? null : _finishDocument,
                                    child: const Text('Finish'),
                                  ),
                                ),
                                IconButton(
                                  onPressed: _busy ? null : _print,
                                  icon: const Icon(Icons.print_outlined),
                                  tooltip: 'Print this PDF',
                                ),
                                PopupMenuButton<ReadingMode>(
                                  tooltip: 'Reading view',
                                  icon: Icon(_readingMode.icon),
                                  onSelected: (mode) =>
                                      unawaited(_setReadingMode(mode)),
                                  itemBuilder: (_) => ReadingMode.values
                                      .map(
                                        (mode) => PopupMenuItem<ReadingMode>(
                                          value: mode,
                                          child: Row(
                                            children: [
                                              Icon(mode.icon),
                                              const SizedBox(width: 8),
                                              Expanded(child: Text(mode.label)),
                                              if (mode == _readingMode) ...[
                                                const SizedBox(width: 8),
                                                const Icon(
                                                  Icons.check,
                                                  size: 18,
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                                IconButton(
                                  onPressed: _busy || _undoLabel == null
                                      ? null
                                      : _undo,
                                  icon: const Icon(Icons.undo),
                                  tooltip: _undoLabel == null
                                      ? 'Nothing to undo'
                                      : 'Undo $_undoLabel',
                                ),
                                PopupMenuButton<String>(
                                  tooltip: 'Document options',
                                  enabled: !_busy,
                                  onSelected: (value) {
                                    switch (value) {
                                      case 'redo':
                                        _redo();
                                      case 'find':
                                        setState(() => _finding = true);
                                      case 'invertColors':
                                        unawaited(
                                          _setInvertedColors(
                                            !_invertDocumentColors,
                                          ),
                                        );
                                        break;
                                      case 'open':
                                        _open();
                                      case 'diagnostics':
                                        DiagnosticsSheet.show(context);
                                      case 'about':
                                        _showAboutAndLicenses(context);
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                      value: 'redo',
                                      enabled: _redoLabel != null,
                                      child: Text(
                                        _redoLabel == null
                                            ? 'Nothing to redo'
                                            : 'Redo $_redoLabel',
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'find',
                                      child: Text('Find in PDF'),
                                    ),
                                    PopupMenuItem(
                                      value: 'invertColors',
                                      child: Row(
                                        children: [
                                          Icon(
                                            _invertDocumentColors
                                                ? Icons.invert_colors
                                                : Icons
                                                      .invert_colors_off_outlined,
                                          ),
                                          const SizedBox(width: 8),
                                          const Text('Invert page colors'),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'diagnostics',
                                      child: Row(
                                        children: [
                                          Icon(Icons.troubleshoot, size: 20),
                                          SizedBox(width: 8),
                                          Text('Diagnostics & Logs'),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'about',
                                      child: Row(
                                        children: [
                                          Icon(Icons.info_outline, size: 20),
                                          SizedBox(width: 8),
                                          Text('About & Licenses'),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'open',
                                      child: Text('Open another PDF'),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ))),
        body: Column(
          children: [
            if (_doc != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _dirty
                            ? 'Unsaved changes${_recoveryAvailable ? ' • recovery available' : ''}'
                            : 'No unsaved changes',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Text(
                      '$_pageCount ${_pageCount == 1 ? 'page' : 'pages'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            if (_busy) const LinearProgressIndicator(),
            Expanded(
              child: ValueListenableBuilder<Matrix4>(
                valueListenable: _viewerTransform,
                builder: (context, transform, _) {
                  if (_readingMode == ReadingMode.vertical) {
                    return _verticalPageList();
                  }
                  if (_readingMode == ReadingMode.horizontalContinuous) {
                    return _horizontalPageList();
                  }
                  if (_png == null) {
                    return _doc == null
                        ? _emptyDocumentHome()
                        : Center(child: Text(_status));
                  }
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final sourceWidth = _imageWidthPx ?? 1;
                      final sourceHeight = _imageHeightPx ?? 1;
                      final secondWidth = _secondImageWidthPx ?? 0;
                      final secondHeight = _secondImageHeightPx ?? 0;
                      final facing =
                          _readingMode == ReadingMode.doublePage &&
                          _secondPng != null;
                      final gap = facing ? 16.0 : 0.0;
                      final combinedSourceWidth =
                          sourceWidth + (facing ? gap + secondWidth : 0);
                      final combinedSourceHeight = sourceHeight > 0
                          ? (facing
                                ? math.max(sourceHeight, secondHeight)
                                : sourceHeight)
                          : 1.0;
                      final fitScale = fitPageScale(
                        viewportWidth: constraints.maxWidth,
                        viewportHeight: constraints.maxHeight,
                        pageWidth: facing ? combinedSourceWidth : sourceWidth,
                        pageHeight: facing
                            ? combinedSourceHeight
                            : sourceHeight,
                      );
                      final pageWidth = sourceWidth * fitScale;
                      final pageHeight = sourceHeight * fitScale;
                      final secondPageWidth = secondWidth * fitScale;
                      final secondPageHeight = secondHeight * fitScale;
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
                            (anchor ? rect[0] : rect[2]) * 96 / 72 * fitScale;
                        final y = rect[3] * 96 / 72 * fitScale;
                        final currentScale = _viewerTransform.value
                            .getMaxScaleOnAxis();
                        final invScale =
                            (1.0 / (currentScale > 0.05 ? currentScale : 1.0))
                                .clamp(0.125, 1.0);
                        final handleSize = 48.0 * invScale;
                        final dotSize = 18.0 * invScale;
                        final borderWidth = 2.0 * invScale;
                        final halfHandle = handleSize / 2;
                        return Positioned(
                          left: x - halfHandle,
                          top: y - halfHandle,
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
                                width: handleSize,
                                height: handleSize,
                                child: Center(
                                  child: Container(
                                    width: dotSize,
                                    height: dotSize,
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: borderWidth,
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
                              key: _readerViewportKey,
                              transformationController: _viewerTransform,
                              panEnabled:
                                  (_canvasMode ==
                                          DocumentInteractionMode.read &&
                                      _viewerTransform.value
                                              .getMaxScaleOnAxis() >
                                          1.05) ||
                                  _viewerPointerCount >= 2,
                              onInteractionStart: (_) =>
                                  _zoomAnimationController?.stop(),
                              scaleEnabled: true,
                              onInteractionUpdate: (_) {
                                if (_viewerTransform.value.getMaxScaleOnAxis() >
                                    1.05) {
                                  _swipeStartedAtFit = false;
                                }
                              },
                              minScale: 1,
                              maxScale: 8,
                              boundaryMargin: EdgeInsets.zero,
                              clipBehavior: Clip.hardEdge,
                              child: Center(
                                child: SizedBox(
                                  width: facing
                                      ? pageWidth +
                                            16 * fitScale.clamp(0.1, 1.0) +
                                            secondPageWidth
                                      : pageWidth,
                                  height: combinedSourceHeight * fitScale,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      if (_canvasMode ==
                                              DocumentInteractionMode.read &&
                                          _textSelectionAnchor == null) {
                                        setState(
                                          () => _showChrome = !_showChrome,
                                        );
                                      }
                                    },
                                    onTapDown:
                                        _canvasMode ==
                                            DocumentInteractionMode.sign
                                        ? (details) {
                                            setState(() {
                                              _draftSignaturePositionPx = Offset(
                                                (details.localPosition.dx /
                                                        fitScale)
                                                    .clamp(
                                                      0.0,
                                                      (sourceWidth -
                                                              _draftSignatureWidthPx)
                                                          .clamp(
                                                            0.0,
                                                            sourceWidth,
                                                          ),
                                                    ),
                                                (details.localPosition.dy /
                                                        fitScale)
                                                    .clamp(
                                                      0.0,
                                                      (sourceHeight -
                                                              _draftSignatureHeightPx)
                                                          .clamp(
                                                            0.0,
                                                            sourceHeight,
                                                          ),
                                                    ),
                                              );
                                            });
                                          }
                                        : null,
                                    onPanStart:
                                        _canvasMode ==
                                            DocumentInteractionMode.markup
                                        ? (details) {
                                            final local = Offset(
                                              (details.localPosition.dx /
                                                      fitScale)
                                                  .clamp(0.0, sourceWidth),
                                              (details.localPosition.dy /
                                                      fitScale)
                                                  .clamp(0.0, sourceHeight),
                                            );
                                            setState(() {
                                              _activeStroke = [local];
                                            });
                                          }
                                        : null,
                                    onPanUpdate:
                                        _canvasMode ==
                                            DocumentInteractionMode.markup
                                        ? (details) {
                                            final local = Offset(
                                              (details.localPosition.dx /
                                                      fitScale)
                                                  .clamp(0.0, sourceWidth),
                                              (details.localPosition.dy /
                                                      fitScale)
                                                  .clamp(0.0, sourceHeight),
                                            );
                                            setState(() {
                                              _activeStroke.add(local);
                                            });
                                          }
                                        : null,
                                    onPanEnd:
                                        _canvasMode ==
                                            DocumentInteractionMode.markup
                                        ? (_) {
                                            if (_activeStroke.length > 1) {
                                              setState(() {
                                                final isHighlighter =
                                                    _markupTool ==
                                                    'highlighter';
                                                _canvasStrokes.add(
                                                  annotation_geo.InkStroke(
                                                    points: [
                                                      for (final p
                                                          in _activeStroke)
                                                        annotation_geo.Point(
                                                          p.dx,
                                                          p.dy,
                                                        ),
                                                    ],
                                                    color: _markupColor,
                                                    width: isHighlighter
                                                        ? 14.0
                                                        : _markupWidth,
                                                  ),
                                                );
                                                _activeStroke = [];
                                              });
                                            }
                                          }
                                        : null,
                                    onDoubleTapDown: (details) =>
                                        _doubleTapPosition =
                                            details.localPosition,
                                    onDoubleTap: () {
                                      if (_canvasMode !=
                                              DocumentInteractionMode.read ||
                                          _busy ||
                                          _doubleTapPosition == null) {
                                        return;
                                      }
                                      final currentScale = _viewerTransform
                                          .value
                                          .getMaxScaleOnAxis();
                                      HapticFeedback.selectionClick();
                                      if (currentScale > 1.05) {
                                        _animateViewerTransform(
                                          Matrix4.identity(),
                                        );
                                      } else {
                                        const targetScale = 2.5;
                                        final focal = _doubleTapPosition!;
                                        final pageOriginX =
                                            (constraints.maxWidth -
                                                (facing
                                                    ? combinedSourceWidth *
                                                          fitScale
                                                    : pageWidth)) /
                                            2;
                                        final pageOriginY =
                                            (constraints.maxHeight -
                                                combinedSourceHeight *
                                                    fitScale) /
                                            2;
                                        final cx = pageOriginX + focal.dx;
                                        final cy = pageOriginY + focal.dy;
                                        final rawDx =
                                            (constraints.maxWidth / 2) -
                                            (cx * targetScale);
                                        final rawDy =
                                            (constraints.maxHeight / 2) -
                                            (cy * targetScale);
                                        final minDx =
                                            constraints.maxWidth *
                                            (1 - targetScale);
                                        final minDy =
                                            constraints.maxHeight *
                                            (1 - targetScale);
                                        final clampedDx = rawDx.clamp(
                                          minDx,
                                          0.0,
                                        );
                                        final clampedDy = rawDy.clamp(
                                          minDy,
                                          0.0,
                                        );
                                        _animateViewerTransform(
                                          Matrix4.identity()
                                            ..translateByDouble(
                                              clampedDx,
                                              clampedDy,
                                              0,
                                              1,
                                            )
                                            ..scaleByDouble(
                                              targetScale,
                                              targetScale,
                                              1,
                                              1,
                                            ),
                                        );
                                      }
                                    },
                                    onLongPressStart: (details) {
                                      if (_canvasMode ==
                                          DocumentInteractionMode.read) {
                                        if (facing) {
                                          final second =
                                              details.localPosition.dx >
                                              pageWidth + gap * fitScale;
                                          final width = second
                                              ? secondPageWidth
                                              : pageWidth;
                                          final height = second
                                              ? secondPageHeight
                                              : pageHeight;
                                          final origin = Offset(
                                            second
                                                ? pageWidth + gap * fitScale
                                                : 0,
                                            (combinedSourceHeight * fitScale -
                                                    height) /
                                                2,
                                          );
                                          _offerPageTextSelection(
                                            _page + (second ? 1 : 0),
                                            details.localPosition - origin,
                                            Size(width, height),
                                          );
                                        } else {
                                          _beginTextSelection(
                                            details.localPosition,
                                            fitScale,
                                          );
                                        }
                                      }
                                    },
                                    onLongPressMoveUpdate: (details) {
                                      if (_canvasMode ==
                                              DocumentInteractionMode.read &&
                                          !facing) {
                                        _extendTextSelection(
                                          details.localPosition,
                                          fitScale,
                                        );
                                      }
                                    },
                                    onLongPressEnd: (_) =>
                                        _viewerLongPressSelecting = false,
                                    child: Stack(
                                      key: _viewerPageKey,
                                      fit: StackFit.expand,
                                      children: [
                                        if (facing)
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              SizedBox(
                                                width: pageWidth,
                                                height: pageHeight,
                                                child: _documentImage(_png!),
                                              ),
                                              SizedBox(
                                                width:
                                                    16 *
                                                    fitScale.clamp(0.1, 1.0),
                                              ),
                                              SizedBox(
                                                width: secondPageWidth,
                                                height: secondPageHeight,
                                                child: _documentImage(
                                                  _secondPng!,
                                                ),
                                              ),
                                            ],
                                          )
                                        else
                                          Semantics(
                                            image: true,
                                            label:
                                                'Document page $_page of $_pageCount',
                                            child: _documentImage(_png!),
                                          ),
                                        // In-canvas Markup layer
                                        CustomPaint(
                                          painter: _CanvasStrokePainter(
                                            strokes: _canvasStrokes,
                                            activeStroke: _activeStroke,
                                            activeTool: _markupTool,
                                            activeColor: _markupColor,
                                            activeWidth: _markupWidth,
                                            fitScale: fitScale,
                                          ),
                                        ),
                                        // In-canvas Signature placement box
                                        if (_canvasMode ==
                                                DocumentInteractionMode.sign &&
                                            _draftSignaturePositionPx != null)
                                          Positioned(
                                            left:
                                                _draftSignaturePositionPx!.dx *
                                                fitScale,
                                            top:
                                                _draftSignaturePositionPx!.dy *
                                                fitScale,
                                            child: GestureDetector(
                                              onPanUpdate: (details) {
                                                setState(() {
                                                  _draftSignaturePositionPx = Offset(
                                                    (_draftSignaturePositionPx!
                                                                .dx +
                                                            details.delta.dx /
                                                                fitScale)
                                                        .clamp(
                                                          0.0,
                                                          (sourceWidth -
                                                                  _draftSignatureWidthPx)
                                                              .clamp(
                                                                0.0,
                                                                sourceWidth,
                                                              ),
                                                        ),
                                                    (_draftSignaturePositionPx!
                                                                .dy +
                                                            details.delta.dy /
                                                                fitScale)
                                                        .clamp(
                                                          0.0,
                                                          (sourceHeight -
                                                                  _draftSignatureHeightPx)
                                                              .clamp(
                                                                0.0,
                                                                sourceHeight,
                                                              ),
                                                        ),
                                                  );
                                                });
                                              },
                                              child: Container(
                                                width:
                                                    _draftSignatureWidthPx *
                                                    fitScale,
                                                height:
                                                    _draftSignatureHeightPx *
                                                    fitScale,
                                                decoration: BoxDecoration(
                                                  border: Border.all(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .primary,
                                                    width: 2,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primaryContainer
                                                      .withValues(alpha: 0.35),
                                                ),
                                                child: Stack(
                                                  children: [
                                                    Center(
                                                      child:
                                                          _activeSignatureIsDate
                                                          ? Text(
                                                              DateTime.now()
                                                                  .toLocal()
                                                                  .toString()
                                                                  .split(
                                                                    ' ',
                                                                  )[0],
                                                              style: const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 16,
                                                              ),
                                                            )
                                                          : _activeSignatureImage !=
                                                                null
                                                          ? Image.memory(
                                                              _activeSignatureImage!,
                                                              fit: BoxFit
                                                                  .contain,
                                                            )
                                                          : Text(
                                                              _activeSignatureTyped ??
                                                                  'Signature',
                                                              style: const TextStyle(
                                                                fontFamily:
                                                                    'serif',
                                                                fontStyle:
                                                                    FontStyle
                                                                        .italic,
                                                                fontSize: 20,
                                                              ),
                                                            ),
                                                    ),
                                                    Positioned(
                                                      right: 0,
                                                      bottom: 0,
                                                      child: GestureDetector(
                                                        onPanUpdate: (details) {
                                                          setState(() {
                                                            _draftSignatureWidthPx =
                                                                (_draftSignatureWidthPx +
                                                                        details.delta.dx /
                                                                            fitScale)
                                                                    .clamp(
                                                                      80.0,
                                                                      400.0,
                                                                    );
                                                            _draftSignatureHeightPx =
                                                                (_draftSignatureHeightPx +
                                                                        details.delta.dy /
                                                                            fitScale)
                                                                    .clamp(
                                                                      30.0,
                                                                      200.0,
                                                                    );
                                                          });
                                                        },
                                                        child: Container(
                                                          width: 22,
                                                          height: 22,
                                                          decoration: BoxDecoration(
                                                            color:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .primary,
                                                            shape:
                                                                BoxShape.circle,
                                                          ),
                                                          child: const Icon(
                                                            Icons.open_in_full,
                                                            size: 13,
                                                            color: Colors.white,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        if (_finding && _findMatches.isNotEmpty)
                                          for (
                                            var matchIdx = 0;
                                            matchIdx < _findMatches.length;
                                            matchIdx++
                                          )
                                            if (_findMatches[matchIdx].page ==
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
                                                        decoration: BoxDecoration(
                                                          color:
                                                              matchIdx ==
                                                                  _findActiveIndex
                                                              ? const Color(
                                                                  0xFFFF9800,
                                                                ).withValues(
                                                                  alpha: 0.50,
                                                                )
                                                              : Colors.yellow
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
                                                                  alpha: 0.10,
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
                                          selectionHandle(selectionStart, true),
                                          selectionHandle(selectionEnd, false),
                                        ],
                                        for (final marker in _markers)
                                          Positioned(
                                            left: marker.x * fitScale - 24,
                                            top: marker.y * fitScale - 24,
                                            child: Semantics(
                                              button: true,
                                              label:
                                                  'Open ${marker.label} conversation on page $_page.',
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
                                                          color: Theme.of(
                                                            context,
                                                          ).colorScheme.primary,
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
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            if (_busy)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Semantics(liveRegion: true, child: Text(_status)),
              ),
          ],
        ),
        bottomNavigationBar: _doc == null
            ? null
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_textSelectionAnchor != null &&
                      _textSelectionExtent != null)
                    TextSelectionActions(
                      busy: _busy,
                      color: _textSelectionColor,
                      onColor: (color) =>
                          setState(() => _textSelectionColor = color),
                      onApply: (kind) => _applyTextSelection(kind: kind),
                      onCopy: _copyTextSelection,
                      onClear: () => setState(() {
                        _textSelectionAnchor = null;
                        _textSelectionExtent = null;
                      }),
                    )
                  else if (_showChrome &&
                      _canvasMode == DocumentInteractionMode.read)
                    ReaderControls(
                      page: _page,
                      pageCount: _pageCount,
                      onNavigate: _goto,
                      transform: _viewerTransform,
                      onUserZoom: () => _zoomAnimationController?.stop(),
                      viewportSize: () =>
                          (_readerViewportKey.currentContext?.findRenderObject()
                                  as RenderBox?)
                              ?.size,
                      busy: _busy,
                    ),
                  if (_showChrome && _textSelectionAnchor == null)
                    if (_canvasMode == DocumentInteractionMode.markup)
                      _buildMarkupBottomPalette(context)
                    else if (_canvasMode == DocumentInteractionMode.sign)
                      _buildSignBottomPalette(context)
                    else
                      _buildReadNavigationBar(context),
                ],
              ),
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
        AppNotice.show(
          context,
          const AppNotice(
            message: 'Enter 1 to 100 pages.',
            kind: NoticeKind.warning,
          ),
        );
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
      ({Uint8List bytes, String name})? output;
      await saveToolOutputs(context, engine, [
        for (final c in response.contents) c.json,
      ], onOpenDocument: (bytes, name) => output = (bytes: bytes, name: name));
      if (output != null && mounted) {
        await _openDocumentBytes(output!.name, output!.bytes);
      }
    } catch (e) {
      if (!mounted) return;
      _reportError('Could not create a blank PDF.', e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _emptyDocumentHome() {
    final enabled = !_busy && !_launchingTask && _engine != null;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          children: [
            // Privacy & offline assurance badge
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 14,
                        color: colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Offline & Private',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.info_outline, size: 20),
                  tooltip: 'About & Open Source Licenses',
                  onPressed: () => _showAboutAndLicenses(context),
                ),
                IconButton(
                  icon: const Icon(Icons.troubleshoot, size: 20),
                  tooltip: 'Diagnostics & Logs',
                  onPressed: () => DiagnosticsSheet.show(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'What would you like to do?',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Work on your PDFs on this device.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),

            // Hero "Open a PDF" Card
            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: enabled ? _open : null,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.folder_open,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Choose Document',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Select any PDF from your device storage to view or edit',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: enabled ? _open : null,
                          icon: const Icon(Icons.folder_open),
                          label: const Text('Open a PDF'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Quick Create shortcut
            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: enabled ? _newBlankPdf : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.note_add_outlined,
                        size: 22,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'New Blank PDF',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'Create a clean empty canvas document',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            if (_recentDocuments.isNotEmpty) ...[
              Text(
                'Recent documents',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Column(
                    children: [
                      for (var i = 0; i < _recentDocuments.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            indent: 56,
                            color: colorScheme.outlineVariant.withValues(
                              alpha: 0.3,
                            ),
                          ),
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 4,
                          ),
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: colorScheme.secondaryContainer.withValues(
                                alpha: 0.5,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.description_outlined,
                              size: 20,
                              color: colorScheme.secondary,
                            ),
                          ),
                          title: Text(
                            _recentDocuments[i].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          subtitle: Text(
                            '${_recentDocuments[i].pageCount} ${_recentDocuments[i].pageCount == 1 ? 'page' : 'pages'}',
                          ),
                          onTap: enabled
                              ? () => _openRecent(_recentDocuments[i])
                              : null,
                          trailing: PopupMenuButton<String>(
                            tooltip: 'Options for ${_recentDocuments[i].name}',
                            onSelected: (_) async {
                              await _recentStore.removeRecent(
                                _recentDocuments[i].name,
                              );
                              await _loadRecents();
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'remove',
                                child: Text('Remove from recents'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            Text(
              'Popular tools',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: enabled ? _showTools : null,
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Browse all tools'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Common tasks card list
            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  children: [
                    for (var i = 0; i < pdfTasks.take(6).length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          indent: 56,
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.3,
                          ),
                        ),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer.withValues(
                              alpha: 0.5,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            pdfTasks[i].icon,
                            size: 20,
                            color: colorScheme.primary,
                          ),
                        ),
                        title: Text(
                          pdfTasks[i].title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          pdfTasks[i].description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        onTap: enabled ? () => _launchTask(pdfTasks[i]) : null,
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),
            if (_engine == null) ...[
              Card(
                color: colorScheme.errorContainer.withValues(alpha: 0.3),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: colorScheme.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _status,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                      if (_status.contains('failed'))
                        TextButton(
                          onPressed: _initEngine,
                          child: const Text('Try again'),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
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

class _CanvasStrokePainter extends CustomPainter {
  const _CanvasStrokePainter({
    required this.strokes,
    required this.activeStroke,
    required this.activeTool,
    required this.activeColor,
    required this.activeWidth,
    required this.fitScale,
  });

  final List<annotation_geo.InkStroke> strokes;
  final List<Offset> activeStroke;
  final String activeTool;
  final String activeColor;
  final double activeWidth;
  final double fitScale;

  Color _resolveColor(String name) {
    switch (name.toLowerCase()) {
      case 'yellow':
        return const Color(0xFFFFD54F);
      case 'red':
        return const Color(0xFFE53935);
      case 'blue':
        return const Color(0xFF1E88E5);
      case 'green':
        return const Color(0xFF43A047);
      case 'black':
        return Colors.black;
      case 'white':
        return Colors.white;
      default:
        return const Color(0xFFFFD54F);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.points.length < 2) continue;
      final isHighlighter = stroke.width >= 10.0;
      final paint = Paint()
        ..color = _resolveColor(stroke.color)
            .withValues(alpha: isHighlighter ? 0.38 : 0.95)
        ..strokeWidth = stroke.width * fitScale
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final path = Path();
      path.moveTo(stroke.points[0].x * fitScale, stroke.points[0].y * fitScale);
      for (var i = 1; i < stroke.points.length; i++) {
        path.lineTo(
          stroke.points[i].x * fitScale,
          stroke.points[i].y * fitScale,
        );
      }
      canvas.drawPath(path, paint);
    }

    if (activeStroke.length >= 2 && activeTool != 'eraser') {
      final isHighlighter = activeTool == 'highlighter';
      final paint = Paint()
        ..color = _resolveColor(activeColor)
            .withValues(alpha: isHighlighter ? 0.38 : 0.95)
        ..strokeWidth = (isHighlighter ? 14.0 : activeWidth) * fitScale
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final path = Path();
      path.moveTo(activeStroke[0].dx * fitScale, activeStroke[0].dy * fitScale);
      for (var i = 1; i < activeStroke.length; i++) {
        path.lineTo(
          activeStroke[i].dx * fitScale,
          activeStroke[i].dy * fitScale,
        );
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasStrokePainter oldDelegate) => true;
}
