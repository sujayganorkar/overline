import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../bridge/api.dart' as bridge;
import '../services/pdf_engine.dart';
import 'annotation_geometry.dart' as geo;

enum AnnotateMode {
  ink,
  line,
  arrow,
  rectangle,
  oval,
  note,
  text,
  addText,
  redact,
  measure,
  select,
  link,
}

/// A text line box from `text_lines`, in top-left points.
class TextLineBox {
  const TextLineBox({required this.text, required this.rect});

  final String text;
  final List<double> rect;
}

/// Intersect a drag box with line boxes; returns one quad per touched line.
/// Quad order matches the engine: top-left, top-right, bottom-left,
/// bottom-right.
List<List<double>> selectionQuads(
  List<TextLineBox> lines,
  double x0,
  double y0,
  double x1,
  double y1,
) {
  final left = x0 < x1 ? x0 : x1;
  final top = y0 < y1 ? y0 : y1;
  final right = x0 < x1 ? x1 : x0;
  final bottom = y0 < y1 ? y1 : y0;
  final quads = <List<double>>[];
  for (final line in lines) {
    final r = line.rect;
    if (r.length != 4) continue;
    if (r[0] < right && r[2] > left && r[1] < bottom && r[3] > top) {
      quads.add([r[0], r[1], r[2], r[1], r[0], r[3], r[2], r[3]]);
    }
  }
  return quads;
}

class AnnotatePage extends StatefulWidget {
  const AnnotatePage({
    super.key,
    required this.engine,
    required this.handle,
    required this.page,
    required this.png,
    required this.imageWidthPx,
    required this.imageHeightPx,
    required this.dpi,
  });

  final PdfEngineApi engine;
  final int handle;
  final int page;
  final Uint8List png;
  final double imageWidthPx;
  final double imageHeightPx;
  final int dpi;

  @override
  State<AnnotatePage> createState() => _AnnotatePageState();
}

class _DraftShape {
  _DraftShape({required this.mode, required this.start, required this.end});

  final AnnotateMode mode;
  final Offset start;
  final Offset end;
}

class _AnnotatePageState extends State<AnnotatePage> {
  AnnotateMode _mode = AnnotateMode.ink;
  final List<geo.InkStroke> _strokes = [];
  List<Offset> _currentStroke = [];
  final List<_DraftShape> _shapes = [];
  Offset? _dragStart;
  String _color = 'red';
  double _width = 2.0;
  bool _saving = false;
  String? _error;
  ui.Image? _baseImage;
  final List<Offset> _measurePoints = [];
  String _measureKind = 'distance';
  List<TextLineBox> _textLines = const [];
  bool _linesLoading = false;
  String _selectKind = 'highlight';

  static const _tapModes = {
    AnnotateMode.note,
    AnnotateMode.text,
    AnnotateMode.addText,
  };

  @override
  void initState() {
    super.initState();
    ui.decodeImageFromList(widget.png, (image) {
      if (mounted) setState(() => _baseImage = image);
    });
  }

  static const _colors = ['red', 'yellow', 'green', 'blue', 'black'];
  static const _widths = [1.0, 2.0, 4.0, 8.0];

  void _onPanStart(DragStartDetails details, BuildContext paintContext) {
    if (_tapModes.contains(_mode)) return;
    if (_mode == AnnotateMode.measure) return;
    final box = paintContext.findRenderObject()! as RenderBox;
    final local = box.globalToLocal(details.globalPosition);
    setState(() {
      if (_mode == AnnotateMode.ink) {
        _currentStroke = [local];
      } else {
        _dragStart = local;
      }
    });
  }

  void _onTapDown(TapDownDetails details, BuildContext paintContext) {
    final box = paintContext.findRenderObject()! as RenderBox;
    final at = box.globalToLocal(details.globalPosition);
    switch (_mode) {
      case AnnotateMode.note:
        _placeNote(at);
      case AnnotateMode.text:
        _placeFillText(at);
      case AnnotateMode.addText:
        _placePageText(at);
      case AnnotateMode.measure:
        setState(() => _measurePoints.add(at));
      case AnnotateMode.select:
      case AnnotateMode.link:
        break;
      case AnnotateMode.ink:
      case AnnotateMode.line:
      case AnnotateMode.arrow:
      case AnnotateMode.rectangle:
      case AnnotateMode.oval:
      case AnnotateMode.redact:
        break;
    }
  }

  void _onPanUpdate(DragUpdateDetails details, BuildContext paintContext) {
    final box = paintContext.findRenderObject()! as RenderBox;
    final local = box.globalToLocal(details.globalPosition);
    setState(() {
      if (_mode == AnnotateMode.ink) {
        _currentStroke = [..._currentStroke, local];
      } else if (_dragStart != null) {
        _shapes
          ..removeWhere((s) => s.mode == _mode && s.start == _dragStart)
          ..add(_DraftShape(mode: _mode, start: _dragStart!, end: local));
      }
    });
  }

  void _onPanEnd() {
    setState(() {
      if (_mode == AnnotateMode.ink && _currentStroke.length > 1) {
        _strokes.add(
          geo.InkStroke(
            points: [for (final p in _currentStroke) geo.Point(p.dx, p.dy)],
            color: _color,
            width: _width,
          ),
        );
      }
      _currentStroke = [];
      _dragStart = null;
    });
  }

  Future<void> _placeNote(Offset at) async {
    final controller = TextEditingController();
    try {
      final contents = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Sticky note'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 4,
            decoration: const InputDecoration(hintText: 'Note text'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Add'),
            ),
          ],
        ),
      );
      if (contents == null || contents.trim().isEmpty || !mounted) return;
      await _execute({
        'page': widget.page,
        'type': 'note',
        'at': [geo.pxToPt(at.dx, widget.dpi), geo.pxToPt(at.dy, widget.dpi)],
        'contents': contents.trim(),
      });
    } finally {
      controller.dispose();
    }
  }

  Future<void> _placeFillText(Offset at) async {
    final controller = TextEditingController();
    try {
      final text = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Type text here'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Text to place'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Place'),
            ),
          ],
        ),
      );
      if (text == null || text.trim().isEmpty || !mounted) return;
      await _execute({
        'page': widget.page,
        'type': 'text',
        'at': [geo.pxToPt(at.dx, widget.dpi), geo.pxToPt(at.dy, widget.dpi)],
        'text': text.trim(),
      }, tool: 'fill_sign_add');
    } finally {
      controller.dispose();
    }
  }

  Future<void> _placePageText(Offset at) async {
    final controller = TextEditingController();
    try {
      final text = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Add text to page'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'Paragraph text'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Add'),
            ),
          ],
        ),
      );
      if (text == null || text.trim().isEmpty || !mounted) return;
      await _execute({
        'page': widget.page,
        'text': text.trim(),
        'at': [geo.pxToPt(at.dx, widget.dpi), geo.pxToPt(at.dy, widget.dpi)],
        'size': 12,
      }, tool: 'page_add_text');
    } finally {
      controller.dispose();
    }
  }

  Future<void> _ensureTextLines() async {
    if (_textLines.isNotEmpty || _linesLoading) return;
    setState(() => _linesLoading = true);
    try {
      final response = await widget.engine.executeTool(
        handle: widget.handle,
        tool: 'text_lines',
        argumentsJson: '{"page": ${widget.page}}',
      );
      final lines = <TextLineBox>[];
      for (final content in response.contents) {
        if (content.json.isEmpty) continue;
        final decoded = jsonDecode(content.json);
        final list = decoded is Map<String, dynamic> ? decoded['lines'] : null;
        if (list is List) {
          for (final item in list) {
            if (item is Map<String, dynamic>) {
              final rect = item['rect'];
              if (rect is List && rect.length == 4) {
                lines.add(
                  TextLineBox(
                    text: item['text'] as String? ?? '',
                    rect: [for (final v in rect) (v as num).toDouble()],
                  ),
                );
              }
            }
          }
        }
      }
      if (!mounted) return;
      setState(() => _textLines = lines);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not load text lines: $e');
    } finally {
      if (mounted) setState(() => _linesLoading = false);
    }
  }

  Future<void> _save() async {
    if (_tapModes.contains(_mode)) return;
    if (_mode == AnnotateMode.measure) {
      await _saveMeasure();
      return;
    }
    if (_mode == AnnotateMode.select) {
      await _saveSelection();
      return;
    }
    late final Map<String, Object?> args;
    String tool = 'comment_add';
    if (_mode == AnnotateMode.ink) {
      if (_strokes.isEmpty) return;
      args = geo.inkArgs(
        page: widget.page,
        strokes: _strokes,
        dpi: widget.dpi,
        color: _color,
        width: _width,
      );
    } else if (_mode == AnnotateMode.redact) {
      final shape = _latestShape();
      if (shape == null) return;
      final rect = geo.rectArgs(
        page: widget.page,
        type: 'rectangle',
        x0: shape.start.dx,
        y0: shape.start.dy,
        x1: shape.end.dx,
        y1: shape.end.dy,
        dpi: widget.dpi,
        color: _color,
        width: _width,
      );
      args = {'page': widget.page, 'rect': rect['rect']};
      tool = 'redact_mark';
    } else if (_mode == AnnotateMode.link) {
      final shape = _latestShape();
      if (shape == null) return;
      final url = await _askLinkUrl();
      if (url == null || !mounted) return;
      final left = shape.start.dx < shape.end.dx
          ? shape.start.dx
          : shape.end.dx;
      final top = shape.start.dy < shape.end.dy ? shape.start.dy : shape.end.dy;
      final right = shape.start.dx < shape.end.dx
          ? shape.end.dx
          : shape.start.dx;
      final bottom = shape.start.dy < shape.end.dy
          ? shape.end.dy
          : shape.start.dy;
      args = {
        'page': widget.page,
        'rect': [
          geo.pxToPt(left, widget.dpi),
          geo.pxToPt(top, widget.dpi),
          geo.pxToPt(right, widget.dpi),
          geo.pxToPt(bottom, widget.dpi),
        ],
        'url': url,
      };
      tool = 'link_add';
    } else {
      final shape = _shapes.isEmpty
          ? null
          : _shapes.lastWhere(
              (s) => s.mode == _mode,
              orElse: () => _shapes.last,
            );
      if (shape == null || shape.mode != _mode) return;
      final type = switch (_mode) {
        AnnotateMode.rectangle => 'rectangle',
        AnnotateMode.oval => 'oval',
        AnnotateMode.line => 'line',
        AnnotateMode.arrow => 'arrow',
        _ => 'rectangle',
      };
      args = type == 'line' || type == 'arrow'
          ? geo.lineArgs(
              page: widget.page,
              type: type,
              x0: shape.start.dx,
              y0: shape.start.dy,
              x1: shape.end.dx,
              y1: shape.end.dy,
              dpi: widget.dpi,
              color: _color,
              width: _width,
            )
          : geo.rectArgs(
              page: widget.page,
              type: type,
              x0: shape.start.dx,
              y0: shape.start.dy,
              x1: shape.end.dx,
              y1: shape.end.dy,
              dpi: widget.dpi,
              color: _color,
              width: _width,
            );
    }
    await _execute(args, tool: tool);
  }

  _DraftShape? _latestShape() {
    if (_shapes.isEmpty) return null;
    final shape = _shapes.lastWhere(
      (s) => s.mode == _mode,
      orElse: () => _shapes.last,
    );
    return shape.mode == _mode ? shape : null;
  }

  Future<void> _saveSelection() async {
    final shape = _latestShape();
    if (shape == null || _textLines.isEmpty) {
      if (_textLines.isEmpty && !_linesLoading) {
        setState(() => _error = 'No text lines on this page to select');
      }
      return;
    }
    final quads = selectionQuads(
      _textLines,
      geo.pxToPt(shape.start.dx, widget.dpi),
      geo.pxToPt(shape.start.dy, widget.dpi),
      geo.pxToPt(shape.end.dx, widget.dpi),
      geo.pxToPt(shape.end.dy, widget.dpi),
    );
    if (quads.isEmpty) {
      setState(() => _error = 'Drag over text to select it');
      return;
    }
    await _execute({'page': widget.page, 'type': _selectKind, 'quads': quads});
  }

  Future<String?> _askLinkUrl() async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Link destination'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText: 'https://example.com',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Add link'),
            ),
          ],
        ),
      ).then((value) {
        final trimmed = value?.trim();
        return trimmed == null || trimmed.isEmpty ? null : trimmed;
      });
    } finally {
      controller.dispose();
    }
  }

  Future<void> _saveMeasure() async {
    final minPoints = _measureKind == 'distance' ? 2 : 3;
    if (_measurePoints.length < minPoints) {
      setState(() => _error = 'Tap at least $minPoints points on the page');
      return;
    }
    final tool = switch (_measureKind) {
      'perimeter' => 'measure_perimeter',
      'area' => 'measure_area',
      _ => 'measure_distance',
    };
    final response = await _executeAndStay({
      'page': widget.page,
      'points': [
        for (final p in _measurePoints)
          [geo.pxToPt(p.dx, widget.dpi), geo.pxToPt(p.dy, widget.dpi)],
      ],
    }, tool: tool);
    if (response != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Measurement saved as annotation')),
      );
      setState(() => _measurePoints.clear());
    }
  }

  /// Runs a tool but stays on the overlay (used when the result is shown
  /// inline rather than by returning to the viewer).
  Future<bridge.DocumentStatus?> _executeAndStay(
    Map<String, Object?> args, {
    String tool = 'comment_add',
  }) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final response = await widget.engine.executeTool(
        handle: widget.handle,
        tool: tool,
        argumentsJson: geo.encodeArgs(args),
      );
      return response.status;
    } catch (e) {
      if (!mounted) return null;
      setState(() => _error = '$e');
      return null;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _execute(
    Map<String, Object?> args, {
    String tool = 'comment_add',
  }) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final response = await widget.engine.executeTool(
        handle: widget.handle,
        tool: 'comment_add',
        argumentsJson: geo.encodeArgs(args),
      );
      if (!mounted) return;
      Navigator.pop(context, response.status);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Annotate page ${widget.page}'),
        actions: [
          if (!_tapModes.contains(_mode))
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
        ],
      ),
      body: Column(
        children: [
          _ModeBar(
            mode: _mode,
            onChanged: (mode) {
              setState(() => _mode = mode);
              if (mode == AnnotateMode.select) _ensureTextLines();
            },
          ),
          _StyleBar(
            color: _color,
            width: _width,
            colors: _colors,
            widths: _widths,
            onColor: (c) => setState(() => _color = c),
            onWidth: (w) => setState(() => _width = w),
            onUndo: () => setState(() {
              if (_measurePoints.isNotEmpty && _mode == AnnotateMode.measure) {
                _measurePoints.removeLast();
              } else if (_strokes.isNotEmpty) {
                _strokes.removeLast();
              } else if (_shapes.isNotEmpty) {
                _shapes.removeLast();
              }
            }),
            onClear: () => setState(() {
              _strokes.clear();
              _shapes.clear();
              _measurePoints.clear();
            }),
          ),
          if (_mode == AnnotateMode.select)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectKind,
                      decoration: const InputDecoration(
                        labelText: 'Mark selected text as',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'highlight',
                          child: Text('Highlight'),
                        ),
                        DropdownMenuItem(
                          value: 'underline',
                          child: Text('Underline'),
                        ),
                        DropdownMenuItem(
                          value: 'strikeout',
                          child: Text('Strikethrough'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _selectKind = v);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _linesLoading
                        ? 'Loading text…'
                        : '${_textLines.length} lines',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          if (_mode == AnnotateMode.measure)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _measureKind,
                      decoration: const InputDecoration(
                        labelText: 'Measurement',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'distance',
                          child: Text('Distance (2+ points)'),
                        ),
                        DropdownMenuItem(
                          value: 'perimeter',
                          child: Text('Perimeter (3+ points)'),
                        ),
                        DropdownMenuItem(
                          value: 'area',
                          child: Text('Area (3+ points)'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() {
                            _measureKind = v;
                            _measurePoints.clear();
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_measurePoints.length} pts',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: _baseImage == null
                ? const Center(child: CircularProgressIndicator())
                : InteractiveViewer(
                    maxScale: 8,
                    child: Center(
                      child: Builder(
                        builder: (paintContext) => GestureDetector(
                          onTapDown: (d) => _onTapDown(d, paintContext),
                          onPanStart: (d) => _onPanStart(d, paintContext),
                          onPanUpdate: (d) => _onPanUpdate(d, paintContext),
                          onPanEnd: (_) => _onPanEnd(),
                          child: CustomPaint(
                            size: Size(
                              widget.imageWidthPx,
                              widget.imageHeightPx,
                            ),
                            painter: _DraftPainter(
                              baseImage: _baseImage!,
                              strokes: _strokes,
                              currentStroke: _currentStroke,
                              shapes: _shapes,
                              measurePoints: _measurePoints,
                              textLinesPx: [
                                for (final line in _textLines)
                                  if (line.rect.length == 4)
                                    Rect.fromLTRB(
                                      geo.ptToPx(line.rect[0], widget.dpi),
                                      geo.ptToPx(line.rect[1], widget.dpi),
                                      geo.ptToPx(line.rect[2], widget.dpi),
                                      geo.ptToPx(line.rect[3], widget.dpi),
                                    ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ModeBar extends StatelessWidget {
  const _ModeBar({required this.mode, required this.onChanged});

  final AnnotateMode mode;
  final ValueChanged<AnnotateMode> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(AnnotateMode m, String label, IconData icon) {
      return ChoiceChip(
        label: Text(label),
        avatar: Icon(icon, size: 16),
        selected: mode == m,
        onSelected: (_) => onChanged(m),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          chip(AnnotateMode.ink, 'Draw', Icons.brush),
          const SizedBox(width: 6),
          chip(AnnotateMode.line, 'Line', Icons.remove),
          const SizedBox(width: 6),
          chip(AnnotateMode.arrow, 'Arrow', Icons.arrow_forward),
          const SizedBox(width: 6),
          chip(AnnotateMode.rectangle, 'Rect', Icons.rectangle_outlined),
          const SizedBox(width: 6),
          chip(AnnotateMode.oval, 'Oval', Icons.circle_outlined),
          const SizedBox(width: 6),
          chip(AnnotateMode.note, 'Note', Icons.sticky_note_2_outlined),
          const SizedBox(width: 6),
          chip(AnnotateMode.text, 'Text', Icons.text_fields_outlined),
          const SizedBox(width: 6),
          chip(AnnotateMode.addText, 'AddText', Icons.title_outlined),
          const SizedBox(width: 6),
          chip(AnnotateMode.redact, 'Redact', Icons.visibility_off_outlined),
          const SizedBox(width: 6),
          chip(AnnotateMode.measure, 'Measure', Icons.straighten_outlined),
          const SizedBox(width: 6),
          chip(AnnotateMode.select, 'Select', Icons.select_all),
          const SizedBox(width: 6),
          chip(AnnotateMode.link, 'Link', Icons.link_outlined),
        ],
      ),
    );
  }
}

class _StyleBar extends StatelessWidget {
  const _StyleBar({
    required this.color,
    required this.width,
    required this.colors,
    required this.widths,
    required this.onColor,
    required this.onWidth,
    required this.onUndo,
    required this.onClear,
  });

  final String color;
  final double width;
  final List<String> colors;
  final List<double> widths;
  final ValueChanged<String> onColor;
  final ValueChanged<double> onWidth;
  final VoidCallback onUndo;
  final VoidCallback onClear;

  static const _swatches = {
    'red': Colors.red,
    'yellow': Colors.yellow,
    'green': Colors.green,
    'blue': Colors.blue,
    'black': Colors.black,
  };

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          for (final name in colors)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ChoiceChip(
                label: Text(name),
                avatar: CircleAvatar(
                  radius: 7,
                  backgroundColor: _swatches[name],
                ),
                selected: color == name,
                onSelected: (_) => onColor(name),
              ),
            ),
          const SizedBox(width: 8),
          DropdownButton<double>(
            value: width,
            items: [
              for (final w in widths)
                DropdownMenuItem(value: w, child: Text('${w.toInt()} pt')),
            ],
            onChanged: (w) {
              if (w != null) onWidth(w);
            },
          ),
          IconButton(
            onPressed: onUndo,
            icon: const Icon(Icons.undo),
            tooltip: 'Undo last',
          ),
          IconButton(
            onPressed: onClear,
            icon: const Icon(Icons.clear_all),
            tooltip: 'Clear all',
          ),
        ],
      ),
    );
  }
}

class _DraftPainter extends CustomPainter {
  _DraftPainter({
    required this.baseImage,
    required this.strokes,
    required this.currentStroke,
    required this.shapes,
    required this.measurePoints,
    required this.textLinesPx,
  });

  final ui.Image baseImage;
  final List<geo.InkStroke> strokes;
  final List<Offset> currentStroke;
  final List<_DraftShape> shapes;
  final List<Offset> measurePoints;
  final List<Rect> textLinesPx;

  static const _swatches = {
    'red': Colors.red,
    'yellow': Colors.yellow,
    'green': Colors.green,
    'blue': Colors.blue,
    'black': Colors.black,
  };

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImage(baseImage, Offset.zero, Paint());
    for (final stroke in strokes) {
      _paintStroke(canvas, stroke);
    }
    if (currentStroke.length > 1) {
      final paint = Paint()
        ..color = Colors.red
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final path = Path()
        ..moveTo(currentStroke.first.dx, currentStroke.first.dy);
      for (final p in currentStroke.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
    for (final shape in shapes) {
      _paintShape(canvas, shape);
    }
    for (final shape in shapes) {
      if (shape.mode != AnnotateMode.select) continue;
      final box = Rect.fromPoints(shape.start, shape.end);
      canvas.drawRect(
        box,
        Paint()
          ..color = Colors.blue.withValues(alpha: 0.15)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRect(
        box,
        Paint()
          ..color = Colors.blue
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
      final highlight = Paint()
        ..color = Colors.yellow.withValues(alpha: 0.4)
        ..style = PaintingStyle.fill;
      for (final line in textLinesPx) {
        if (line.overlaps(box)) canvas.drawRect(line, highlight);
      }
    }
    if (measurePoints.isNotEmpty) {
      final paint = Paint()
        ..color = Colors.blue
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      for (final p in measurePoints) {
        canvas.drawCircle(p, 7, paint);
      }
      if (measurePoints.length > 1) {
        final path = Path()
          ..moveTo(measurePoints.first.dx, measurePoints.first.dy);
        for (final p in measurePoints.skip(1)) {
          path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path, paint);
      }
    }
  }

  void _paintStroke(Canvas canvas, geo.InkStroke stroke) {
    if (stroke.points.length < 2) return;
    final paint = Paint()
      ..color = (_swatches[stroke.color] ?? Colors.red).withValues(alpha: 0.7)
      ..strokeWidth = stroke.width * 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path()..moveTo(stroke.points.first.x, stroke.points.first.y);
    for (final p in stroke.points.skip(1)) {
      path.lineTo(p.x, p.y);
    }
    canvas.drawPath(path, paint);
  }

  void _paintShape(Canvas canvas, _DraftShape shape) {
    final paint = Paint()
      ..color = Colors.red.withValues(alpha: 0.7)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    final rect = Rect.fromPoints(shape.start, shape.end);
    switch (shape.mode) {
      case AnnotateMode.rectangle:
        canvas.drawRect(rect, paint);
      case AnnotateMode.redact:
        canvas.drawRect(
          rect,
          Paint()
            ..color = Colors.red.withValues(alpha: 0.25)
            ..style = PaintingStyle.fill,
        );
        canvas.drawRect(rect, paint);
      case AnnotateMode.oval:
        canvas.drawOval(rect, paint);
      case AnnotateMode.line:
        canvas.drawLine(shape.start, shape.end, paint);
      case AnnotateMode.arrow:
        canvas.drawLine(shape.start, shape.end, paint);
        final angle = (shape.end - shape.start).direction;
        const head = 18.0;
        canvas.drawLine(
          shape.end,
          shape.end - Offset(head * 1.0, 0).rotate(angle - 0.45),
          paint,
        );
        canvas.drawLine(
          shape.end,
          shape.end - Offset(head * 1.0, 0).rotate(angle + 0.45),
          paint,
        );
      case AnnotateMode.ink:
      case AnnotateMode.note:
      case AnnotateMode.text:
      case AnnotateMode.addText:
      case AnnotateMode.measure:
      case AnnotateMode.select:
      case AnnotateMode.link:
        break;
    }
  }

  @override
  bool shouldRepaint(_DraftPainter old) => true;
}

extension on Offset {
  Offset rotate(double angle) {
    final c = math.cos(angle);
    final s = math.sin(angle);
    return Offset(dx * c - dy * s, dx * s + dy * c);
  }
}
