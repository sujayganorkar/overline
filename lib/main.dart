import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'bridge/api.dart';
import 'bridge/frb_generated.dart';

void main() {
  runApp(const PdfCraftApp());
}

class PdfCraftApp extends StatelessWidget {
  const PdfCraftApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PdfCraft Mobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const ViewerPage(),
    );
  }
}

class ViewerPage extends StatefulWidget {
  const ViewerPage({super.key});

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  Engine? _engine;
  int? _doc;
  int _pageCount = 0;
  int _page = 1; // 1-based
  Uint8List? _png;
  String? _name;
  String _status = 'Starting engine';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _initEngine();
  }

  Future<void> _initEngine() async {
    try {
      await RustLib.init();
      if (!mounted) return;
      setState(() {
        _engine = Engine();
        _status = 'Engine ready (PdfCraft Rust core)';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Engine init failed: $e');
    }
  }

  Future<void> _open() async {
    final files = await FilePickerPlatform.instance.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final file = files.isNotEmpty ? files.first : null;
    if (file == null) return;
    final fileBytes = await file.readAsBytes();
    if (fileBytes.isEmpty) return;
    setState(() {
      _busy = true;
      _status = 'Opening ${file.name}\u2026';
    });
    try {
      final engine = _engine;
      if (engine == null) throw StateError('engine not initialized');
      final doc = await engine.open(name: file.name, bytes: fileBytes, password: null);
      final count = await engine.pageCount(handle: doc);
      if (!mounted) return;
      setState(() {
        _doc = doc;
        _name = file.name;
        _pageCount = count;
        _page = 1;
        _status = 'Opened ${file.name}';
      });
      await _render();
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Open failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
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
      final png = await engine.renderPagePng(handle: doc, page1Based: _page, dpi: 96);
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
    setState(() => _busy = true);
    try {
      final bytes = await engine.save(handle: doc);
      final dir = await getApplicationDocumentsDirectory();
      final out = File('${dir.path}/$_name');
      await out.writeAsBytes(bytes);
      if (!mounted) return;
      setState(() => _status = 'Saved ${bytes.length} bytes to ${out.path}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved to ${out.path}')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Save failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PdfCraft Mobile'),
        actions: [
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
                    _name == null ? _status : '$_name - $_pageCount page${_pageCount == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_busy) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _png == null
                ? Center(child: Text(_status))
                : InteractiveViewer(
                    maxScale: 8,
                    child: Center(child: Image.memory(_png!, gaplessPlayback: true)),
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(_status, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
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
