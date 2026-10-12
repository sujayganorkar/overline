import 'dart:convert';

import 'package:flutter/material.dart';

import '../bridge/api.dart' as bridge;
import '../services/pdf_engine.dart';

/// A bookmark node from `bookmark_list` (paths are 1-based, children nested).
class BookmarkNode {
  BookmarkNode({
    required this.path,
    required this.title,
    required this.page,
    required this.children,
  });

  final List<int> path;
  final String title;
  final int? page;
  final List<BookmarkNode> children;

  static BookmarkNode? fromJson(Map<String, dynamic> json) {
    final path = json['path'];
    if (path is! List) return null;
    final kids = json['children'];
    return BookmarkNode(
      path: [
        for (final p in path)
          if (p is int) p,
      ],
      title: json['title'] as String? ?? '(untitled)',
      page: (json['page'] as num?)?.toInt(),
      children: kids is List
          ? [
              for (final k in kids)
                if (k is Map<String, dynamic>)
                  ...[BookmarkNode.fromJson(k)].whereType<BookmarkNode>(),
            ]
          : const [],
    );
  }
}

/// Bookmark outline: jump, add, rename, retarget, move, delete.
class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({
    super.key,
    required this.engine,
    required this.handle,
    required this.currentPage,
    required this.onStatusChanged,
    required this.onJumpToPage,
  });

  final PdfEngineApi engine;
  final int handle;
  final int currentPage;
  final ValueChanged<bridge.DocumentStatus> onStatusChanged;
  final ValueChanged<int> onJumpToPage;

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  List<BookmarkNode> _roots = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.engine.executeTool(
        handle: widget.handle,
        tool: 'bookmark_list',
        argumentsJson: '{}',
      );
      final roots = <BookmarkNode>[];
      for (final content in response.contents) {
        if (content.json.isEmpty) continue;
        final decoded = jsonDecode(content.json);
        final list = decoded is Map<String, dynamic>
            ? decoded['bookmarks']
            : null;
        if (list is List) {
          for (final item in list) {
            if (item is Map<String, dynamic>) {
              final node = BookmarkNode.fromJson(item);
              if (node != null) roots.add(node);
            }
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _roots = roots;
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

  Future<void> _run(String tool, Map<String, Object?> args) async {
    setState(() => _busy = true);
    try {
      final response = await widget.engine.executeTool(
        handle: widget.handle,
        tool: tool,
        argumentsJson: jsonEncode(args),
      );
      if (!mounted) return;
      widget.onStatusChanged(response.status);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$tool failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final titleController = TextEditingController();
    try {
      final title = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Add bookmark'),
          content: TextField(
            controller: titleController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Bookmark title',
              hintText: 'Title (goes to page ${widget.currentPage})',
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, titleController.text),
              child: const Text('Add'),
            ),
          ],
        ),
      );
      if (title == null || title.trim().isEmpty || !mounted) return;
      await _run('bookmark_add', {
        'title': title.trim(),
        'page': widget.currentPage,
      });
    } finally {
      titleController.dispose();
    }
  }

  Future<void> _fromHeadings() async {
    setState(() => _busy = true);
    try {
      final response = await widget.engine.executeTool(
        handle: widget.handle,
        tool: 'bookmark_from_structure',
        argumentsJson: '{}',
      );
      if (!mounted) return;
      widget.onStatusChanged(response.status);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No headings found: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename(BookmarkNode node) async {
    final controller = TextEditingController(text: node.title);
    try {
      final title = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Rename bookmark'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Bookmark title',
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
              child: const Text('Rename'),
            ),
          ],
        ),
      );
      if (title == null || title.trim().isEmpty || !mounted) return;
      await _run('bookmark_rename', {'path': node.path, 'title': title.trim()});
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bookmarks'),
        actions: [
          IconButton(
            onPressed: _loading || _busy ? null : _add,
            icon: const Icon(Icons.add),
            tooltip: 'Add bookmark for current page',
          ),
          IconButton(
            onPressed: _loading || _busy ? null : _fromHeadings,
            icon: const Icon(Icons.account_tree_outlined),
            tooltip: 'Build from headings',
          ),
          IconButton(
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : _roots.isEmpty
          ? const Center(
              child: Text(
                'No bookmarks.\nAdd one for the current page with +.',
                textAlign: TextAlign.center,
              ),
            )
          : Stack(
              children: [
                ListView(
                  children: [for (final node in _roots) _nodeTile(node, 0)],
                ),
                if (_busy)
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
    );
  }

  Widget _nodeTile(BookmarkNode node, int depth) {
    final subtitle = node.page == null ? 'No destination' : 'Page ${node.page}';
    final tile = ListTile(
      contentPadding: EdgeInsets.only(left: 16.0 + depth * 20.0, right: 8),
      leading: const Icon(Icons.bookmark_outline, size: 20),
      title: Text(node.title),
      subtitle: Text(subtitle),
      onTap: node.page == null
          ? null
          : () {
              widget.onJumpToPage(node.page!);
              Navigator.pop(context);
            },
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 20),
        onSelected: (choice) {
          switch (choice) {
            case 'rename':
              _rename(node);
            case 'retarget':
              _run('bookmark_set_page', {
                'path': node.path,
                'page': widget.currentPage,
              });
            case 'delete':
              _confirmDelete(node);
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'rename', child: Text('Rename')),
          PopupMenuItem(
            value: 'retarget',
            child: Text('Point at current page'),
          ),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
    if (node.children.isEmpty) return tile;
    return ExpansionTile(
      leading: const Icon(Icons.bookmark_outline, size: 20),
      title: Text(node.title),
      subtitle: Text(subtitle),
      children: [
        for (final child in node.children) _nodeTile(child, depth + 1),
      ],
    );
  }

  Future<void> _confirmDelete(BookmarkNode node) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete bookmark?'),
        content: Text(
          '“${node.title}” and its sub-bookmarks will be removed. Undoable.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _run('bookmark_delete', {'path': node.path});
    }
  }
}
