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

      // Render crisp black ink on transparent background for stamping onto PDF paper
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const pixelRatio = 3.0;
      canvas.scale(pixelRatio, pixelRatio);

      final exportPainter = _SignaturePainter(
        strokes: allStrokes,
        current: const [],
        color: Colors.black,
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
    final padBackground = isDark ? const Color(0xFF222222) : Colors.white;
    final strokeColor = isDark ? Colors.white : Colors.black;

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
                  child: Text(
                    'Draw signature',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Cancel drawing',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
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
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: GestureDetector(
                  key: _boundary,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _SignaturePainter(
                        strokes: _strokes,
                        current: _current,
                        color: strokeColor,
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
                FilledButton(
                  onPressed: _saving ? null : _place,
                  child: _saving
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
    this.color = Colors.black,
  });

  final List<List<Offset>> strokes;
  final List<Offset> current;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void draw(List<Offset> points) {
      if (points.length < 2) {
        if (points.length == 1) {
          canvas.drawCircle(points.first, 1.5, paint);
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
