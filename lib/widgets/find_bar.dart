import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/pdf_engine.dart';

/// A find match from `text_find`.
class FindMatch {
  const FindMatch({required this.page, required this.text});

  final int page;
  final String text;
}

/// In-viewer find bar: query, match count, previous/next navigation.
/// Tapping a navigation button jumps the viewer to the match's page.
class FindBar extends StatefulWidget {
  const FindBar({
    super.key,
    required this.engine,
    required this.handle,
    required this.onJumpToPage,
    required this.onClose,
  });

  final PdfEngineApi engine;
  final int handle;
  final ValueChanged<int> onJumpToPage;
  final VoidCallback onClose;

  @override
  State<FindBar> createState() => _FindBarState();
}

class _FindBarState extends State<FindBar> {
  final _controller = TextEditingController();
  List<FindMatch> _matches = const [];
  int _index = 0;
  bool _searching = false;
  String? _error;
  bool _complete = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final response = await widget.engine.executeTool(
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
                matches.add(
                  FindMatch(page: page, text: item['text'] as String? ?? ''),
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
      if (matches.isNotEmpty) widget.onJumpToPage(matches.first.page);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _step(int delta) {
    if (_matches.isEmpty) return;
    setState(() {
      _index = (_index + delta) % _matches.length;
      if (_index < 0) _index += _matches.length;
    });
    widget.onJumpToPage(_matches[_index].page);
  }

  @override
  Widget build(BuildContext context) {
    final label = _matches.isEmpty
        ? (_error ?? 'Find in document')
        : '${_index + 1} of ${_matches.length}${_complete ? '' : '+'}';
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  hintText: 'Find',
                  border: InputBorder.none,
                  prefixIcon: Icon(Icons.search, size: 20),
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
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            IconButton(
              onPressed: _matches.isEmpty ? null : () => _step(-1),
              icon: const Icon(Icons.keyboard_arrow_up, size: 20),
              tooltip: 'Previous match',
            ),
            IconButton(
              onPressed: _matches.isEmpty ? null : () => _step(1),
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
              tooltip: 'Close find',
            ),
          ],
        ),
      ),
    );
  }
}
