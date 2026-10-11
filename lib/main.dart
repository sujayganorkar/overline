import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';

import 'bridge/api.dart' as bridge;
import 'services/pdf_engine.dart';
import 'widgets/document_heading.dart';
import 'widgets/operation_browser.dart';

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

class _ViewerPageState extends State<ViewerPage> {
  PdfEngineApi? _engine;
  int? _doc;
  int _pageCount = 0;
  int _page = 1; // 1-based
  Uint8List? _png;
  String? _name;
  String _status = 'Starting engine';
  bool _busy = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
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
        _status = 'Opened ${file.name}';
      });
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
    if (!mounted) return false;
    setState(() {
      _doc = null;
      _name = null;
      _pageCount = 0;
      _page = 1;
      _png = null;
      _dirty = false;
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
    setState(() {
      _busy = true;
      _status = 'Rendering page $_page\u2026';
    });
    try {
      final png = await engine.renderPagePng(
        handle: doc,
        page1Based: _page,
        dpi: 96,
      );
      if (!mounted) return;
      setState(() {
        _png = png;
        _status = 'Page $_page of $_pageCount';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Render failed: $e');
      _png = null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _goto(int page) async {
    if (page < 1 || page > _pageCount || page == _page) return;
    _page = page;
    await _render();
  }

  Future<void> _save() async {
    final doc = _doc;
    final engine = _engine;
    if (doc == null || engine == null || _name == null) return;
    bridge.SaveSnapshot? snapshot;
    var externalSaved = false;
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
        if (!mounted) return;
        setState(() {
          _dirty = status.dirty;
          _status = 'Saved to $uri';
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Saved to $uri')));
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

  Future<void> _showOperations() async {
    final engine = _engine;
    final doc = _doc;
    if (engine == null || doc == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => OperationBrowser(
        engine: engine,
        handle: doc,
        onStatusChanged: _onOperationStatus,
      ),
    );
  }

  void _onOperationStatus(bridge.DocumentStatus status) {
    if (!mounted) return;
    setState(() {
      _pageCount = status.pageCount;
      _dirty = status.dirty;
      if (_page > _pageCount && _pageCount > 0) _page = _pageCount;
      _status = status.dirty ? 'Unsaved changes' : 'Operation complete';
      if (status.pageCount == 0) _png = null;
    });
    if (_pageCount > 0) unawaited(_render());
  }

  @override
  void dispose() {
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
              onPressed: _busy ? null : _showOperations,
              icon: const Icon(Icons.build_outlined),
              tooltip: 'Editing tools',
            ),
          if (_doc != null)
            IconButton(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.save),
              tooltip: 'Save (engine incremental save)',
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
                  child: Text(
                    _name == null
                        ? _status
                        : '${documentHeading(_name!, _pageCount)}${_dirty ? ' • Unsaved' : ''}',
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
          Expanded(
            child: _png == null
                ? Center(child: Text(_status))
                : InteractiveViewer(
                    maxScale: 8,
                    child: Center(
                      child: Image.memory(_png!, gaplessPlayback: true),
                    ),
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                      Text('$_page / $_pageCount'),
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
      floatingActionButton: FloatingActionButton(
        onPressed: _busy ? null : _open,
        tooltip: 'Open PDF',
        child: const Icon(Icons.folder_open),
      ),
    );
  }
}
