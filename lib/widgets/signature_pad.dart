import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Drawn signature: capture strokes on a pad, export PNG, stage it, and
/// place it with `fill_sign_add`. Falls back to the typed signature sheet
/// for devices where drawing is impractical.
class SignaturePad extends StatefulWidget {
  const SignaturePad({super.key});

  @override
  State<SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<SignaturePad> {
  final _boundary = GlobalKey();
  List<List<Offset>> _strokes = [];
  List<Offset> _current = [];
  bool _saving = false;
  String? _error;
  Color _selectedColor = const Color(0xFF003366); // Default: Executive Formal Blue
  double _selectedStrokeWidth = 3.0;

  static const _inkColors = [
    (name: 'Executive Blue', color: Color(0xFF003366), tooltip: 'Formal blue ink (legal standard)'),
    (name: 'Midnight Black', color: Color(0xFF111111), tooltip: 'Clean executive black ink'),
    (name: 'Navy Indigo', color: Color(0xFF1E3A8A), tooltip: 'Deep navy fountain pen ink'),
  ];

  static const _strokeWidths = [
    (label: 'Fine', width: 1.8),
    (label: 'Regular', width: 3.0),
    (label: 'Bold', width: 4.5),
  ];

  Future<void> _place() async {
    final allStrokes = [..._strokes];
    if (_current.isNotEmpty) {
      allStrokes.add(_current);
    }
    if (allStrokes.isEmpty) {
      setState(() => _error = 'Draw your signature first');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final renderObject = _boundary.currentContext?.findRenderObject();
      final size = (renderObject is RenderBox && renderObject.hasSize)
          ? renderObject.size
          : const Size(300, 200);

      // Render crisp ink on transparent background for stamping onto PDF paper
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const pixelRatio = 3.0;
      canvas.scale(pixelRatio, pixelRatio);

      final exportPainter = _SignaturePainter(
        strokes: allStrokes,
        current: const [],
        color: _selectedColor,
        strokeWidth: _selectedStrokeWidth,
      );
      exportPainter.paint(canvas, size);

      final picture = recorder.endRecording();
      final image = await picture.toImage(
        (size.width * pixelRatio).toInt(),
        (size.height * pixelRatio).toInt(),
      );
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('Could not export the drawing');
      final png = bytes.buffer.asUint8List();
      if (!mounted) return;
      Navigator.pop<Uint8List>(context, png);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final padBackground = isDark ? const Color(0xFF222222) : const Color(0xFFFAFAFA);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Signature Studio',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Draw with your finger or stylus',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Cancel drawing',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Ink color & stroke options bar
            Row(
              children: [
                Text(
                  'Ink:',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                for (final ink in _inkColors)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Tooltip(
                      message: ink.tooltip,
                      child: InkWell(
                        onTap: () => setState(() => _selectedColor = ink.color),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: ink.color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _selectedColor == ink.color
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.grey.withValues(alpha: 0.4),
                              width: _selectedColor == ink.color ? 2.5 : 1,
                            ),
                            boxShadow: _selectedColor == ink.color
                                ? [
                                    BoxShadow(
                                      color: ink.color.withValues(alpha: 0.4),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ]
                                : null,
                          ),
                          child: _selectedColor == ink.color
                              ? const Icon(Icons.check, size: 16, color: Colors.white)
                              : null,
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
                SegmentedButton<double>(
                  segments: [
                    for (final s in _strokeWidths)
                      ButtonSegment(
                        value: s.width,
                        label: Text(s.label, style: const TextStyle(fontSize: 11)),
                      ),
                  ],
                  selected: {_selectedStrokeWidth},
                  onSelectionChanged: (values) =>
                      setState(() => _selectedStrokeWidth = values.first),
                ),
              ],
            ),
            const SizedBox(height: 10),

            Semantics(
              label: 'Signature drawing canvas. Draw with one finger.',
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  color: padBackground,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: GestureDetector(
                    key: _boundary,
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _SignaturePainter(
                          strokes: _strokes,
                          current: _current,
                          color: _selectedColor,
                          strokeWidth: _selectedStrokeWidth,
                        ),
                        size: Size.infinite,
                      ),
                    ),
                    onPanStart: (d) =>
                        setState(() => _current = [d.localPosition]),
                    onPanUpdate: (d) =>
                        setState(() => _current = [..._current, d.localPosition]),
                    onPanEnd: (_) => setState(() {
                      if (_current.length > 1) {
                        _strokes = [..._strokes, _current];
                      }
                      _current = [];
                    }),
                  ),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => setState(() {
                    _strokes = [];
                    _current = [];
                  }),
                  icon: const Icon(Icons.clear_all),
                  label: const Text('Clear'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _saving ? null : _place,
                  icon: const Icon(Icons.check, size: 18),
                  label: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Continue to placement'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter({
    required this.strokes,
    required this.current,
    this.color = const Color(0xFF003366),
    this.strokeWidth = 3.0,
  });

  final List<List<Offset>> strokes;
  final List<Offset> current;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void draw(List<Offset> points) {
      if (points.length < 2) {
        if (points.length == 1) {
          canvas.drawCircle(points.first, strokeWidth / 2, paint);
        }
        return;
      }
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final p in points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }

    for (final stroke in strokes) {
      draw(stroke);
    }
    draw(current);
  }

  @override
  bool shouldRepaint(_SignaturePainter old) => true;
}
