import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../bridge/api.dart' as bridge;
import '../services/pdf_engine.dart';
import '../services/text_edit_session.dart';
import 'page_viewport.dart';
import 'touch_session.dart';
export '../services/text_edit_session.dart' show Paragraph;

class TextEditSheet extends StatefulWidget {
  const TextEditSheet({
    super.key,
    required this.engine,
    required this.handle,
    required this.page,
    required this.png,
    required this.imageWidthPx,
    required this.imageHeightPx,
    required this.onStatusChanged,
    this.initialAddAt,
  });
  final PdfEngineApi engine;
  final int handle, page;
  final Uint8List png;
  final double imageWidthPx, imageHeightPx;
  final ValueChanged<bridge.DocumentStatus> onStatusChanged;
  final Offset? initialAddAt;
  @override
  State<TextEditSheet> createState() => _TextEditSheetState();
}

class _TextEditSheetState extends State<TextEditSheet>
    with WidgetsBindingObserver {
  late final _session = TextEditSession(
    engine: widget.engine,
    handle: widget.handle,
    page: widget.page,
  );
  late Uint8List _png = widget.png;
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _canvasKey = GlobalKey();
  double _fit = 1;
  String _lastText = '';
  final _transform = TransformationController();
  final _touch = TouchSession();
  List<Paragraph> _paragraphs = [];
  Paragraph? _selected;
  Offset? _addedAt;
  bool _adding = false, _loading = true, _committing = false, _review = false;
  bool _previewRunning = false, _promptOpen = false;
  int _revision = 0, _previewRevision = -1, _applied = 0, _paintedRevision = -1;
  TextEditPreview? _preview;
  String? _error;
  Timer? _debounce;
  double _size = 12, _width = 200, _dx = 0, _dy = 0;
  String _font = 'source', _align = 'left';
  bool? _bold;
  String? _color;
  bool _initialPlacement = true;
  bool get _hasDraft => _selected != null || _addedAt != null;
  bool get _dirty =>
      _hasDraft &&
      (_addedAt != null
          ? _text.text.isNotEmpty
          : _text.text != _selected!.text ||
                _size != _selected!.size ||
                (_width - (_selected!.rect[2] - _selected!.rect[0])).abs() >
                    .1 ||
                _dx != 0 ||
                _dy != 0 ||
                _font != 'source' ||
                _bold != null ||
                _color != null ||
                _align != 'source');
  bool get _candidateReady =>
      _dirty &&
      !_previewRunning &&
      _preview != null &&
      _previewRevision == _revision;
  bool get _ready => _candidateReady && _paintedRevision == _revision;
  String? get _layoutWarning {
    if (!_candidateReady) return null;
    if (_text.text.isEmpty) return 'This removes the selected text.';
    final normalized = _text.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final matches = _preview!.paragraphs
        .where(
          (p) => p.text.replaceAll(RegExp(r'\s+'), ' ').trim() == normalized,
        )
        .toList();
    if (matches.length != 1) return null;
    final r = matches.single.rect;
    final bounds = Rect.fromLTRB(r[0], r[1], r[2], r[3]);
    if (r[0] < 0 ||
        r[1] < 0 ||
        r[2] > _pageWidth ||
        r[3] > _pageHeight ||
        _paragraphs.any(
          (p) =>
              p.number != _selected?.number &&
              bounds.overlaps(
                Rect.fromLTRB(p.rect[0], p.rect[1], p.rect[2], p.rect[3]),
              ),
        )) {
      return 'Text may overlap nearby content or extend beyond the page. Adjust its size, position or width before applying.';
    }
    return null;
  }

  double get _pageWidth => widget.imageWidthPx * 72 / 96;
  double get _pageHeight => widget.imageHeightPx * 72 / 96;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _text.addListener(_textChanged);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _text.removeListener(_textChanged);
    _text.dispose();
    _focus.dispose();
    _transform.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _revealSelection();
    });
  }

  void _revealSelection() {
    if (!_hasDraft || _review) return;
    final box = _canvasKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final factor = _fit * 96 / 72;
    final left = (_selected?.rect[0] ?? _addedAt!.dx) + _dx;
    final top = (_selected?.rect[1] ?? _addedAt!.dy) - _dy;
    final zoom = math
        .max(
          _transform.value.getMaxScaleOnAxis(),
          14 / math.max(1, _size * factor),
        )
        .clamp(1.0, 6.0);
    final sceneWidth = widget.imageWidthPx * _fit + 24;
    final sceneHeight = widget.imageHeightPx * _fit + 24;
    final x = (box.size.width / 2 - (12 + (left + _width / 2) * factor) * zoom)
        .clamp(math.min(0.0, box.size.width - sceneWidth * zoom), 0.0);
    final y = (48 - (12 + top * factor) * zoom).clamp(
      math.min(0.0, box.size.height - sceneHeight * zoom),
      0.0,
    );
    _transform.value = Matrix4.identity()
      ..translateByDouble(x.toDouble(), y.toDouble(), 0, 1)
      ..scaleByDouble(zoom, zoom, 1, 1);
  }

  void _move(double x, double y) {
    final originalX = _selected?.rect[0] ?? _addedAt!.dx;
    final originalY = _selected?.rect[1] ?? _addedAt!.dy;
    _dx = (_dx + x).clamp(
      -originalX,
      math.max(-originalX, _pageWidth - originalX - _width),
    );
    _dy = (_dy + y).clamp(
      math.min(originalY, originalY - _pageHeight + _size),
      originalY,
    );
    _changed();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await widget.engine.status(handle: widget.handle);
      if (!status.editable) {
        throw StateError('This PDF does not allow text editing.');
      }
      final blocks = await _session.refresh();
      if (mounted) {
        setState(() => _paragraphs = blocks);
        if (widget.initialAddAt != null && _initialPlacement) {
          _initialPlacement = false;
          final at = widget.initialAddAt!;
          setState(() {
            _adding = true;
            _addedAt = at;
            _font = 'helvetica';
            _align = 'left';
            _width = math.min(200, math.max(30, _pageWidth - at.dx));
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _focus.requestFocus();
              _revealSelection();
            }
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load editable text. $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _textChanged() {
    if (_text.text == _lastText) return;
    _lastText = _text.text;
    _changed();
  }

  void _changed() {
    if (!mounted || _loading || _committing) return;
    _debounce?.cancel();
    setState(() {
      _revision++;
      _error = null;
    });
    if (_dirty) {
      _debounce = Timer(const Duration(milliseconds: 350), _makePreview);
    }
  }

  Map<String, Object?> _args() => {
    'page': widget.page, 'text': _text.text, 'size': _size, 'width': _width,
    if (_selected != null) ...{
      'paragraph': _selected!.number,
      'dx': _dx,
      'dy': _dy,
    },
    if (_addedAt != null) 'at': [_addedAt!.dx + _dx, _addedAt!.dy - _dy],
    if (_font != 'source') 'font': _font,
    if (_bold != null) 'bold': _bold,
    if (_color != null) 'color': _color,
    // Preserve source alignment until the user explicitly chooses a format.
    if (_align != 'source') 'align': _align,
  };
  Future<void> _makePreview() async {
    if (!mounted || _previewRunning || !_dirty || _committing || _loading) {
      return;
    }
    final revision = _revision;
    final tool = _selected == null ? 'page_add_text' : 'text_edit';
    final args = _args();
    setState(() => _previewRunning = true);
    try {
      final preview = await _session.preview(tool, args);
      if (mounted && revision == _revision) {
        setState(() {
          _preview = preview;
          _paintedRevision = -1;
          _previewRevision = revision;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && revision == _revision) {
        setState(
          () => _error =
              'Could not preview this edit. Your draft is still here. $e',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _previewRunning = false);
        if (revision != _revision && _dirty) {
          _debounce = Timer(const Duration(milliseconds: 100), _makePreview);
        }
      }
    }
  }

  Future<bool> _discard() async {
    if (_committing || _promptOpen) return false;
    if (!_dirty) return true;
    _promptOpen = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard this text edit?'),
        content: const Text('This draft has not been applied to your PDF.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard draft'),
          ),
        ],
      ),
    );
    _promptOpen = false;
    return discard == true;
  }

  void _clear() {
    _debounce?.cancel();
    _focus.unfocus();
    setState(() {
      _selected = null;
      _addedAt = null;
      _review = false;
      _preview = null;
      _error = null;
      _revision++;
    });
  }

  Future<void> _close() async {
    if (_loading || _committing) return;
    if (await _discard() && mounted) Navigator.pop(context);
  }

  Future<void> _select(Paragraph paragraph) async {
    if (_loading || _committing || !await _discard() || !mounted) return;
    _clear();
    setState(() {
      _selected = paragraph;
      _adding = false;
      _font = 'source';
      _align = 'source';
      _bold = null;
      _color = null;
      _size = paragraph.size;
      _width = paragraph.rect[2] - paragraph.rect[0];
      _dx = 0;
      _dy = 0;
    });
    _text.text = paragraph.text;
    _transform.value = Matrix4.identity();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focus.requestFocus();
        _revealSelection();
      }
    });
  }

  Future<void> _tap(Offset position, double scale) async {
    if (!_touch.canEdit || _loading || _committing || _hasDraft) return;
    final point = position / scale * (72 / 96);
    if (_adding) {
      setState(() {
        _addedAt = Offset(
          point.dx.clamp(0, _pageWidth - 30),
          point.dy.clamp(0, _pageHeight - 30),
        );
        _font = 'helvetica';
        _align = 'left';
        _bold = null;
        _color = null;
        _size = 12;
        _width = math.min(200, _pageWidth - _addedAt!.dx);
        _dx = 0;
        _dy = 0;
        _review = false;
      });
      _text.clear();
      _focus.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _revealSelection();
      });
      return;
    }
    // Finger tolerance is measured in screen pixels, including current zoom.
    final zoom = _transform.value.getMaxScaleOnAxis();
    final tolerance = 16 / (scale * 96 / 72 * zoom);
    final hits = _paragraphs
        .where(
          (p) => Rect.fromLTRB(
            p.rect[0],
            p.rect[1],
            p.rect[2],
            p.rect[3],
          ).inflate(tolerance).contains(point),
        )
        .toList();
    if (hits.isEmpty) return;
    final exact = hits
        .where(
          (p) => Rect.fromLTRB(
            p.rect[0],
            p.rect[1],
            p.rect[2],
            p.rect[3],
          ).contains(point),
        )
        .toList();
    if (exact.length == 1) {
      await _select(exact.single);
      return;
    }
    if (hits.length == 1) {
      await _select(hits.single);
      return;
    }
    await _browse(hits);
  }

  Future<void> _browse([List<Paragraph>? blocks]) async {
    if (_committing) return;
    final selected = await showModalBottomSheet<Paragraph>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                blocks == null
                    ? 'Choose text to edit'
                    : 'Which text did you mean?',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in blocks ?? _paragraphs)
                    ListTile(
                      title: Text(
                        p.text,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${p.font} · ${p.size.toStringAsFixed(1)} pt',
                      ),
                      onTap: () => Navigator.pop(context, p),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) await _select(selected);
  }

  Future<void> _apply() async {
    if (!_ready || !_review || _committing) return;
    final preview = _preview!;
    _focus.unfocus();
    _debounce?.cancel();
    setState(() => _committing = true);
    try {
      final status = await _session.apply(preview);
      // The route cannot be dismissed during commit. Notify the owner before refresh.
      widget.onStatusChanged(status);
      if (!mounted) return;
      _clear();
      setState(() {
        _png = preview.png;
        _paragraphs = [];
        _applied++;
      });
      await _load();
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              _error = 'Could not apply the edit. Your draft is still here. $e',
        );
      }
    } finally {
      if (mounted) setState(() => _committing = false);
    }
  }

  Future<void> _undo() async {
    if (_committing ||
        _loading ||
        _applied == 0 ||
        !await _discard() ||
        !mounted) {
      return;
    }
    _clear();
    setState(() => _committing = true);
    try {
      final response = await widget.engine.executeTool(
        handle: widget.handle,
        tool: 'edit_undo',
        argumentsJson: '{}',
      );
      widget.onStatusChanged(response.status);
      _applied--;
      final png = await widget.engine.renderPagePng(
        handle: widget.handle,
        page1Based: widget.page,
        dpi: 96,
      );
      if (!mounted) return;
      setState(() => _png = png);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not undo. $e');
    } finally {
      if (mounted) setState(() => _committing = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _close();
    },
    child: Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close text editor',
          onPressed: _committing || _loading ? null : _close,
          icon: const Icon(Icons.close),
        ),
        title: Text('Edit text · page ${widget.page}'),
        actions: [
          IconButton(
            tooltip: 'Undo text edit',
            onPressed: _applied > 0 && !_committing && !_loading ? _undo : null,
            icon: const Icon(Icons.undo),
          ),
          TextButton(
            onPressed: _committing || _loading ? null : _close,
            child: const Text('Done'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading || _previewRunning || _committing)
            const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Semantics(
                liveRegion: true,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _error!,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: _committing || _loading
                          ? null
                          : () => _hasDraft ? _makePreview() : _load(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          if (_review &&
              _previewRevision == _revision &&
              _preview?.font.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'PDF font: ${_preview!.font}. Check line breaks and nearby content.',
              ),
            ),
          if (_review && _layoutWarning != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                _layoutWarning!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(child: _canvas()),
          _toolbar(),
        ],
      ),
    ),
  );

  Widget _canvas() => LayoutBuilder(
    builder: (context, constraints) {
      // Keep document coordinates stable as the keyboard opens; reveal the selected block.
      final fit = fitPageScale(
        viewportWidth: constraints.maxWidth - 24,
        viewportHeight: _hasDraft
            ? math.max(constraints.maxHeight, widget.imageHeightPx * .45)
            : constraints.maxHeight,
        pageWidth: widget.imageWidthPx,
        pageHeight: widget.imageHeightPx,
      );
      _fit = fit;
      final factor = fit * 96 / 72;
      final p = _selected;
      final left = (p?.rect[0] ?? _addedAt?.dx ?? 0) + _dx;
      final top = (p?.rect[1] ?? _addedAt?.dy ?? 0) - _dy;
      final showInput = _hasDraft && !_review;
      return Listener(
        key: _canvasKey,
        onPointerDown: (e) => _touch.down(e.pointer),
        onPointerUp: (e) => _touch.up(e.pointer),
        onPointerCancel: (e) => _touch.cancel(e.pointer),
        child: InteractiveViewer(
          transformationController: _transform,
          minScale: 1,
          maxScale: 6,
          constrained: false,
          boundaryMargin: const EdgeInsets.all(100),
          clipBehavior: Clip.hardEdge,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: widget.imageWidthPx * fit,
              height: widget.imageHeightPx * fit,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => _tap(d.localPosition, fit),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Positioned.fill(
                      child: ColoredBox(color: Colors.white),
                    ),
                    Positioned.fill(
                      child: Image.memory(
                        _review && _candidateReady ? _preview!.png : _png,
                        fit: BoxFit.fill,
                        key: ValueKey(
                          _review && _candidateReady
                              ? 'preview-$_previewRevision'
                              : 'source-${identityHashCode(_png)}',
                        ),
                        gaplessPlayback: false,
                        frameBuilder: (context, child, frame, synchronous) {
                          if (_review &&
                              _candidateReady &&
                              frame != null &&
                              _paintedRevision != _revision) {
                            final revision = _revision;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted && revision == _revision) {
                                setState(() => _paintedRevision = revision);
                              }
                            });
                          }
                          return child;
                        },
                        semanticLabel: _review
                            ? 'PDF layout preview'
                            : 'Page ${widget.page}, tap text to edit',
                      ),
                    ),
                    if (_review && !_ready)
                      Positioned.fill(
                        child: ColoredBox(
                          color: Theme.of(context).colorScheme.surface
                              .withValues(alpha: .92),
                          child: Center(
                            child: Text(
                              _error == null ? 'Preparing PDF preview…' : 'Preview unavailable. Keep editing or retry.',
                            ),
                          ),
                        ),
                      ),
                    if (!_hasDraft)
                      for (final block in _paragraphs)
                        Positioned(
                          left: block.rect[0] * factor,
                          top: block.rect[1] * factor,
                          width: (block.rect[2] - block.rect[0]) * factor,
                          height: (block.rect[3] - block.rect[1]) * factor,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.primary
                                      .withValues(alpha: .45),
                                ),
                              ),
                            ),
                          ),
                        ),
                    if (showInput)
                      Positioned(
                        left: left * factor,
                        top: top * factor,
                        width: math.max(60, _width * factor),
                        child: TextField(
                          controller: _text,
                          focusNode: _focus,
                          enabled: !_committing,
                          minLines: 1,
                          maxLines: 6,
                          textCapitalization: TextCapitalization.sentences,
                          style: TextStyle(
                            fontSize: math.max(1, _size * factor),
                            height: 1.2,
                            fontFamily:
                                (_font == 'times' ||
                                    _font == 'source' &&
                                        (p?.font.toLowerCase().contains(
                                              'times',
                                            ) ??
                                            false))
                                ? 'serif'
                                : (_font == 'courier' ||
                                      _font == 'source' &&
                                          (p?.font.toLowerCase().contains(
                                                'courier',
                                              ) ??
                                              false))
                                ? 'monospace'
                                : null,
                            fontWeight: _bold == true
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: _color == null
                                ? Colors.black
                                : Color(
                                    int.parse(_color!.substring(1), radix: 16) |
                                        0xff000000,
                                  ),
                          ),
                          decoration: const InputDecoration(
                            filled: true,
                            fillColor: Colors.white,
                            isDense: true,
                            contentPadding: EdgeInsets.all(4),
                            border: OutlineInputBorder(),
                            hintText: 'Type text',
                          ),
                        ),
                      ),
                    if (showInput)
                      Positioned(
                        left: left * factor,
                        top: math.max(0, top * factor - 48),
                        child: Semantics(
                          label: 'Move text block',
                          child: GestureDetector(
                            onPanUpdate: (d) {
                              if (!_touch.canEdit || _committing) return;
                              _move(d.delta.dx / factor, -d.delta.dy / factor);
                            },
                            child: const SizedBox(
                              width: 48,
                              height: 48,
                              child: Icon(Icons.open_with),
                            ),
                          ),
                        ),
                      ),
                    if (showInput)
                      Positioned(
                        left: (left + _width) * factor - 24,
                        top: top * factor + 24,
                        child: Semantics(
                          label: 'Resize text width',
                          child: GestureDetector(
                            onPanUpdate: (d) {
                              if (!_touch.canEdit || _committing) return;
                              _width = (_width + d.delta.dx / factor).clamp(
                                30,
                                math.max(30, _pageWidth - left),
                              );
                              _changed();
                            },
                            child: const SizedBox(
                              width: 48,
                              height: 48,
                              child: Icon(Icons.drag_handle),
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
      );
    },
  );

  Widget _toolbar() => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _hasDraft
                  ? (_review
                        ? 'Review the PDF layout before applying.'
                        : 'Edit on the page, then review the PDF layout.')
                  : _adding
                  ? 'Tap the page where new text belongs.'
                  : _paragraphs.isEmpty
                  ? 'No editable text. Add text here, or use OCR for a scan.'
                  : 'Tap a text block to edit it.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_hasDraft) ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    DropdownButton<String>(
                      value: _font,
                      onChanged: _committing || _review
                          ? null
                          : (v) {
                              _font = v!;
                              _changed();
                            },
                      items: [
                        if (_selected != null)
                          const DropdownMenuItem(
                            value: 'source',
                            child: Text('Original font'),
                          ),
                        for (final f in ['helvetica', 'times', 'courier'])
                          DropdownMenuItem(
                            value: f,
                            child: Text(f[0].toUpperCase() + f.substring(1)),
                          ),
                      ],
                    ),
                    IconButton(
                      tooltip: 'Decrease font size',
                      onPressed: _committing || _review
                          ? null
                          : () {
                              _size = math.max(1, _size - 1);
                              _changed();
                            },
                      icon: const Icon(Icons.text_decrease),
                    ),
                    Text('${_size.toStringAsFixed(1)} pt'),
                    IconButton(
                      tooltip: 'Increase font size',
                      onPressed: _committing || _review
                          ? null
                          : () {
                              _size = math.min(200, _size + 1);
                              _changed();
                            },
                      icon: const Icon(Icons.text_increase),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Text color',
                      enabled: !_committing && !_review,
                      onSelected: (v) {
                        _color = v;
                        _changed();
                      },
                      icon: const Icon(Icons.format_color_text),
                      itemBuilder: (_) => [
                        for (final entry in {
                          '#000000': 'Black',
                          '#b3261e': 'Red',
                          '#174ea6': 'Blue',
                          '#146c2e': 'Green',
                        }.entries)
                          PopupMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                      ],
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Text alignment',
                      initialValue: _align,
                      enabled: !_committing && !_review,
                      onSelected: (v) {
                        _align = v;
                        _changed();
                      },
                      icon: const Icon(Icons.format_align_left),
                      itemBuilder: (_) => [
                        if (_selected != null)
                          const PopupMenuItem(
                            value: 'source',
                            child: Text('Original alignment'),
                          ),
                        for (final v in ['left', 'center', 'right', 'justify'])
                          PopupMenuItem(
                            value: v,
                            child: Text(v[0].toUpperCase() + v.substring(1)),
                          ),
                      ],
                    ),
                    IconButton(
                      tooltip: 'Move text left',
                      onPressed: _committing || _review
                          ? null
                          : () => _move(-4, 0),
                      icon: const Icon(Icons.arrow_left),
                    ),
                    IconButton(
                      tooltip: 'Move text right',
                      onPressed: _committing || _review
                          ? null
                          : () => _move(4, 0),
                      icon: const Icon(Icons.arrow_right),
                    ),
                    IconButton(
                      tooltip: 'Narrow text block',
                      onPressed: _committing || _review
                          ? null
                          : () {
                              _width = math.max(30, _width - 10);
                              _changed();
                            },
                      icon: const Icon(Icons.width_normal),
                    ),
                    IconButton(
                      tooltip: 'Widen text block',
                      onPressed: _committing || _review
                          ? null
                          : () {
                              _width = math.min(_pageWidth, _width + 10);
                              _changed();
                            },
                      icon: const Icon(Icons.width_wide),
                    ),
                    IconButton(
                      tooltip: 'Bold',
                      isSelected: _bold == true,
                      onPressed: _committing || _review
                          ? null
                          : () {
                              _bold = !(_bold ?? false);
                              _changed();
                            },
                      icon: const Icon(Icons.format_bold),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  TextButton(
                    onPressed: _committing
                        ? null
                        : () async {
                            if (await _discard() && mounted) _clear();
                          },
                    child: const Text('Cancel edit'),
                  ),
                  if (_review)
                    OutlinedButton(
                      onPressed: _committing
                          ? null
                          : () {
                              setState(() => _review = false);
                              _focus.requestFocus();
                            },
                      child: const Text('Keep editing'),
                    )
                  else
                    OutlinedButton(
                      onPressed: !_dirty || _committing
                          ? null
                          : () {
                              _focus.unfocus();
                              setState(() => _review = true);
                              _debounce?.cancel();
                              if (!_candidateReady) _makePreview();
                            },
                      child: const Text('Review PDF'),
                    ),
                  FilledButton(
                    onPressed: _ready && _review && !_committing
                        ? _apply
                        : null,
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ] else
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                children: [
                  TextButton.icon(
                    onPressed: _loading || _committing ? null : () => _browse(),
                    icon: const Icon(Icons.list_alt),
                    label: const Text('Browse text blocks'),
                  ),
                  TextButton.icon(
                    onPressed: _loading || _committing
                        ? null
                        : () => setState(() => _adding = !_adding),
                    icon: const Icon(Icons.add),
                    label: Text(_adding ? 'Select text' : 'Add text'),
                  ),
                ],
              ),
          ],
        ),
      ),
    ),
  );
}
