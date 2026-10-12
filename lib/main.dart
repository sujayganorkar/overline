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
import 'widgets/annotate_page.dart';
import 'widgets/agent_command_sheet.dart';
import 'widgets/bookmarks_screen.dart';
import 'widgets/comments_screen.dart';
import 'widgets/document_heading.dart';
import 'widgets/document_insights_sheet.dart';
import 'widgets/export_sheet.dart';
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
  String? _undoLabel;
  String? _redoLabel;
  List<_Marker> _markers = const [];
  double? _imageWidthPx;
  double? _imageHeightPx;
  bool _recoveredUnsaved = false;
  bool _recoveryAvailable = false;
  int _activeSurface = 0;
  final TransformationController _viewerTransform = TransformationController();
  int _viewerPointerCount = 0;
  Offset? _viewerSwipeStart;
  Timer? _recoveryDebounce;
  Future<void> _recoveryWrites = Future<void>.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initEngine();
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Engine init failed: $e');
    }
  }

  Future<void> _open() async {
    int? openedDoc;
    try {
      final files = await FilePickerPlatform.instance.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (!mounted || files.isEmpty) return;
      final file = files.first;
      final fileBytes = await file.readAsBytes();
      if (!mounted || fileBytes.isEmpty) return;
      if (!await _confirmReplacingCurrent()) return;
      setState(() {
        _busy = true;
        _status = 'Opening ${file.name}\u2026';
      });
      final engine = _engine;
      if (engine == null) throw StateError('engine not initialized');
      final previousDoc = _doc;
      openedDoc = await _openDocument(engine, file.name, fileBytes);
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
        _name = file.name;
        _pageCount = count;
        _page = 1;
        _dirty = status.dirty;
        _recoveredUnsaved = false;
        _recoveryAvailable = false;
        _status = 'Opened ${file.name}';
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
      setState(() {
        _png = png;
        _imageWidthPx = pageSize.width * 96 / 72;
        _imageHeightPx = pageSize.height * 96 / 72;
        _status = 'Swipe to turn pages · Pinch to zoom';
      });
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
              label: (item['type'] as String?) ?? 'comment',
            ),
          );
        }
      }
      setState(() {
        _imageWidthPx = widthPx;
        _imageHeightPx = heightPx;
        _markers = markers;
      });
    } catch (e) {
      debugPrint('Could not load comment markers: $e');
    }
  }

  Future<void> _goto(int page) async {
    if (page < 1 || page > _pageCount || page == _page) return;
    _page = page;
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
    _viewerSwipeStart = _viewerPointerCount == 1 ? event.position : null;
  }

  void _onViewerPointerUp(PointerEvent event) {
    _viewerPointerCount = math.max(0, _viewerPointerCount - 1);
    if (_viewerPointerCount > 0) return;
    final start = _viewerSwipeStart;
    _viewerSwipeStart = null;
    if (start == null || _busy || _doc == null) return;
    final delta = event.position - start;
    final destination = pageForSwipe(
      delta,
      currentPage: _page,
      pageCount: _pageCount,
      scale: _viewerTransform.value.getMaxScaleOnAxis(),
    );
    if (destination != null) unawaited(_goto(destination));
  }

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
        await engine.commitSave(handle: doc, token: snapshot.token);
        snapshot = null;
        final status = await engine.status(handle: doc);
        await _clearRecoveryCheckpoint();
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

  Future<void> _openAnnotate() async {
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

  Future<void> _highlightPhrase() async {
    final doc = _doc;
    final engine = _engine;
    if (doc == null || engine == null) return;
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
      if (entered != true) return;
      if (!mounted) return;
      final phrase = controller.text.trim();
      if (phrase.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enter the words you want to highlight.'),
          ),
        );
        return;
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
          return;
        }
        final matchCount = allMatches
            ? visibleMatches.length
            : matchingPages.length;
        if (!mounted) return;
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
        if (approved != true || !mounted) return;
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
        if (!mounted) return;
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
      } catch (e) {
        if (!mounted) return;
        if (latestStatus != null) _onOperationStatus(latestStatus);
        setState(() => _status = 'Highlight failed: $e');
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _openForms() async {
    final engine = _engine;
    final doc = _doc;
    if (engine == null || doc == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => FormScreen(
          engine: engine,
          handle: doc,
          onStatusChanged: _onOperationStatus,
        ),
      ),
    );
  }

  Future<void> _openSignature() async {
    final engine = _engine;
    final doc = _doc;
    if (engine == null || doc == null) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Add to this PDF',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
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
              ListTile(
                leading: const Icon(Icons.calendar_today_outlined),
                title: const Text('Place today’s date'),
                subtitle: const Text('Tap the page where it belongs'),
                onTap: () => Navigator.pop(context, 'date'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'date') {
      await _openQuickMark();
      return;
    }
    if (choice == 'draw') {
      final png = await showModalBottomSheet<Uint8List>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => const SignaturePad(),
      );
      if (!mounted || png == null || png.isEmpty) return;
      setState(() => _busy = true);
      try {
        final staged = await engine.stageFile(
          name: 'signature.png',
          bytes: png,
        );
        if (!mounted) return;
        await Navigator.push<void>(
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
      } catch (e) {
        if (!mounted) return;
        setState(() => _status = 'Signature failed: $e');
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
    if (choice == 'type') {
      final name = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => const SignatureSheet(),
      );
      if (!mounted || name == null || name.trim().isEmpty) return;
      await Navigator.push<void>(
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
    }
  }

  Future<void> _openPages() async {
    final engine = _engine;
    final doc = _doc;
    if (engine == null || doc == null) return;
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
  }

  Future<void> _openQuickMark() async {
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
        ),
      ),
    );
  }

  Future<void> _openComments() async {
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

  Future<void> _openSecure() async {
    final engine = _engine;
    final doc = _doc;
    if (engine == null || doc == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SecureSheet(
        engine: engine,
        handle: doc,
        onStatusChanged: _onOperationStatus,
      ),
    );
  }

  Future<void> _openOrganize() async {
    final engine = _engine;
    final doc = _doc;
    if (engine == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => OrganizeSheet(
        engine: engine,
        handle: doc ?? 0,
        pageCount: _pageCount,
        hasDocument: doc != null,
        onOpenPages: _openPages,
        onStatusChanged: _onOperationStatus,
      ),
    );
  }

  Future<void> _openExport() async {
    final engine = _engine;
    final doc = _doc;
    if (engine == null || doc == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => ExportSheet(
        engine: engine,
        handle: doc,
        onStatusChanged: _onOperationStatus,
      ),
    );
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

  Future<void> _openRecipes({String? initialAction}) async {
    final engine = _engine;
    final doc = _doc;
    if (engine == null || doc == null) return;
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
    if (!mounted) return;
    switch (action) {
      case 'pages':
        await _openPages();
      case 'reviewPhones':
        await _openSecure();
      case 'compress':
      case 'compare':
        await _openExport();
    }
  }

  Future<String?> _chooseSurfaceAction(
    String title,
    List<({String id, String label, String detail, IconData icon})> actions,
  ) => showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    builder: (context) => SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.82,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final action in actions)
                      ListTile(
                        leading: Icon(action.icon),
                        title: Text(action.label),
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
      ],
      1 => <({String id, String label, String detail, IconData icon})>[
        (
          id: 'draw',
          label: 'Draw & annotate',
          detail: 'Write, mark, and point directly on the page',
          icon: Icons.brush_outlined,
        ),
        (
          id: 'highlight',
          label: 'Highlight text',
          detail: 'Find a phrase and preview all matches',
          icon: Icons.highlight_outlined,
        ),
        (
          id: 'forms',
          label: 'Fill form',
          detail: 'Use full-width controls instead of tiny PDF fields',
          icon: Icons.ballot_outlined,
        ),
        (
          id: 'sign',
          label: 'Sign & date',
          detail: 'Type, draw, or place today’s date',
          icon: Icons.draw_outlined,
        ),
        (
          id: 'text',
          label: 'Edit existing text',
          detail: 'Tap a paragraph, review, then replace',
          icon: Icons.edit_outlined,
        ),
        (
          id: 'pages',
          label: 'Pages',
          detail: 'Preview, reorder, rotate, duplicate, or delete',
          icon: Icons.grid_view_outlined,
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
      case 'draw':
        await _openAnnotate();
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
    switch (request) {
      case 'phones':
      case 'dates':
        await _openRecipes(initialAction: request);
      case 'compress':
      case 'compare':
      case 'export':
      case 'ocr':
        await _openExport();
      case 'combine':
        await _openOrganize();
      case 'pages':
        await _openPages();
      case 'forms':
        await _openForms();
      case 'highlight':
        await _highlightPhrase();
      case 'secure':
        await _openSecure();
      case 'sign':
        await _openSignature();
      default:
        await _explainUnsupportedRequest(request);
    }
  }

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
      body: Stack(
        fit: StackFit.expand,
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _name == null
                            ? _status
                            : '${documentHeading(_name!, _pageCount)}${_dirty ? ' • Unsaved${_recoveryAvailable ? ' · recovery saved' : ''}' : ''}',
                        style: Theme.of(context).textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
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
              if (_finding && _doc != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: FindBar(
                    engine: _engine!,
                    handle: _doc!,
                    onJumpToPage: _goto,
                    onClose: () => setState(() => _finding = false),
                  ),
                ),
              if (_finding && _doc != null) const Divider(height: 1),
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
                          return Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: _onViewerPointerDown,
                            onPointerUp: _onViewerPointerUp,
                            onPointerCancel: _onViewerPointerCancel,
                            child: Center(
                              child: InteractiveViewer(
                                transformationController: _viewerTransform,
                                constrained: false,
                                alignment: Alignment.center,
                                minScale: 1,
                                maxScale: 8,
                                child: SizedBox(
                                  width: pageWidth,
                                  height: pageHeight,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Image.memory(
                                        _png!,
                                        fit: BoxFit.fill,
                                        gaplessPlayback: true,
                                      ),
                                      for (final marker in _markers)
                                        Positioned(
                                          left: marker.x * fitScale - 24,
                                          top: marker.y * fitScale - 24,
                                          child: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: _openComments,
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
                                                      shape: BoxShape.circle,
                                                      border: Border.all(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .primary,
                                                      ),
                                                    ),
                                                    child: Icon(
                                                      Icons.comment,
                                                      size: 17,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .primary,
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
                            onPressed: _busy ? null : () => _goto(_page - 1),
                            icon: const Icon(Icons.chevron_left),
                          ),
                          TextButton(
                            onPressed: _busy ? null : _goToPagePrompt,
                            child: Text('$_page / $_pageCount'),
                          ),
                          IconButton(
                            onPressed: _busy ? null : () => _goto(_page + 1),
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (_doc != null)
            Positioned(
              right: 16,
              bottom: 180,
              child: FloatingActionButton.extended(
                heroTag: 'pdfcraft-agent-command',
                onPressed: _busy ? null : _openAgentCommand,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Ask'),
              ),
            ),
        ],
      ),
    );
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
  const _Marker({required this.x, required this.y, required this.label});

  final double x;
  final double y;
  final String label;
}
