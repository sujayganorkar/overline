import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'app_notice.dart';

import '../bridge/api.dart' as bridge;
import '../services/pdf_engine.dart';
import 'annotation_geometry.dart';

/// Place a date (or a check/cross/dot/line mark) with a single deliberate
/// tap on the visible page. The full page remains the target (rather than a
/// tiny PDF field); the date preview uses the same engine preference that
/// will be applied at the tap point. Pass [markType] (one of check, cross,
/// dot, line) with a [markLabel] to place a mark instead of a date.
class QuickMarkPage extends StatefulWidget {
  const QuickMarkPage({
    super.key,
    required this.engine,
    required this.handle,
    required this.page,
    required this.pageCount,
    required this.png,
    required this.onStatusChanged,
    this.markType,
    this.markLabel,
  });

  final PdfEngineApi engine;
  final int handle;
  final int page;
  final int pageCount;
  final Uint8List png;
  final ValueChanged<bridge.DocumentStatus> onStatusChanged;
  final String? markType;
  final String? markLabel;

  @override
  State<QuickMarkPage> createState() => _QuickMarkPageState();
}

class _QuickMarkPageState extends State<QuickMarkPage> {
  static const _dpi = 96;
  late int _page = widget.page;
  late Uint8List _png = widget.png;
  double _imageWidth = 0;
  double _imageHeight = 0;
  String? _datePreview;
  String? _error;
  Offset? _draftImagePosition;
  bool _busy = false;

  bool get _isDate => widget.markType == null;

  String get _noun => _isDate ? 'date' : 'mark';

  @override
  void initState() {
    super.initState();
    if (_isDate) {
      _loadDatePreference();
    } else {
      _datePreview = widget.markLabel ?? widget.markType;
    }
    _loadDimensions();
  }

  Future<void> _loadDatePreference() async {
    try {
      final result = await widget.engine.executeTool(
        handle: widget.handle,
        tool: 'fill_sign_date_format',
        argumentsJson: '{}',
      );
      final source = result.contents
          .where((content) => content.json.isNotEmpty)
          .map((content) => content.json)
          .firstOrNull;
      if (source == null) throw StateError('Date preference was empty');
      final data = jsonDecode(source);
      final today = data is Map<String, dynamic> ? data['today'] : null;
      if (today is! String || today.isEmpty) {
        throw StateError('Could not read today’s date from PdfCraft');
      }
      if (mounted) setState(() => _datePreview = today);
    } catch (error) {
      if (mounted) setState(() => _error = 'Date preview unavailable: $error');
    }
  }

  Future<void> _loadDimensions() async {
    try {
      final size = await widget.engine.pageSize(
        handle: widget.handle,
        page1Based: _page,
      );
      if (!mounted) return;
      setState(() {
        _imageWidth = size.width * _dpi / 72;
        _imageHeight = size.height * _dpi / 72;
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not size page: $error');
    }
  }

  Future<void> _goTo(int page) async {
    if (page < 1 || page > widget.pageCount || page == _page || _busy) return;
    setState(() => _busy = true);
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
        _draftImagePosition = null;
        _imageWidth = size.width * _dpi / 72;
        _imageHeight = size.height * _dpi / 72;
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not open page $page: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _selectPosition(Offset localPosition, Size displayedSize) {
    if (_busy || _datePreview == null) return;
    setState(() {
      _draftImagePosition = Offset(
        localPosition.dx * _imageWidth / displayedSize.width,
        localPosition.dy * _imageHeight / displayedSize.height,
      );
      _error = null;
    });
  }

  Future<void> _placeDate() async {
    final position = _draftImagePosition;
    if (_busy || _datePreview == null || position == null) return;
    final x = pxToPt(position.dx, _dpi);
    final y = pxToPt(position.dy, _dpi);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.engine.executeTool(
        handle: widget.handle,
        tool: 'fill_sign_add',
        argumentsJson: jsonEncode({
          'page': _page,
          'type': widget.markType ?? 'date',
          'at': [x, y],
        }),
      );
      widget.onStatusChanged(result.status);
      final updated = await widget.engine.renderPagePng(
        handle: widget.handle,
        page1Based: _page,
        dpi: _dpi,
      );
      if (!mounted) return;
      setState(() {
        _png = updated;
        _draftImagePosition = null;
      });
      AppNotice.show(
        context,
        AppNotice(
          message: 'Placed $_datePreview on page $_page.',
          kind: NoticeKind.success,
          action: NoticeAction(label: 'Undo', onPressed: _undoPlacement),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _error =
              '${_noun[0].toUpperCase()}${_noun.substring(1)} was not placed: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undoPlacement() async {
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
      if (mounted) setState(() => _png = png);
    } catch (error) {
      if (mounted) setState(() => _error = 'Undo failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isDate ? 'Place a date' : 'Place a ${widget.markLabel ?? 'mark'}',
        ),
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
                final displayedSize = Size(width, height);
                return InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 6.0,
                  clipBehavior: Clip.hardEdge,
                  child: Center(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (details) =>
                          _selectPosition(details.localPosition, displayedSize),
                      child: SizedBox(
                        width: width,
                        height: height,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.memory(_png, fit: BoxFit.fill),
                            if (_draftImagePosition case final position?)
                              Positioned(
                                left: position.dx * width / _imageWidth,
                                top: position.dy * height / _imageHeight,
                                child: Transform.translate(
                                  offset: const Offset(-8, -24),
                                  child: IgnorePointer(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .tertiaryContainer,
                                        borderRadius: BorderRadius.circular(5),
                                        border: Border.all(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .tertiary,
                                        ),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 3,
                                        ),
                                        child: Text(
                                          _datePreview ?? '',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium,
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
          Material(
            elevation: 6,
            color: Theme.of(context).colorScheme.surface,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Previous page',
                          onPressed: _busy || _page <= 1
                              ? null
                              : () => _goTo(_page - 1),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Text('Page $_page of ${widget.pageCount}'),
                              const SizedBox(height: 4),
                              Text(
                                _datePreview ??
                                    (_isDate
                                        ? 'Loading today’s date…'
                                        : 'Loading…'),
                                style: Theme.of(context).textTheme.titleMedium,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Next page',
                          onPressed: _busy || _page >= widget.pageCount
                              ? null
                              : () => _goTo(_page + 1),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                    Text(
                      _error ??
                          (_draftImagePosition == null
                              ? 'Tap the page to preview the $_noun placement.'
                              : 'Review the preview, then place it or tap a new spot.'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed:
                            _busy ||
                                _datePreview == null ||
                                _draftImagePosition == null
                            ? null
                            : _placeDate,
                        icon: const Icon(Icons.place_outlined),
                        label: Text(
                          _draftImagePosition == null
                              ? 'Choose a position on the page'
                              : 'Place $_noun here',
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
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
