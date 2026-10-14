import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/pdf_engine.dart';

/// A find match from `text_find`.
class FindMatch {
  const FindMatch({
    required this.page,
    required this.text,
    this.rects = const [],
  });

  final int page;
  final String text;
  final List<List<double>> rects;
}

/// In-viewer find bar: query, match count, previous/next navigation.
/// Tapping a navigation button jumps the viewer to the match's page.
class FindBar extends StatefulWidget {
  const FindBar({
    super.key,
    this.engine,
    this.handle = 0,
    this.onJumpToPage,
    required this.onClose,
    this.onMatchesChanged,
    this.onActiveIndexChanged,
    this.controller,
    this.matchIndex,
    this.matchCount,
    this.onPrevious,
    this.onNext,
  });

  final PdfEngineApi? engine;
  final int handle;
  final ValueChanged<int>? onJumpToPage;
  final VoidCallback onClose;
  final ValueChanged<List<FindMatch>>? onMatchesChanged;
  final ValueChanged<int>? onActiveIndexChanged;
  final TextEditingController? controller;
  final int? matchIndex;
  final int? matchCount;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  State<FindBar> createState() => _FindBarState();
}

class _FindBarState extends State<FindBar> {
  late final TextEditingController _controller;
  List<FindMatch> _matches = const [];
  int _index = 0;
  bool _searching = false;
  String? _error;
  bool _complete = true;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
  }

  @override
  void dispose() {
    widget.onMatchesChanged?.call(const []);
    widget.onActiveIndexChanged?.call(-1);
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  Future<void> _search() async {
    final engine = widget.engine;
    if (engine == null) return;
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final response = await engine.executeTool(
        handle: widget.handle,
        tool: 'text_find',
        argumentsJson: jsonEncode({'query': query, 'limit': 200}),
      );
      final matches = <FindMatch>[];
      var complete = true;
      for (final content in response.contents) {
        if (content.json.isEmpty) continue;
        final decoded = jsonDecode(content.json);
        final list = decoded is Map<String, dynamic>
            ? decoded['matches']
            : null;
        if (list is List) {
          for (final item in list) {
            if (item is Map<String, dynamic>) {
              final page = (item['page'] as num?)?.toInt();
              if (page != null) {
                final rawRects = item['rects'];
                final rects = <List<double>>[];
                if (rawRects is List) {
                  for (final r in rawRects) {
                    if (r is List && r.length == 4) {
                      rects.add([for (final v in r) (v as num).toDouble()]);
                    }
                  }
                }
                matches.add(
                  FindMatch(
                    page: page,
                    text: item['text'] as String? ?? '',
                    rects: rects,
                  ),
                );
              }
            }
          }
        }
        if (decoded is Map<String, dynamic> && decoded['complete'] == false) {
          complete = false;
        }
      }
      if (!mounted) return;
      setState(() {
        _matches = matches;
        _index = 0;
        _complete = complete;
      });
      widget.onMatchesChanged?.call(matches);
      widget.onActiveIndexChanged?.call(matches.isEmpty ? -1 : 0);
      if (matches.isNotEmpty) widget.onJumpToPage?.call(matches.first.page);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _step(int delta) {
    if (widget.onPrevious != null && delta < 0) {
      widget.onPrevious!();
      return;
    }
    if (widget.onNext != null && delta > 0) {
      widget.onNext!();
      return;
    }
    if (_matches.isEmpty) return;
    setState(() {
      _index = (_index + delta) % _matches.length;
      if (_index < 0) _index += _matches.length;
    });
    widget.onActiveIndexChanged?.call(_index);
    widget.onJumpToPage?.call(_matches[_index].page);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveIndex = widget.matchIndex ?? _index;
    final totalCount = widget.matchCount ?? _matches.length;
    final label = (widget.matchCount != null)
        ? '${effectiveIndex + 1} of $totalCount'
        : _matches.isEmpty
        ? (_error ?? 'Find in document')
        : '${effectiveIndex + 1} of $totalCount${_complete ? '' : '+'}';
    final hasMatches = widget.matchCount != null
        ? widget.matchCount! > 0
        : _matches.isNotEmpty;

    return Material(
      elevation: 6,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(16),
      color: theme.colorScheme.surface.withValues(alpha: 0.96),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  labelText: 'Find in PDF',
                  hintText: 'Type keyword…',
                  border: InputBorder.none,
                  prefixIcon: Icon(Icons.search, size: 20),
                  isDense: true,
                ),
                onSubmitted: (_) => _search(),
              ),
            ),
            if (_searching)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Semantics(
                liveRegion: true,
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            IconButton(
              onPressed: hasMatches ? () => _step(-1) : null,
              icon: const Icon(Icons.keyboard_arrow_up, size: 20),
              tooltip: 'Previous match',
            ),
            IconButton(
              onPressed: hasMatches ? () => _step(1) : null,
              icon: const Icon(Icons.keyboard_arrow_down, size: 20),
              tooltip: 'Next match',
            ),
            IconButton(
              onPressed: _search,
              icon: const Icon(Icons.arrow_forward, size: 20),
              tooltip: 'Search',
            ),
            IconButton(
              onPressed: widget.onClose,
              icon: const Icon(Icons.close, size: 20),
              tooltip: 'Close search',
            ),
          ],
        ),
      ),
    );
  }
}
