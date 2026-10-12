import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../bridge/api.dart' as bridge;
import '../services/pdf_engine.dart';
import 'annotation_geometry.dart';
import 'page_viewport.dart';

/// Place a typed or drawn signature with the same touch grammar as the date
/// placer: tap to preview, inspect, then explicitly place.
class SignaturePlacementPage extends StatefulWidget {
  const SignaturePlacementPage({
    super.key,
    required this.engine,
    required this.handle,
    required this.initialPage,
    required this.pageCount,
    required this.onStatusChanged,
    this.typedText,
    this.imagePath,
    this.imageBytes,
  });

  final PdfEngineApi engine;
  final int handle;
  final int initialPage;
  final int pageCount;
  final ValueChanged<bridge.DocumentStatus> onStatusChanged;
  final String? typedText;
  final String? imagePath;
  final Uint8List? imageBytes;

  @override
  State<SignaturePlacementPage> createState() => _SignaturePlacementPageState();
}

class _SignaturePlacementPageState extends State<SignaturePlacementPage> {
  static const _dpi = 96;
  late int _page = widget.initialPage;
  Uint8List? _pagePng;
  double _imageWidthPx = 0;
  double _imageHeightPx = 0;
  Offset? _draftPositionPx;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPage(_page);
  }

  Future<void> _loadPage(int page) async {
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
        _pagePng = png;
        _imageWidthPx = size.width * _dpi / 72;
        _imageHeightPx = size.height * _dpi / 72;
        _draftPositionPx = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not open page $page: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _previewAt(Offset localPosition, double fitScale) {
    if (_busy) return;
    setState(() {
      _draftPositionPx = Offset(
        localPosition.dx / fitScale,
        localPosition.dy / fitScale,
      );
      _error = null;
    });
  }

  Future<void> _place() async {
    final position = _draftPositionPx;
    if (position == null || _busy) return;
    final at = [pxToPt(position.dx, _dpi), pxToPt(position.dy, _dpi)];
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await widget.engine.executeTool(
        handle: widget.handle,
        tool: 'fill_sign_add',
        argumentsJson: jsonEncode({
          'page': _page,
          'type': 'signature',
          'at': at,
          if (widget.imagePath != null) 'path': widget.imagePath,
          if (widget.typedText != null) 'text': widget.typedText,
        }),
      );
      widget.onStatusChanged(response.status);
      final updated = await widget.engine.renderPagePng(
        handle: widget.handle,
        page1Based: _page,
        dpi: _dpi,
      );
      if (!mounted) return;
      setState(() {
        _pagePng = updated;
        _draftPositionPx = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Signature placed on page $_page.'),
          action: SnackBarAction(label: 'Undo', onPressed: _undo),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not place signature: $error');
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
      final png = await widget.engine.renderPagePng(
        handle: widget.handle,
        page1Based: _page,
        dpi: _dpi,
      );
      if (mounted) setState(() => _pagePng = png);
    } catch (error) {
      if (mounted) setState(() => _error = 'Undo failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final typedText = widget.typedText;
    final drawnImage = widget.imageBytes;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Place signature'),
        actions: [
          IconButton(
            tooltip: 'Close without placing',
            onPressed: _busy ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: _pagePng == null
                ? Center(child: Text(_error ?? 'Loading page…'))
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final fitScale = fitPageScale(
                        viewportWidth: constraints.maxWidth,
                        viewportHeight: constraints.maxHeight,
                        pageWidth: _imageWidthPx,
                        pageHeight: _imageHeightPx,
                      );
                      final width = _imageWidthPx * fitScale;
                      final height = _imageHeightPx * fitScale;
                      final position = _draftPositionPx;
                      return Center(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (details) =>
                              _previewAt(details.localPosition, fitScale),
                          child: SizedBox(
                            width: width,
                            height: height,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.memory(_pagePng!, fit: BoxFit.fill),
                                if (position != null)
                                  Positioned(
                                    left: position.dx * fitScale,
                                    top: position.dy * fitScale - 24 * fitScale,
                                    child: IgnorePointer(
                                      child: Container(
                                        constraints: BoxConstraints(
                                          maxWidth:
                                              width - position.dx * fitScale,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .tertiaryContainer,
                                          border: Border.all(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .tertiary,
                                          ),
                                        ),
                                        child: drawnImage != null
                                            ? Image.memory(
                                                drawnImage,
                                                width:
                                                    150 * _dpi / 72 * fitScale,
                                                height:
                                                    32 * _dpi / 72 * fitScale,
                                                fit: BoxFit.contain,
                                              )
                                            : Text(
                                                typedText ?? '',
                                                style: TextStyle(
                                                  fontSize: 20 * fitScale,
                                                  fontStyle: FontStyle.italic,
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
                          child: Text(
                            'Page $_page of ${widget.pageCount}',
                            textAlign: TextAlign.center,
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
                          (_draftPositionPx == null
                              ? 'Tap the page to preview the signature.'
                              : 'Check the placement. Tap elsewhere to move it.'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _busy || _draftPositionPx == null
                            ? null
                            : _place,
                        icon: const Icon(Icons.draw_outlined),
                        label: Text(
                          _draftPositionPx == null
                              ? 'Choose a position'
                              : 'Place signature',
                        ),
                      ),
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
