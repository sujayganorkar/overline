import 'dart:convert';

import 'package:flutter/material.dart';

import 'app_notice.dart';

import '../bridge/api.dart' as bridge;
import '../services/pdf_engine.dart';

/// A link reported by `link_list`.
class PageLink {
  const PageLink({
    required this.page,
    required this.index,
    required this.destination,
  });

  final int page;
  final int index;
  final String destination;

  static PageLink? fromJson(Map<String, dynamic> json) {
    final page = (json['page'] as num?)?.toInt();
    final index = (json['index'] as num?)?.toInt();
    if (page == null || index == null) return null;
    final url = json['url'];
    final toPage = (json['to_page'] as num?)?.toInt();
    final destination = url is String && url.isNotEmpty
        ? url
        : toPage != null
        ? 'Page $toPage'
        : 'Unknown destination';
    return PageLink(page: page, index: index, destination: destination);
  }
}

/// Every link in the document, grouped by page. Tap a page to jump there;
/// delete removes the link (confirmed, undoable). Add new links by dragging
/// a box in Draw & annotate → Link.
class LinksScreen extends StatefulWidget {
  const LinksScreen({
    super.key,
    required this.engine,
    required this.handle,
    required this.onStatusChanged,
    required this.onJumpToPage,
  });

  final PdfEngineApi engine;
  final int handle;
  final ValueChanged<bridge.DocumentStatus> onStatusChanged;
  final ValueChanged<int> onJumpToPage;

  @override
  State<LinksScreen> createState() => _LinksScreenState();
}

class _LinksScreenState extends State<LinksScreen> {
  List<PageLink> _links = const [];
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
        tool: 'link_list',
        argumentsJson: '{}',
      );
      final links = <PageLink>[];
      for (final content in response.contents) {
        if (content.json.isEmpty) continue;
        final decoded = jsonDecode(content.json);
        final list = decoded is Map<String, dynamic>
            ? decoded['links']
            : decoded is List
            ? decoded
            : null;
        if (list is List) {
          for (final item in list) {
            if (item is Map<String, dynamic>) {
              final link = PageLink.fromJson(item);
              if (link != null) links.add(link);
            }
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _links = links;
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

  Future<void> _delete(PageLink link) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete link?'),
        content: Text(
          'The link to ${link.destination} on page ${link.page} is removed. The page itself stays. This is undoable.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final response = await widget.engine.executeTool(
        handle: widget.handle,
        tool: 'link_delete',
        argumentsJson: jsonEncode({'page': link.page, 'index': link.index}),
      );
      if (!mounted) return;
      widget.onStatusChanged(response.status);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      AppNotice.show(
        context,
        AppNotice(
          message: 'Could not delete the link.',
          kind: NoticeKind.error,
          details: '$e',
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_loading ? 'Links' : 'Links (${_links.length})'),
        actions: [
          IconButton(
            onPressed: _loading || _busy ? null : _reload,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : _links.isEmpty
          ? const Center(
              child: Text(
                'No links in this document.\nAdd one by dragging a box in Draw & annotate → Link.',
                textAlign: TextAlign.center,
              ),
            )
          : Stack(
              children: [
                ListView.builder(
                  itemCount: _links.length,
                  itemBuilder: (context, i) {
                    final link = _links[i];
                    return ListTile(
                      leading: const Icon(Icons.link_outlined),
                      title: Text(
                        link.destination,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text('Page ${link.page}'),
                      trailing: IconButton(
                        tooltip: 'Delete link',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _busy ? null : () => _delete(link),
                      ),
                      onTap: () {
                        widget.onJumpToPage(link.page);
                        Navigator.pop(context);
                      },
                    );
                  },
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
}
