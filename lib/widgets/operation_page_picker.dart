import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/pdf_engine.dart';

/// Choose page-space coordinates on the actual rendered surface. The caller
/// uses this only for operations whose geometry is expressed in display points.
class OperationPagePicker extends StatefulWidget {
  const OperationPagePicker({
    super.key,
    required this.engine,
    required this.handle,
    required this.page,
    required this.properties,
    required this.onSelected,
  });
  final PdfEngineApi engine;
  final int handle, page;
  final Map<String, dynamic> properties;
  final ValueChanged<Map<String, dynamic>> onSelected;

  @override
  State<OperationPagePicker> createState() => _OperationPagePickerState();
}

class _OperationPagePickerState extends State<OperationPagePicker> {
  bool loading = false;
  String? error;

  Future<void> _locate(String field, int count) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final size = await widget.engine.pageSize(
        handle: widget.handle,
        page1Based: widget.page,
      );
      if (size.width <= 0 || size.height <= 0) {
        throw StateError('The page dimensions are unavailable.');
      }
      final dpi = (1000 * 72 / math.max(size.width, size.height)).floor().clamp(
        1,
        120,
      );
      final image = await widget.engine.renderPagePng(
        handle: widget.handle,
        page1Based: widget.page,
        dpi: dpi,
      );
      if (!mounted) return;
      final points = await Navigator.of(context).push<List<Offset>>(
        MaterialPageRoute(
          builder: (_) => _PointPicker(
            page: widget.page,
            data: image,
            ratio: size.width / size.height,
            count: count,
          ),
        ),
      );
      if (!mounted || points == null) return;
      final picked = points
          .map((p) => Offset(p.dx * size.width, p.dy * size.height))
          .toList();
      List<double> result;
      if (field == 'rect' || field == 'region') {
        final r = Rect.fromPoints(picked.first, picked.last);
        result = [r.left, r.top, r.right, r.bottom];
      } else {
        result = [
          for (final p in picked) ...[p.dx, p.dy],
        ];
      }
      widget.onSelected({
        field: result.map((n) => (n * 100).round() / 100).toList(),
        if (widget.properties['page']?['type'] == 'integer')
          'page': widget.page,
        if (field == 'region') 'pages': widget.page.toString(),
      });
    } catch (e) {
      if (mounted) setState(() => error = 'Could not open page preview. $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final props = widget.properties;
    final fields = <String, int>{
      for (final (key, length) in [
        ('point', 2),
        ('at', 2),
        ('rect', 4),
        ('region', 4),
        ('corners', 8),
      ])
        if (props[key]?['type'] == 'array' && props[key]?['maxItems'] == length)
          key: length ~/ 2,
    };
    if (widget.handle <= 0 || fields.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final e in fields.entries)
              OutlinedButton.icon(
                onPressed: loading ? null : () => _locate(e.key, e.value),
                icon: const Icon(Icons.touch_app_outlined),
                label: Text(switch (e.key) {
                  'point' || 'at' => 'Tap a position',
                  'rect' || 'region' => 'Mark a rectangle',
                  _ => 'Mark four corners',
                }),
              ),
          ],
        ),
        if (loading)
          const LinearProgressIndicator(semanticsLabel: 'Rendering page'),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _PointPicker extends StatefulWidget {
  const _PointPicker({
    required this.page,
    required this.data,
    required this.ratio,
    required this.count,
  });
  final int page, count;
  final double ratio;
  final Uint8List data;
  @override
  State<_PointPicker> createState() => _PointPickerState();
}

class _PointPickerState extends State<_PointPicker> {
  final points = <Offset>[];
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Page ${widget.page}')),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Semantics(
              liveRegion: true,
              child: Text(
                points.length == widget.count
                    ? 'Review the selection.'
                    : widget.count == 1
                    ? 'Tap the position on the page.'
                    : 'Tap corner ${points.length + 1} of ${widget.count}.',
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: widget.ratio,
                child: LayoutBuilder(
                  builder: (context, box) {
                    final width = box.maxWidth, height = box.maxHeight;
                    return GestureDetector(
                      onTapUp: (event) {
                        if (points.length >= widget.count) return;
                        setState(
                          () => points.add(
                            Offset(
                              (event.localPosition.dx / width).clamp(0, 1),
                              (event.localPosition.dy / height).clamp(0, 1),
                            ),
                          ),
                        );
                      },
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(
                            widget.data,
                            fit: BoxFit.fill,
                            semanticLabel: 'Page preview',
                          ),
                          if (widget.count == 2 && points.length == 2)
                            Positioned.fromRect(
                              rect: Rect.fromPoints(
                                Offset(
                                  points.first.dx * width,
                                  points.first.dy * height,
                                ),
                                Offset(
                                  points.last.dx * width,
                                  points.last.dy * height,
                                ),
                              ),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: .15),
                                  border: Border.all(
                                    color: Colors.blue,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                          for (var i = 0; i < points.length; i++)
                            Positioned(
                              left: points[i].dx * width - 9,
                              top: points[i].dy * height - 9,
                              child: CircleAvatar(
                                radius: 9,
                                backgroundColor: Colors.indigo,
                                child: Text(
                                  '${i + 1}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: points.isEmpty
                      ? null
                      : () => setState(() => points.removeLast()),
                  child: const Text('Undo point'),
                ),
                FilledButton(
                  onPressed: points.length == widget.count
                      ? () => Navigator.pop(context, points)
                      : null,
                  child: const Text('Use selection'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
