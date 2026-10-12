import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../bridge/api.dart' as bridge;
import '../services/pdf_engine.dart';
import 'page_viewport.dart';

/// A text paragraph from `text_paragraphs`.
class Paragraph {
  Paragraph({
    required this.number,
    required this.text,
    required this.font,
    required this.size,
    required this.rect,
  });

  final int number;
  final String text;
  final String font;
  final double size;
  final List<double> rect;

  static Paragraph? fromJson(Map<String, dynamic> json) {
    final number = (json['paragraph'] as num?)?.toInt();
    if (number == null) return null;
    return Paragraph(
      number: number,
      text: json['text'] as String? ?? '',
      font: json['font'] as String? ?? '',
      size: (json['size'] as num?)?.toDouble() ?? 0,
      rect: (json['rect'] as List? ?? const [])
          .whereType<num>()
          .map((value) => value.toDouble())
          .toList(growable: false),
    );
  }
}

/// Edit existing text: pick a paragraph on the page, rewrite it in place.
/// Uses `text_paragraphs` + `text_edit`.
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
  });

  final PdfEngineApi engine;
  final int handle;
  final int page;
  final Uint8List png;
  final double imageWidthPx;
  final double imageHeightPx;
  final ValueChanged<bridge.DocumentStatus> onStatusChanged;

  @override
  State<TextEditSheet> createState() => _TextEditSheetState();
}

class _TextEditSheetState extends State<TextEditSheet> {
  List<Paragraph> _paragraphs = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  Paragraph? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await widget.engine.executeTool(
        handle: widget.handle,
        tool: 'text_paragraphs',
        argumentsJson: jsonEncode({'page': widget.page}),
      );
      final paragraphs = <Paragraph>[];
      for (final content in response.contents) {
        if (content.json.isEmpty) continue;
        final decoded = jsonDecode(content.json);
        final list = decoded is Map<String, dynamic>
            ? decoded['paragraphs']
            : decoded is List
            ? decoded
            : null;
        if (list is List) {
          for (final item in list) {
            if (item is Map<String, dynamic>) {
              final p = Paragraph.fromJson(item);
              if (p != null) paragraphs.add(p);
            }
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _paragraphs = paragraphs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _selectAt(Offset localPosition, double fitScale) {
    final x = localPosition.dx / fitScale * 72 / 96;
    final y = localPosition.dy / fitScale * 72 / 96;
    Paragraph? closest;
    var closestDistanceSquared = double.infinity;
    for (final paragraph in _paragraphs) {
      if (paragraph.rect.length != 4) continue;
      final left = paragraph.rect[0];
      final top = paragraph.rect[1];
      final right = paragraph.rect[2];
      final bottom = paragraph.rect[3];
      final dx = x < left
          ? left - x
          : x > right
          ? x - right
          : 0.0;
      final dy = y < top
          ? top - y
          : y > bottom
          ? y - bottom
          : 0.0;
      final distanceSquared = dx * dx + dy * dy;
      if (distanceSquared < closestDistanceSquared) {
        closest = paragraph;
        closestDistanceSquared = distanceSquared;
      }
    }
    if (closest == null || closestDistanceSquared > 42 * 42) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tap near a line of text to select it.')),
      );
      return;
    }
    setState(() => _selected = closest);
  }

  Future<void> _browseParagraphs() async {
    final selected = await showModalBottomSheet<Paragraph>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: ListView.builder(
          itemCount: _paragraphs.length,
          itemBuilder: (context, index) {
            final paragraph = _paragraphs[index];
            return ListTile(
              title: Text(
                paragraph.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text('Paragraph ${paragraph.number}'),
              onTap: () => Navigator.pop(context, paragraph),
            );
          },
        ),
      ),
    );
    if (selected != null && mounted) setState(() => _selected = selected);
  }

  Future<void> _edit(Paragraph paragraph) async {
    final controller = TextEditingController(text: paragraph.text);
    try {
      final text = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Paragraph ${paragraph.number}'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 6,
            decoration: InputDecoration(
              helperText:
                  '${paragraph.font} ${paragraph.size.toStringAsFixed(1)} pt',
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (text == null || !mounted) return;
      setState(() => _busy = true);
      try {
        final response = await widget.engine.executeTool(
          handle: widget.handle,
          tool: 'text_edit',
          argumentsJson: jsonEncode({
            'page': widget.page,
            'paragraph': paragraph.number,
            'text': text,
          }),
        );
        if (!mounted) return;
        widget.onStatusChanged(response.status);
        Navigator.pop(context);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Edit failed: $e')));
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Edit text · page ${widget.page}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(child: Text(_error!))
                  : _paragraphs.isEmpty
                  ? const Center(child: Text('No editable text on this page.'))
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final fitScale = fitPageScale(
                          viewportWidth: constraints.maxWidth,
                          viewportHeight: constraints.maxHeight,
                          pageWidth: widget.imageWidthPx,
                          pageHeight: widget.imageHeightPx,
                        );
                        return Center(
                          child: SizedBox(
                            width: widget.imageWidthPx * fitScale,
                            height: widget.imageHeightPx * fitScale,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapUp: (details) =>
                                  _selectAt(details.localPosition, fitScale),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.memory(widget.png, fit: BoxFit.fill),
                                  if (_selected?.rect.length == 4)
                                    Positioned(
                                      left:
                                          _selected!.rect[0] *
                                          96 /
                                          72 *
                                          fitScale,
                                      top:
                                          _selected!.rect[1] *
                                          96 /
                                          72 *
                                          fitScale,
                                      width:
                                          (_selected!.rect[2] -
                                              _selected!.rect[0]) *
                                          96 /
                                          72 *
                                          fitScale,
                                      height:
                                          (_selected!.rect[3] -
                                              _selected!.rect[1]) *
                                          96 /
                                          72 *
                                          fitScale,
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
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (!_loading && _paragraphs.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_selected == null)
                      const Text(
                        'Tap a paragraph on the page to preview what will be replaced.',
                        textAlign: TextAlign.center,
                      )
                    else
                      Text(
                        'Selected: ${_selected!.text}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 6),
                    FilledButton.icon(
                      onPressed: _busy || _selected == null
                          ? null
                          : () => _edit(_selected!),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit selected text'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : _browseParagraphs,
                      child: const Text('Browse text blocks'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
