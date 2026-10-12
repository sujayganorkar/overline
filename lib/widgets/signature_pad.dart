import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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
    if (_strokes.isEmpty && _current.isEmpty) {
      setState(() => _error = 'Draw your signature first');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final renderObject = _boundary.currentContext?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) {
        throw StateError('Could not capture the signature drawing');
      }
      final boundary = renderObject;
      final image = await boundary.toImage(pixelRatio: 3);
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Draw signature',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: GestureDetector(
                child: RepaintBoundary(
                  key: _boundary,
                  child: CustomPaint(
                    painter: _SignaturePainter(
                      strokes: _strokes,
                      current: _current,
                    ),
                    size: Size.infinite,
                  ),
                ),
                onPanStart: (d) => setState(() => _current = [d.localPosition]),
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
  _SignaturePainter({required this.strokes, required this.current});

  final List<List<Offset>> strokes;
  final List<Offset> current;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
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
