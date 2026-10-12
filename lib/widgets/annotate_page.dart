import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';

import '../bridge/api.dart' as bridge;
import '../services/pdf_engine.dart';
import 'annotation_geometry.dart' as geo;
import 'page_viewport.dart';

enum AnnotateMode {
  pan,
  ink,
  line,
  arrow,
  rectangle,
  oval,
  note,
  text,
  addText,
  stamp,
  image,
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

List<double> _lineQuad(List<double> rect) => [
  rect[0],
  rect[1],
  rect[2],
  rect[1],
  rect[0],
  rect[3],
  rect[2],
  rect[3],
];

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
    this.initialMode = AnnotateMode.ink,
  });

  final PdfEngineApi engine;
  final int handle;
  final int page;
  final Uint8List png;
  final double imageWidthPx;
  final double imageHeightPx;
  final int dpi;
  final AnnotateMode initialMode;

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
  int? _selectionAnchorLine;
  int? _selectionExtentLine;

  bool get _dedicatedMode =>
      widget.initialMode == AnnotateMode.note ||
      widget.initialMode == AnnotateMode.select;

  /// Open variant strip: shapes or the overflow tools. Only one at a time.
  String? _variantStrip;

  static const _shapeModes = [
    AnnotateMode.line,
    AnnotateMode.arrow,
    AnnotateMode.rectangle,
    AnnotateMode.oval,
  ];

  static const _overflowModes = [
    AnnotateMode.addText,
    AnnotateMode.stamp,
    AnnotateMode.image,
    AnnotateMode.redact,
    AnnotateMode.link,
  ];

  bool get _inShapes => _shapeModes.contains(_mode);

  bool get _inOverflow => _overflowModes.contains(_mode);

  void _pickTool(AnnotateMode mode) {
    setState(() {
      _mode = mode;
      _variantStrip = null;
      if (mode == AnnotateMode.select) _ensureTextLines();
    });
  }

  void _pickShape(AnnotateMode mode) {
    setState(() {
      _mode = mode;
      if (mode == AnnotateMode.select) _ensureTextLines();
    });
  }

  String _shapeLabel(AnnotateMode mode) => switch (mode) {
    AnnotateMode.line => 'Line',
    AnnotateMode.arrow => 'Arrow',
    AnnotateMode.oval => 'Oval',
    _ => 'Rect',
  };

  IconData _shapeIcon(AnnotateMode mode) => switch (mode) {
    AnnotateMode.line => Icons.remove,
    AnnotateMode.arrow => Icons.arrow_forward,
    AnnotateMode.oval => Icons.circle_outlined,
    _ => Icons.rectangle_outlined,
  };

  String _overflowLabel(AnnotateMode mode) => switch (mode) {
    AnnotateMode.addText => 'Page text',
    AnnotateMode.stamp => 'Stamp',
    AnnotateMode.image => 'Picture',
    AnnotateMode.redact => 'Redact',
    _ => 'Link',
  };

  IconData _overflowIcon(AnnotateMode mode) => switch (mode) {
    AnnotateMode.addText => Icons.title_outlined,
    AnnotateMode.stamp => Icons.approval_outlined,
    AnnotateMode.image => Icons.image_outlined,
    AnnotateMode.redact => Icons.visibility_off_outlined,
    _ => Icons.link_outlined,
  };

  static const _tapModes = {
    AnnotateMode.note,
    AnnotateMode.text,
    AnnotateMode.addText,
    AnnotateMode.stamp,
    AnnotateMode.image,
  };

  static const _standardStamps = [
    'approved',
    'completed',
    'confidential',
    'draft',
    'final',
    'for comment',
    'for public release',
    'information only',
    'not approved',
    'not for public release',
    'preliminary results',
    'void',
    'accepted',
    'initial here',
    'rejected',
    'sign here',
    'witness',
  ];

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    ui.decodeImageFromList(widget.png, (image) {
      if (mounted) setState(() => _baseImage = image);
    });
    if (_mode == AnnotateMode.select) _ensureTextLines();
  }

  static const _colors = ['red', 'yellow', 'green', 'blue', 'black'];
  static const _widths = [1.0, 2.0, 4.0, 8.0];

  void _onPanStart(
    DragStartDetails details,
    BuildContext paintContext,
    double fitScale,
  ) {
    if (_tapModes.contains(_mode) ||
        _mode == AnnotateMode.select ||
        _mode == AnnotateMode.pan) {
      return;
    }
    if (_mode == AnnotateMode.measure) return;
    final box = paintContext.findRenderObject()! as RenderBox;
    final display = box.globalToLocal(details.globalPosition);
    final local = Offset(display.dx / fitScale, display.dy / fitScale);
    setState(() {
      if (_mode == AnnotateMode.ink) {
        _currentStroke = [local];
      } else {
        _dragStart = local;
      }
    });
  }

  void _onTapDown(
    TapDownDetails details,
    BuildContext paintContext,
    double fitScale,
  ) {
    if (_mode == AnnotateMode.select || _mode == AnnotateMode.pan) return;
    final box = paintContext.findRenderObject()! as RenderBox;
    final display = box.globalToLocal(details.globalPosition);
    final at = Offset(display.dx / fitScale, display.dy / fitScale);
    switch (_mode) {
      case AnnotateMode.pan:
        break;
      case AnnotateMode.note:
        _placeNote(at);
      case AnnotateMode.text:
        _placeFillText(at);
      case AnnotateMode.addText:
        _placePageText(at);
      case AnnotateMode.stamp:
        _placeStamp(at);
      case AnnotateMode.image:
        _placeImage(at);
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

  int? _nearestTextLine(Offset sourcePixels) {
    var bestIndex = -1;
    var bestDistance = double.infinity;
    for (var index = 0; index < _textLines.length; index++) {
      final rect = _lineRectPixels(_textLines[index]);
      final dx = sourcePixels.dx < rect.left
          ? rect.left - sourcePixels.dx
          : sourcePixels.dx > rect.right
          ? sourcePixels.dx - rect.right
          : 0.0;
      final dy = sourcePixels.dy < rect.top
          ? rect.top - sourcePixels.dy
          : sourcePixels.dy > rect.bottom
          ? sourcePixels.dy - rect.bottom
          : 0.0;
      final distance = dx * dx + dy * dy;
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = index;
      }
    }
    return bestIndex >= 0 && bestDistance <= 84 * 84 ? bestIndex : null;
  }

  Rect _lineRectPixels(TextLineBox line) => Rect.fromLTRB(
    geo.ptToPx(line.rect[0], widget.dpi),
    geo.ptToPx(line.rect[1], widget.dpi),
    geo.ptToPx(line.rect[2], widget.dpi),
    geo.ptToPx(line.rect[3], widget.dpi),
  );

  List<Rect> _selectedLineRects() {
    final anchor = _selectionAnchorLine;
    final extent = _selectionExtentLine;
    if (anchor == null || extent == null || _textLines.isEmpty) return const [];
    final start = math.min(anchor, extent);
    final end = math.max(anchor, extent);
    return [
      for (var index = start; index <= end; index++)
        _lineRectPixels(_textLines[index]),
    ];
  }

  void _startTextSelection(LongPressStartDetails details, double fitScale) {
    if (_mode != AnnotateMode.select || _linesLoading) return;
    final point = Offset(
      details.localPosition.dx / fitScale,
      details.localPosition.dy / fitScale,
    );
    final line = _nearestTextLine(point);
    if (line == null) {
      setState(() => _error = 'Press on selectable text to start a selection.');
      return;
    }
    setState(() {
      _selectionAnchorLine = line;
      _selectionExtentLine = line;
      _error = null;
    });
  }

  void _extendTextSelection(
    LongPressMoveUpdateDetails details,
    double fitScale,
  ) {
    if (_mode != AnnotateMode.select || _selectionAnchorLine == null) return;
    final point = Offset(
      details.localPosition.dx / fitScale,
      details.localPosition.dy / fitScale,
    );
    final line = _nearestTextLine(point);
    if (line != null) setState(() => _selectionExtentLine = line);
  }

  void _moveSelectionHandle({
    required DragUpdateDetails details,
    required BuildContext paintContext,
    required double fitScale,
    required bool anchor,
  }) {
    final box = paintContext.findRenderObject();
    if (box is! RenderBox) return;
    final display = box.globalToLocal(details.globalPosition);
    final line = _nearestTextLine(
      Offset(display.dx / fitScale, display.dy / fitScale),
    );
    if (line == null) return;
    setState(() {
      if (anchor) {
        _selectionAnchorLine = line;
      } else {
        _selectionExtentLine = line;
      }
    });
  }

  void _onPanUpdate(
    DragUpdateDetails details,
    BuildContext paintContext,
    double fitScale,
  ) {
    if (_mode == AnnotateMode.select || _mode == AnnotateMode.pan) return;
    final box = paintContext.findRenderObject()! as RenderBox;
    final display = box.globalToLocal(details.globalPosition);
    final local = Offset(display.dx / fitScale, display.dy / fitScale);
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
    if (_mode == AnnotateMode.pan) return;
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
          title: const Text('Add a note'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Note text',
              hintText: 'Enter note contents',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Add note'),
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
            decoration: const InputDecoration(
              labelText: 'Text to place',
              hintText: 'Enter text to place on page',
            ),
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
            decoration: const InputDecoration(
              labelText: 'Paragraph text',
              hintText: 'Enter paragraph text to add',
            ),
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

  Future<void> _placeStamp(Offset at) async {
    final stamp = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final name in _standardStamps)
              ListTile(
                title: Text(
                  name.replaceAllMapped(
                    RegExp(r'\b[a-z]'),
                    (m) => m.group(0)!.toUpperCase(),
                  ),
                ),
                onTap: () => Navigator.pop(context, name),
              ),
          ],
        ),
      ),
    );
    if (stamp == null || !mounted) return;
    await _execute({
      'page': widget.page,
      'type': 'stamp',
      'stamp': stamp,
      'at': [geo.pxToPt(at.dx, widget.dpi), geo.pxToPt(at.dy, widget.dpi)],
    });
  }

  Future<void> _placeImage(Offset at) async {
    final picked = await FilePickerPlatform.instance.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'tif', 'tiff', 'gif', 'bmp'],
      dialogTitle: 'Choose a picture to place',
    );
    if (picked.isEmpty || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final file = picked.first;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) throw StateError('${file.name} is empty');
      final staged = await widget.engine.stageFile(
        name: 'stamp-${file.name}',
        bytes: bytes,
      );
      if (!mounted) return;
      final x = geo.pxToPt(at.dx, widget.dpi);
      final y = geo.pxToPt(at.dy, widget.dpi);
      await _execute({
        'page': widget.page,
        'path': staged,
        'rect': [x - 100, y - 75, x + 100, y + 75],
      }, tool: 'page_add_image');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not place the picture: $e';
        _saving = false;
      });
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
    if (_textLines.isEmpty) {
      if (!_linesLoading) {
        setState(() => _error = 'No selectable text on this page.');
      }
      return;
    }
    final anchor = _selectionAnchorLine;
    final extent = _selectionExtentLine;
    final shape = _latestShape();
    final quads = anchor != null && extent != null
        ? [
            for (
              var index = math.min(anchor, extent);
              index <= math.max(anchor, extent);
              index++
            )
              if (_textLines[index].rect.length == 4)
                _lineQuad(_textLines[index].rect),
          ]
        : shape == null
        ? const <List<double>>[]
        : selectionQuads(
            _textLines,
            geo.pxToPt(shape.start.dx, widget.dpi),
            geo.pxToPt(shape.start.dy, widget.dpi),
            geo.pxToPt(shape.end.dx, widget.dpi),
            geo.pxToPt(shape.end.dy, widget.dpi),
          );
    if (quads.isEmpty) {
      setState(
        () => _error = 'Touch and hold text, then drag to extend selection.',
      );
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
              labelText: 'Destination URL',
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_measureSummary(response))));
      setState(() => _measurePoints.clear());
    }
  }

  String _measureSummary(bridge.OperationResponse response) {
    for (final content in response.contents) {
      if (content.json.isEmpty) continue;
      try {
        final data = jsonDecode(content.json);
        if (data is Map<String, dynamic>) {
          final value = data['value'] ?? data['distance'] ?? data['area'];
          final unit = data['unit'];
          if (value != null) {
            return 'Measured $value${unit is String && unit.isNotEmpty ? ' $unit' : ''} — kept as an annotation.';
          }
        }
      } catch (_) {}
    }
    return 'Measurement saved as annotation.';
  }

  /// Runs a tool but stays on the overlay (used when the result is shown
  /// inline rather than by returning to the viewer).
  Future<bridge.OperationResponse?> _executeAndStay(
    Map<String, Object?> args, {
    String tool = 'comment_add',
  }) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      return await widget.engine.executeTool(
        handle: widget.handle,
        tool: tool,
        argumentsJson: geo.encodeArgs(args),
      );
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
        tool: tool,
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

  /// Thumb-first tool clusters: the five everyday tools stay visible and
  /// shapes/overflow live one tap deeper instead of twelve scrolling chips.
  Widget _toolClusters() {
    Widget cluster({
      required String label,
      required IconData icon,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label),
          avatar: Icon(icon, size: 16),
          selected: selected,
          onSelected: (_) => onTap(),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          cluster(
            label: 'Pan',
            icon: Icons.pan_tool_outlined,
            selected: _mode == AnnotateMode.pan,
            onTap: () => _pickTool(AnnotateMode.pan),
          ),
          cluster(
            label: 'Draw',
            icon: Icons.brush,
            selected: _mode == AnnotateMode.ink,
            onTap: () => _pickTool(AnnotateMode.ink),
          ),
          cluster(
            label: 'Mark',
            icon: Icons.highlight_outlined,
            selected: _mode == AnnotateMode.select,
            onTap: () => _pickTool(AnnotateMode.select),
          ),
          cluster(
            label: 'Note',
            icon: Icons.sticky_note_2_outlined,
            selected: _mode == AnnotateMode.note,
            onTap: () => _pickTool(AnnotateMode.note),
          ),
          cluster(
            label: 'Text',
            icon: Icons.text_fields_outlined,
            selected: _mode == AnnotateMode.text,
            onTap: () => _pickTool(AnnotateMode.text),
          ),
          cluster(
            label: _inShapes ? _shapeLabel(_mode) : 'Shape',
            icon: _inShapes ? _shapeIcon(_mode) : Icons.interests_outlined,
            selected: _inShapes,
            onTap: () {
              if (!_inShapes) _pickShape(AnnotateMode.rectangle);
              setState(() {
                _variantStrip = _variantStrip == 'shapes' ? null : 'shapes';
              });
            },
          ),
          cluster(
            label: 'Measure',
            icon: Icons.straighten_outlined,
            selected: _mode == AnnotateMode.measure,
            onTap: () => _pickTool(AnnotateMode.measure),
          ),
          cluster(
            label: 'More',
            icon: Icons.more_horiz,
            selected: _inOverflow,
            onTap: () => setState(() {
              _variantStrip = _variantStrip == 'more' ? null : 'more';
            }),
          ),
        ],
      ),
    );
  }

  Widget _variantStripRow({
    required List<AnnotateMode> modes,
    required AnnotateMode? selected,
    required String Function(AnnotateMode) label,
    required IconData Function(AnnotateMode) icon,
    required ValueChanged<AnnotateMode> onPick,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: [
          for (final mode in modes)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(label(mode)),
                avatar: Icon(icon(mode), size: 16),
                selected: selected == mode,
                onSelected: (_) => onPick(mode),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _mode == AnnotateMode.pan
              ? 'Pan & zoom · page ${widget.page}'
              : _mode == AnnotateMode.select
              ? 'Select text · page ${widget.page}'
              : _mode == AnnotateMode.note
              ? 'Add a note · page ${widget.page}'
              : _mode == AnnotateMode.stamp
              ? 'Place a stamp · page ${widget.page}'
              : _mode == AnnotateMode.image
              ? 'Place a picture · page ${widget.page}'
              : 'Annotate page ${widget.page}',
        ),
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
                  : Text(
                      _mode == AnnotateMode.select
                          ? 'Highlight selection'
                          : 'Save',
                    ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (!_dedicatedMode) _toolClusters(),
          if (!_dedicatedMode && _variantStrip == 'shapes')
            _variantStripRow(
              modes: _shapeModes,
              selected: _inShapes ? _mode : null,
              label: _shapeLabel,
              icon: _shapeIcon,
              onPick: _pickShape,
            ),
          if (!_dedicatedMode && _variantStrip == 'more')
            _variantStripRow(
              modes: _overflowModes,
              selected: _inOverflow ? _mode : null,
              label: _overflowLabel,
              icon: _overflowIcon,
              onPick: _pickTool,
            ),
          if (_mode == AnnotateMode.pan)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.pan_tool_outlined, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Pan mode active: Drag with one finger to move, pinch to zoom. Select Draw, Note, or Shape to edit.',
                    ),
                  ),
                ],
              ),
            ),
          if (_mode != AnnotateMode.pan &&
              _mode != AnnotateMode.select &&
              _mode != AnnotateMode.note &&
              _mode != AnnotateMode.stamp &&
              _mode != AnnotateMode.image)
            _StyleBar(
              color: _color,
              width: _width,
              colors: _colors,
              widths: _widths,
              onColor: (c) => setState(() => _color = c),
              onWidth: (w) => setState(() => _width = w),
              onUndo: () => setState(() {
                if (_mode == AnnotateMode.select) {
                  _selectionAnchorLine = null;
                  _selectionExtentLine = null;
                } else if (_measurePoints.isNotEmpty &&
                    _mode == AnnotateMode.measure) {
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
                _selectionAnchorLine = null;
                _selectionExtentLine = null;
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
                        : _selectionAnchorLine == null
                        ? 'Touch and hold a word, then drag'
                        : '${_selectedLineRects().length} lines selected',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          if (_mode == AnnotateMode.select)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(
                'Hold a word and drag to extend. Move either handle to adjust; yellow lines are the preview.',
              ),
            ),
          if (_mode == AnnotateMode.note)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text('Tap where the note belongs. Write it, then Add.'),
            ),
          if (_mode == AnnotateMode.stamp)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text('Tap where the stamp belongs, then choose it.'),
            ),
          if (_mode == AnnotateMode.image)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text('Tap where the picture belongs, then choose it.'),
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
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final fitScale = fitPageScale(
                        viewportWidth: constraints.maxWidth,
                        viewportHeight: constraints.maxHeight,
                        pageWidth: widget.imageWidthPx,
                        pageHeight: widget.imageHeightPx,
                      );
                      final pageWidth = widget.imageWidthPx * fitScale;
                      final pageHeight = widget.imageHeightPx * fitScale;
                      return Center(
                        child: InteractiveViewer(
                          constrained: false,
                          minScale: 1,
                          maxScale: 8,
                          child: SizedBox(
                            width: pageWidth,
                            height: pageHeight,
                            child: Builder(
                              builder: (paintContext) {
                                final start = _selectionAnchorLine;
                                final extent = _selectionExtentLine;
                                final firstRect =
                                    start == null || extent == null
                                    ? null
                                    : _lineRectPixels(
                                        _textLines[math.min(start, extent)],
                                      );
                                final lastRect = start == null || extent == null
                                    ? null
                                    : _lineRectPixels(
                                        _textLines[math.max(start, extent)],
                                      );
                                Widget handle(Rect rect, bool anchor) =>
                                    Positioned(
                                      left:
                                          (anchor ? rect.left : rect.right) *
                                              fitScale -
                                          22,
                                      top: rect.bottom * fitScale - 22,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onPanUpdate: (details) =>
                                            _moveSelectionHandle(
                                              details: details,
                                              paintContext: paintContext,
                                              fitScale: fitScale,
                                              anchor: anchor,
                                            ),
                                        child: SizedBox(
                                          width: 44,
                                          height: 44,
                                          child: Center(
                                            child: Container(
                                              width: 16,
                                              height: 16,
                                              decoration: BoxDecoration(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.white,
                                                  width: 2,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                return GestureDetector(
                                  onTapDown: _mode == AnnotateMode.pan
                                      ? null
                                      : (details) => _onTapDown(
                                          details,
                                          paintContext,
                                          fitScale,
                                        ),
                                  onPanStart: (_mode == AnnotateMode.select ||
                                          _mode == AnnotateMode.pan)
                                      ? null
                                      : (details) => _onPanStart(
                                          details,
                                          paintContext,
                                          fitScale,
                                        ),
                                  onPanUpdate: (_mode == AnnotateMode.select ||
                                          _mode == AnnotateMode.pan)
                                      ? null
                                      : (details) => _onPanUpdate(
                                          details,
                                          paintContext,
                                          fitScale,
                                        ),
                                  onPanEnd: (_mode == AnnotateMode.select ||
                                          _mode == AnnotateMode.pan)
                                      ? null
                                      : (_) => _onPanEnd(),
                                  onLongPressStart: _mode == AnnotateMode.select
                                      ? (details) => _startTextSelection(
                                          details,
                                          fitScale,
                                        )
                                      : null,
                                  onLongPressMoveUpdate:
                                      _mode == AnnotateMode.select
                                      ? (details) => _extendTextSelection(
                                          details,
                                          fitScale,
                                        )
                                      : null,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    clipBehavior: Clip.none,
                                    children: [
                                      CustomPaint(
                                        size: Size(pageWidth, pageHeight),
                                        painter: _DraftPainter(
                                          baseImage: _baseImage!,
                                          fitScale: fitScale,
                                          strokes: _strokes,
                                          currentStroke: _currentStroke,
                                          shapes: _shapes,
                                          measurePoints: _measurePoints,
                                          selectedLineRectsPx:
                                              _selectedLineRects(),
                                        ),
                                      ),
                                      if (firstRect != null &&
                                          lastRect != null) ...[
                                        handle(firstRect, true),
                                        handle(lastRect, false),
                                      ],
                                    ],
                                  ),
                                );
                              },
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
    required this.fitScale,
    required this.strokes,
    required this.currentStroke,
    required this.shapes,
    required this.measurePoints,
    required this.selectedLineRectsPx,
  });

  final ui.Image baseImage;
  final double fitScale;
  final List<geo.InkStroke> strokes;
  final List<Offset> currentStroke;
  final List<_DraftShape> shapes;
  final List<Offset> measurePoints;
  final List<Rect> selectedLineRectsPx;

  static const _swatches = {
    'red': Colors.red,
    'yellow': Colors.yellow,
    'green': Colors.green,
    'blue': Colors.blue,
    'black': Colors.black,
  };

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(fitScale);
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
    final highlight = Paint()
      ..color = Colors.yellow.withValues(alpha: 0.42)
      ..style = PaintingStyle.fill;
    final edge = Paint()
      ..color = Colors.amber.shade800
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final line in selectedLineRectsPx) {
      canvas.drawRect(line, highlight);
      canvas.drawRect(line, edge);
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
    canvas.restore();
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
      case AnnotateMode.pan:
      case AnnotateMode.ink:
      case AnnotateMode.note:
      case AnnotateMode.text:
      case AnnotateMode.addText:
      case AnnotateMode.stamp:
      case AnnotateMode.image:
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
