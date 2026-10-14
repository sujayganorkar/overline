import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'app_notice.dart';

import '../bridge/api.dart' as bridge;
import '../services/pdf_engine.dart';
import 'annotation_geometry.dart';

/// Crop the current page by dragging the visible box. The dashed preview is
/// exactly what the engine keeps; Apply bakes it in (undoable), Reset
/// restores the full page.
class CropPage extends StatefulWidget {
  const CropPage({
    super.key,
    required this.engine,
    required this.handle,
    required this.page,
    required this.pageCount,
    required this.png,
    required this.onStatusChanged,
  });

  final PdfEngineApi engine;
  final int handle;
  final int page;
  final int pageCount;
  final Uint8List png;
  final ValueChanged<bridge.DocumentStatus> onStatusChanged;

  @override
  State<CropPage> createState() => _CropPageState();
}

class _CropPageState extends State<CropPage> {
  static const _dpi = 96;
  late int _page = widget.page;
  late Uint8List _png = widget.png;
  double _imageWidth = 0;
  double _imageHeight = 0;
  Offset? _boxStart;
  Offset? _boxEnd;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPage(_page, keepBox: false);
  }

  Future<void> _loadPage(int page, {bool keepBox = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final png = await widget.engine.renderPagePng(
        handle: widget.handle,
        page1Based: page,
        dpi: _dpi,
      );
      final size = await widget.engine.pageSize(
        handle: widget.handle,
        page1Based: page,
      );
      if (!mounted) return;
      setState(() {
        _page = page;
        _png = png;
        _imageWidth = size.width * _dpi / 72;
        _imageHeight = size.height * _dpi / 72;
        if (!keepBox) {
          _boxStart = null;
          _boxEnd = null;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not open page $page: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Offset _pagePoint(Offset local, double scale) => Offset(
    (local.dx / scale).clamp(0.0, _imageWidth),
    (local.dy / scale).clamp(0.0, _imageHeight),
  );

  Rect? _box() {
    final start = _boxStart;
    final end = _boxEnd;
    if (start == null || end == null) return null;
    final box = Rect.fromPoints(start, end);
    if (box.width < 24 || box.height < 24) return null;
    return box;
  }

  Future<void> _apply() async {
    final box = _box();
    if (box == null || _busy) return;
    final rect = [
      pxToPt(box.left, _dpi),
      pxToPt(box.top, _dpi),
      pxToPt(box.right, _dpi),
      pxToPt(box.bottom, _dpi),
    ];
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await widget.engine.executeTool(
        handle: widget.handle,
        tool: 'page_set_box',
        argumentsJson: jsonEncode({
          'pages': [_page],
          'rect': rect,
        }),
      );
      widget.onStatusChanged(response.status);
      await _loadPage(_page);
      if (!mounted) return;
      AppNotice.show(
        context,
        AppNotice(
          message: 'Page cropped.',
          kind: NoticeKind.info,
          action: NoticeAction(label: 'Undo', onPressed: () => _undo()),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not crop: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await widget.engine.executeTool(
        handle: widget.handle,
        tool: 'page_set_box',
        argumentsJson: jsonEncode({
          'pages': [_page],
        }),
      );
      widget.onStatusChanged(response.status);
      await _loadPage(_page);
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not reset: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undo() async {
    try {
      final response = await widget.engine.executeTool(
        handle: widget.handle,
        tool: 'edit_undo',
        argumentsJson: '{}',
      );
      widget.onStatusChanged(response.status);
      await _loadPage(_page);
    } catch (error) {
      if (mounted) setState(() => _error = 'Undo failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Crop · page $_page'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _reset,
            child: const Text('Reset'),
          ),
          IconButton(
            tooltip: 'Close without cropping',
            onPressed: _busy ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (_imageWidth <= 0 || _imageHeight <= 0) {
                  return const Center(child: CircularProgressIndicator());
                }
                final scale = math.min(
                  constraints.maxWidth / _imageWidth,
                  constraints.maxHeight / _imageHeight,
                );
                final width = _imageWidth * scale;
                final height = _imageHeight * scale;
                final box = _box();
                return Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: _busy
                        ? null
                        : (details) => setState(() {
                            // Display pixels → source pixels so the engine
                            // receives top-left points, not screen positions.
                            _boxStart = _pagePoint(
                              details.localPosition,
                              scale,
                            );
                            _boxEnd = _pagePoint(details.localPosition, scale);
                            _error = null;
                          }),
                    onPanUpdate: _busy
                        ? null
                        : (details) => setState(
                            () => _boxEnd = _pagePoint(
                              details.localPosition,
                              scale,
                            ),
                          ),
                    onPanCancel: () => setState(() {
                      _boxStart = null;
                      _boxEnd = null;
                    }),
                    child: SizedBox(
                      width: width,
                      height: height,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(
                            _png,
                            fit: BoxFit.fill,
                            semanticLabel: 'Page $_page preview for cropping',
                          ),
                          if (box != null)
                            Positioned.fromRect(
                              rect: Rect.fromLTRB(
                                box.left * scale,
                                box.top * scale,
                                box.right * scale,
                                box.bottom * scale,
                              ),
                              child: Semantics(
                                label: 'Selected crop area',
                                child: IgnorePointer(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withValues(alpha: 0.15),
                                      border: Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        width: 2,
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
                );
              },
            ),
          ),
          Material(
            elevation: 6,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Previous page',
                          onPressed: _busy || _page <= 1
                              ? null
                              : () => _loadPage(_page - 1),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Expanded(
                          child: Semantics(
                            hint: 'Use previous and next page buttons to navigate',
                            child: Text(
                              'Page $_page of ${widget.pageCount}',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Next page',
                          onPressed: _busy || _page >= widget.pageCount
                              ? null
                              : () => _loadPage(_page + 1),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                    Text(
                      _error ??
                          (_box() == null
                              ? 'Drag a box around what to keep.'
                              : 'The tinted box is what stays.'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _busy || _box() == null
                                ? null
                                : () => setState(() {
                                    _boxStart = null;
                                    _boxEnd = null;
                                  }),
                            child: const Text('Clear'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _busy || _box() == null ? null : _apply,
                            icon: const Icon(Icons.crop_outlined),
                            label: const Text('Crop'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
