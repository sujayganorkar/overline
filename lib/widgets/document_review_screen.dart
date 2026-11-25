import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../bridge/api.dart' as bridge;
import '../services/pdf_engine.dart';
import 'output_saver.dart';

bool isDocumentReviewTool(String tool) => const {
  'accessibility_autotag_apply',
  'accessibility_autotag_preview',
  'ocr_words',
  'ocr_review_apply',
  'doc_audit_redactions',
}.contains(tool);

class DocumentReviewScreen extends StatefulWidget {
  const DocumentReviewScreen({
    super.key,
    required this.engine,
    required this.handle,
    required this.tool,
    required this.currentPage,
    required this.pageCount,
    required this.onStatusChanged,
    this.onShowPage,
  });
  final PdfEngineApi engine;
  final int handle, currentPage, pageCount;
  final String tool;
  final ValueChanged<bridge.DocumentStatus> onStatusChanged;
  final ValueChanged<int>? onShowPage;
  @override
  State<DocumentReviewScreen> createState() => _DocumentReviewScreenState();
}

class _DocumentReviewScreenState extends State<DocumentReviewScreen> {
  late final _engine = widget.engine;
  late final _handle = widget.handle;
  late int _page = widget.currentPage;
  bool get _ocr => widget.tool.startsWith('ocr_');
  bool get _audit => widget.tool == 'doc_audit_redactions';
  late final String _title = _ocr
      ? 'Review recognized words'
      : _audit
      ? 'Audit redactions'
      : 'Tag for screen readers';
  bool _busy = true, _applying = false, _applied = false, _editableCopy = false;
  String? _error, _message, _editablePath;
  Uint8List? _png;
  Size? _size;
  int? _review;
  List<Rect> _wordBoxes = const [];
  static const _dictionaryPath = 'outputs/ocr-dictionary-en.txt';
  Set<String> _dictionary = {};
  bool _dictionaryLoaded = false;
  List<Map<String, dynamic>> _items = [];
  final _edits = <int, String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<bridge.OperationResponse> _run(
    String tool,
    Map<String, Object?> args,
  ) => _engine.executeTool(
    handle: _handle,
    tool: tool,
    argumentsJson: jsonEncode(args),
  );

  Map<String, dynamic> _data(bridge.OperationResponse response) {
    for (final content in response.contents) {
      if (content.json.isEmpty) continue;
      final value = jsonDecode(content.json);
      if (value is Map<String, dynamic>) return value;
    }
    throw const FormatException('The engine returned no review data.');
  }

  Future<void> _release(int review) async {
    try {
      await _run('ocr_review_apply', {'review': review, 'discard': true});
    } catch (_) {
      // Closing the document also releases its retained OCR review.
    }
  }

  Future<void> _load() async {
    final oldReview = _review;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
      _editablePath = null;
      _wordBoxes = const [];
      _applied = false;
      _review = null;
      _items = [];
      _edits.clear();
      _png = null;
    });
    try {
      if (oldReview != null) await _release(oldReview);
      if (!mounted) return;
      if (!_audit) {
        final size = await widget.engine.pageSize(
          handle: widget.handle,
          page1Based: _page,
        );
        if (!mounted) return;
        _size = Size(size.width, size.height);
        _png = await widget.engine.renderPagePng(
          handle: widget.handle,
          page1Based: _page,
          dpi: 96,
        );
        if (!mounted) return;
      }
      final result = _data(
        await _run(
          _ocr
              ? 'ocr_words'
              : _audit
              ? 'doc_audit_redactions'
              : 'accessibility_autotag_preview',
          _ocr
              ? {
                  'pages': [_page],
                  'retain_review': true,
                  'force_ocr': true,
                  'dpi': 180,
                }
              : _audit
              ? {}
              : {'page': _page},
        ),
      );
      final token = result['review'] as int?;
      if (!mounted) {
        if (token != null) await _release(token);
        return;
      }
      if (_ocr) {
        _review = token;
        if (!_dictionaryLoaded) {
          try {
            final saved = _data(
              await _run('ocr_dictionary', {'path': _dictionaryPath}),
            );
            _dictionary = (saved['words'] as List).whereType<String>().toSet();
          } catch (_) {
            // A fresh installation has no saved dictionary.
          }
          _dictionaryLoaded = true;
          if (!mounted) return;
        }
        final pages = (result['pages'] as List).whereType<Map>();
        final words = pages.isEmpty ? [] : pages.first['words'] as List? ?? [];
        _items = words.whereType<Map<String, dynamic>>().toList();
        _wordBoxes = [
          for (final word in _items)
            if (word['box'] case [num x, num y, num w, num h])
              Rect.fromLTWH(
                x.toDouble(),
                y.toDouble(),
                w.toDouble(),
                h.toDouble(),
              )
            else
              Rect.zero,
        ];
      } else {
        final items = result[_audit ? 'findings' : 'candidates'] as List;
        _items = items.whereType<Map<String, dynamic>>().toList();
      }
    } catch (e) {
      if (mounted) _error = e.toString();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    final token = _review;
    if (token != null) unawaited(_release(token));
    super.dispose();
  }

  Future<void> _editWord(int index) async {
    final old = _edits[index] ?? _items[index]['text'] as String;
    var replacement = old;
    var remember = false;
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) {
          final prefix = replacement.trim().toLowerCase();
          final suggestions = _dictionary
              .where(
                (w) => prefix.isNotEmpty && w != prefix && w.startsWith(prefix),
              )
              .take(3);
          return AlertDialog(
            scrollable: true,
            title: Text('Word ${index + 1} on page $_page'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  initialValue: old,
                  autofocus: true,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Corrected text',
                    helperText: 'Clear the word to remove it.',
                  ),
                  onChanged: (value) => update(() => replacement = value),
                  onFieldSubmitted: (value) => Navigator.pop(ctx, value),
                ),
                if (suggestions.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final word in suggestions)
                        ActionChip(
                          label: Text(word),
                          tooltip: 'Use dictionary word',
                          onPressed: () => Navigator.pop(ctx, word),
                        ),
                    ],
                  ),
                if (prefix.isNotEmpty && !_dictionary.contains(prefix))
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: remember,
                    title: const Text('Remember word on this device'),
                    onChanged: (value) =>
                        update(() => remember = value == true),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, replacement),
                child: const Text('Keep correction'),
              ),
            ],
          );
        },
      ),
    );
    if (mounted && text != null) {
      setState(() {
        if (text == _items[index]['text']) {
          _edits.remove(index);
        } else {
          _edits[index] = text;
        }
      });
      if (remember &&
          text.trim().isNotEmpty &&
          !_dictionary.contains(text.trim().toLowerCase())) {
        try {
          final saved = _data(
            await _run('ocr_dictionary', {
              'path': _dictionaryPath,
              'add': [text],
            }),
          );
          if (mounted) {
            setState(
              () => _dictionary = (saved['words'] as List)
                  .whereType<String>()
                  .toSet(),
            );
          }
        } catch (e) {
          if (mounted) {
            setState(
              () => _error =
                  'Correction kept. Could not save the dictionary word. $e',
            );
          }
        }
      }
    }
  }

  Future<void> _apply() async {
    setState(() {
      _busy = true;
      _applying = true;
      _error = null;
    });
    try {
      final args = <String, Object?>{};
      if (_ocr) {
        args['review'] = _review!;
        args['corrections'] = [
          for (final edit in _edits.entries)
            {'page': _page, 'word': edit.key + 1, 'text': edit.value},
        ];
        if (_editableCopy) {
          args['output_mode'] = 'editable';
          args['out'] =
              'outputs/ocr-${DateTime.now().microsecondsSinceEpoch}.pdf';
        }
      }
      final result = await _run(
        _ocr ? 'ocr_review_apply' : 'accessibility_autotag_apply',
        args,
      );
      _review = null;
      if (!mounted) return;
      if (!_ocr || !_editableCopy) widget.onStatusChanged(result.status);
      _applied = true;
      _message = _ocr
          ? (_editableCopy
                ? 'Editable PDF created.'
                : 'Searchable text applied to page $_page.')
          : 'The document is tagged. Review its headings and reading order.';
      if (_ocr && _editableCopy) {
        _editablePath = args['out'] as String;
        await saveOutputPaths(context, widget.engine, [_editablePath!]);
      }
    } catch (e) {
      if (mounted) _error = e.toString();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _applying = false;
        });
      }
    }
  }

  Future<bool> _mayLeave() async {
    if (_edits.isEmpty || _applied) return true;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Discard word corrections?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Discard'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _changePage(int step) async {
    if (!await _mayLeave() || !mounted) return;
    _page += step;
    await _load();
  }

  Widget _pageImage({ValueChanged<int>? onWord}) {
    final pageSize = _size!;
    return AspectRatio(
      aspectRatio: pageSize.aspectRatio,
      child: LayoutBuilder(
        builder: (context, box) => GestureDetector(
          onTapUp: onWord == null
              ? null
              : (tap) {
                  final point = Offset(
                    tap.localPosition.dx * pageSize.width / box.maxWidth,
                    tap.localPosition.dy * pageSize.height / box.maxHeight,
                  );
                  final index = _wordBoxes.indexWhere(
                    (rect) => rect.contains(point),
                  );
                  if (index >= 0) onWord(index);
                },
          child: CustomPaint(
            foregroundPainter: onWord == null
                ? null
                : _WordBoxes(_wordBoxes, pageSize),
            child: Image.memory(
              _png!,
              fit: BoxFit.fill,
              semanticLabel: 'Preview of page $_page',
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _enlarge() async {
    final word = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          appBar: AppBar(title: Text('Recognized words · Page $_page')),
          body: SafeArea(
            child: InteractiveViewer(
              maxScale: 8,
              child: Center(
                child: _pageImage(onWord: (index) => Navigator.pop(ctx, index)),
              ),
            ),
          ),
        ),
      ),
    );
    if (mounted && word != null) await _editWord(word);
  }

  Widget _preview() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 230),
          child: _pageImage(onWord: _ocr && !_applied ? _editWord : null),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_applying && (_edits.isEmpty || _applied),
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop || _applying || !await _mayLeave() || !mounted) return;
      setState(() => _edits.clear());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    },
    child: Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: SafeArea(
        child: _busy
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      _audit
                          ? 'Checking redactions…'
                          : 'Processing page $_page…',
                    ),
                  ],
                ),
              )
            : ListView.builder(
                key: ValueKey(_page),
                itemCount: _items.length + 1,
                itemBuilder: (_, i) {
                  if (i == 0) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!_audit)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                tooltip: 'Previous page',
                                onPressed: _page > 1
                                    ? () => _changePage(-1)
                                    : null,
                                icon: const Icon(Icons.chevron_left),
                              ),
                              Text('Page $_page of ${widget.pageCount}'),
                              IconButton(
                                tooltip: 'Next page',
                                onPressed: _page < widget.pageCount
                                    ? () => _changePage(1)
                                    : null,
                                icon: const Icon(Icons.chevron_right),
                              ),
                            ],
                          ),
                        if (_png != null) _preview(),
                        if (_ocr && !_applied && _wordBoxes.isNotEmpty)
                          Center(
                            child: TextButton.icon(
                              onPressed: _enlarge,
                              icon: const Icon(Icons.zoom_in),
                              label: const Text('Enlarge scan'),
                            ),
                          ),
                        if (_editablePath != null)
                          Center(
                            child: OutlinedButton(
                              onPressed: () => saveOutputPaths(
                                context,
                                widget.engine,
                                [_editablePath!],
                              ),
                              child: const Text('Save or share editable copy'),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              _error ??
                                  _message ??
                                  (_ocr
                                      ? (_items.isEmpty
                                            ? 'No words found on this page.'
                                            : 'Tap a word to correct it before applying.')
                                      : _audit
                                      ? (_items.isEmpty
                                            ? 'No covered text or unapplied marks found.'
                                            : '${_items.length} potential redaction problems. Tap one to view its page.')
                                      : 'Suggested structure for this page. Applying tags covers the whole text-only document.'),
                            ),
                          ),
                        ),
                        if (_error != null && _items.isEmpty)
                          TextButton(
                            onPressed: _load,
                            child: const Text('Try again'),
                          ),
                        if (_ocr && _items.isNotEmpty && !_applied)
                          SwitchListTile(
                            title: const Text('Create an editable PDF copy'),
                            value: _editableCopy,
                            onChanged: (v) => setState(() => _editableCopy = v),
                          ),
                      ],
                    );
                  }
                  final index = i - 1, item = _items[index];
                  if (_audit) {
                    return ListTile(
                      leading: const Icon(Icons.visibility_off_outlined),
                      title: Text(
                        '${item['covered_text'] ?? ''}'.isEmpty
                            ? 'Review redaction mark'
                            : '${item['covered_text']}',
                      ),
                      subtitle: Text('Page ${item['page']} · ${item['kind']}'),
                      onTap: widget.onShowPage == null
                          ? null
                          : () => widget.onShowPage!(item['page'] as int),
                    );
                  }
                  if (!_ocr) {
                    return ListTile(
                      title: Text('${item['text'] ?? ''}'),
                      subtitle: Text('${item['type']} · ${item['reason']}'),
                    );
                  }
                  final confidence = item['confidence'];
                  final text = _edits[index] ?? item['text'] as String;
                  return ListTile(
                    title: Text(text.isEmpty ? 'Remove word' : text),
                    subtitle: Text(
                      _edits.containsKey(index)
                          ? 'Corrected'
                          : _dictionary.contains(text.toLowerCase())
                          ? 'In your dictionary'
                          : confidence is num
                          ? '${confidence.round()}% confidence'
                          : 'Word ${index + 1}',
                    ),
                    trailing: _applied ? null : const Icon(Icons.edit_outlined),
                    onTap: _applied ? null : () => _editWord(index),
                  );
                },
              ),
      ),
      bottomNavigationBar: _busy || _audit || (_error != null && _items.isEmpty)
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton(
                onPressed: _applied
                    ? () => Navigator.pop(context)
                    : (_ocr && (_review == null || _items.isEmpty))
                    ? null
                    : _apply,
                child: Text(
                  _applied
                      ? 'Done'
                      : _ocr
                      ? 'Apply reviewed words'
                      : 'Tag entire document',
                ),
              ),
            ),
    ),
  );
}

class _WordBoxes extends CustomPainter {
  const _WordBoxes(this.words, this.pageSize);
  final List<Rect> words;
  final Size pageSize;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / pageSize.width, y = size.height / pageSize.height;
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xff0671a8);
    for (final rect in words) {
      if (!rect.isEmpty) {
        canvas.drawRect(
          Rect.fromLTRB(
            rect.left * x,
            rect.top * y,
            rect.right * x,
            rect.bottom * y,
          ),
          outline,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_WordBoxes old) =>
      old.words != words || old.pageSize != pageSize;
}
