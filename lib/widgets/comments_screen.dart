import 'dart:convert';

import 'package:flutter/material.dart';

import 'app_notice.dart';

import '../bridge/api.dart' as bridge;
import '../services/pdf_engine.dart';
import 'output_saver.dart';

/// A comment thread from `comment_list`, with nested replies flattened in
/// document order by the engine.
class CommentThread {
  CommentThread({
    required this.id,
    required this.page,
    required this.index,
    required this.type,
    required this.author,
    required this.contents,
    required this.modified,
    required this.status,
    required this.marked,
    required this.locked,
    required this.replies,
  });

  final String id;
  final int page;
  final int index;
  final String type;
  final String author;
  final String contents;
  final String modified;
  final String status;
  final bool marked;
  final bool locked;
  final List<CommentReply> replies;

  static CommentThread? fromJson(Map<String, dynamic> json) {
    final page = (json['page'] as num?)?.toInt();
    final index = (json['index'] as num?)?.toInt();
    if (page == null || index == null) return null;
    final replies = json['replies'];
    return CommentThread(
      id: json['id'] as String? ?? '',
      page: page,
      index: index,
      type: json['type'] as String? ?? 'comment',
      author: json['author'] as String? ?? '',
      contents: json['contents'] as String? ?? '',
      modified: json['modified'] as String? ?? '',
      status: json['status'] as String? ?? 'none',
      marked: json['marked'] == true,
      locked: json['locked'] == true,
      replies: replies is List
          ? [
              for (final r in replies)
                if (r is Map<String, dynamic>)
                  CommentReply(
                    author: r['author'] as String? ?? '',
                    contents: r['contents'] as String? ?? '',
                    modified: r['modified'] as String? ?? '',
                  ),
            ]
          : const [],
    );
  }
}

String _commentAction(String tool) => switch (tool) {
  'comment_reply' => 'send your reply',
  'comment_set_status' => 'change the review status',
  'comment_mark' => 'mark the comment',
  'comment_lock' => 'change the lock',
  'comment_edit' => 'edit the comment',
  'comment_delete' => 'delete the comment',
  _ => 'complete that comment action',
};

class CommentReply {
  const CommentReply({
    required this.author,
    required this.contents,
    required this.modified,
  });

  final String author;
  final String contents;
  final String modified;
}

/// Threaded comments: list, reply, review status, checkmark, lock, edit,
/// delete. All actions run the matching `comment_*` operation and report
/// back through [onStatusChanged] so the viewer refreshes.
class CommentsScreen extends StatefulWidget {
  const CommentsScreen({
    super.key,
    required this.engine,
    required this.handle,
    required this.onStatusChanged,
    required this.onJumpToPage,
    required this.onAddComment,
    this.initialPage,
    this.focusIndex,
  });

  final PdfEngineApi engine;
  final int handle;
  final ValueChanged<bridge.DocumentStatus> onStatusChanged;
  final ValueChanged<int> onJumpToPage;
  final Future<void> Function() onAddComment;
  final int? initialPage;
  final int? focusIndex;

  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  final _focusedCommentKey = GlobalKey();
  List<CommentThread> _threads = const [];
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
        tool: 'comment_list',
        argumentsJson: jsonEncode({
          if (widget.initialPage != null) 'page': widget.initialPage,
        }),
      );
      final threads = <CommentThread>[];
      for (final content in response.contents) {
        if (content.json.isEmpty) continue;
        final decoded = jsonDecode(content.json);
        final list = decoded is Map<String, dynamic>
            ? decoded['comments']
            : null;
        if (list is List) {
          for (final item in list) {
            if (item is Map<String, dynamic>) {
              final thread = CommentThread.fromJson(item);
              if (thread != null) threads.add(thread);
            }
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _threads = threads;
        _loading = false;
      });
      if (widget.focusIndex != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final target = _focusedCommentKey.currentContext;
          if (target != null) {
            Scrollable.ensureVisible(
              target,
              alignment: 0.2,
              duration: const Duration(milliseconds: 250),
            );
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _addComment() async {
    if (_loading || _busy) return;
    await widget.onAddComment();
    if (mounted) await _reload();
  }

  Future<void> _run(
    String tool,
    Map<String, Object?> args, {
    bool confirmDelete = false,
  }) async {
    if (confirmDelete) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete comment?'),
          content: const Text(
            'The comment and its replies will be removed. This is undoable.',
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
      if (ok != true || !mounted) return;
    }
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
      AppNotice.show(
        context,
        AppNotice(
          message: 'Could not ${_commentAction(tool)}.',
          kind: NoticeKind.error,
          details: '$e',
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, Object?> _target(CommentThread thread) => {
    'page': thread.page,
    'index': thread.index,
  };

  Future<void> _summarize() async {
    setState(() => _busy = true);
    try {
      final response = await widget.engine.executeTool(
        handle: widget.handle,
        tool: 'comments_summarize',
        argumentsJson: '{"out": "outputs/comments-summary.pdf"}',
      );
      if (!mounted) return;
      await saveToolOutputs(context, widget.engine, [
        for (final c in response.contents) c.json,
      ]);
    } catch (e) {
      if (!mounted) return;
      AppNotice.show(
        context,
        AppNotice(
          message: 'Summarize failed.',
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
        title: Text(
          _loading
              ? 'Comments'
              : 'Comments${widget.initialPage == null ? '' : ' · page ${widget.initialPage}'} (${_threads.length})',
        ),
        actions: [
          IconButton(
            onPressed: _loading || _busy ? null : _addComment,
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'Add a note to the current page',
          ),
          IconButton(
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          IconButton(
            onPressed: _loading || _busy ? null : _summarize,
            icon: const Icon(Icons.summarize_outlined),
            tooltip: 'Summarize to PDF',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : _threads.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'No comments yet. Add a note to start a conversation.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _loading || _busy ? null : _addComment,
                    icon: const Icon(Icons.add_comment_outlined),
                    label: const Text('Add a note'),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: _threads.length,
                  itemBuilder: (context, i) => _ThreadCard(
                    key: _threads[i].index == widget.focusIndex
                        ? _focusedCommentKey
                        : ValueKey('${_threads[i].page}-${_threads[i].index}'),
                    thread: _threads[i],
                    onJump: () {
                      widget.onJumpToPage(_threads[i].page);
                      Navigator.pop(context);
                    },
                    onReply: (text) => _run('comment_reply', {
                      ..._target(_threads[i]),
                      'text': text,
                    }),
                    onStatus: (status) => _run('comment_set_status', {
                      ..._target(_threads[i]),
                      'status': status,
                    }),
                    onMark: (marked) => _run('comment_mark', {
                      ..._target(_threads[i]),
                      'marked': marked,
                    }),
                    onLock: (locked) => _run('comment_lock', {
                      ..._target(_threads[i]),
                      'locked': locked,
                    }),
                    onEdit: (contents) => _run('comment_edit', {
                      ..._target(_threads[i]),
                      'contents': contents,
                    }),
                    onDelete: () => _run(
                      'comment_delete',
                      _target(_threads[i]),
                      confirmDelete: true,
                    ),
                    highlighted: _threads[i].index == widget.focusIndex,
                  ),
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

class _ThreadCard extends StatelessWidget {
  const _ThreadCard({
    super.key,
    required this.thread,
    required this.onJump,
    required this.onReply,
    required this.onStatus,
    required this.onMark,
    required this.onLock,
    required this.onEdit,
    required this.onDelete,
    this.highlighted = false,
  });

  final CommentThread thread;
  final VoidCallback onJump;
  final ValueChanged<String> onReply;
  final ValueChanged<String> onStatus;
  final ValueChanged<bool> onMark;
  final ValueChanged<bool> onLock;
  final ValueChanged<String> onEdit;
  final VoidCallback onDelete;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: highlighted
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_iconFor(thread.type), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_labelFor(thread.type)} · p${thread.page}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (thread.status != 'none')
                  Chip(
                    label: Text(thread.status),
                    visualDensity: VisualDensity.compact,
                  ),
                if (thread.marked)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.check_circle, size: 18),
                  ),
                if (thread.locked)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.lock, size: 18),
                  ),
              ],
            ),
            if (thread.author.isNotEmpty || thread.modified.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  [
                    thread.author,
                    thread.modified,
                  ].where((s) => s.isNotEmpty).join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (thread.contents.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(thread.contents),
              ),
            for (final reply in thread.replies)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reply.author.isEmpty ? 'Reply' : reply.author,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(reply.contents),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 0,
              children: [
                TextButton.icon(
                  onPressed: onJump,
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('View'),
                ),
                TextButton.icon(
                  onPressed: () => _replyDialog(context, onReply),
                  icon: const Icon(Icons.reply_outlined, size: 18),
                  label: const Text('Reply'),
                ),
                TextButton.icon(
                  onPressed: () => _statusDialog(context, onStatus),
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: const Text('Status'),
                ),
                IconButton(
                  onPressed: () => onMark(!thread.marked),
                  icon: Icon(
                    thread.marked
                        ? Icons.check_circle
                        : Icons.check_circle_outlined,
                    size: 20,
                  ),
                  tooltip: thread.marked ? 'Unmark' : 'Mark done',
                ),
                IconButton(
                  onPressed: () => onLock(!thread.locked),
                  icon: Icon(
                    thread.locked ? Icons.lock : Icons.lock_open_outlined,
                    size: 20,
                  ),
                  tooltip: thread.locked ? 'Unlock' : 'Lock',
                ),
                IconButton(
                  onPressed: () =>
                      _editDialog(context, thread.contents, onEdit),
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: 'Edit text',
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outlined, size: 20),
                  tooltip: 'Delete',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(String type) => switch (type.toLowerCase()) {
    'highlight' => Icons.highlight_outlined,
    'underline' => Icons.format_underline,
    'strikeout' || 'strike_out' => Icons.format_strikethrough,
    'note' || 'text' => Icons.sticky_note_2_outlined,
    'ink' => Icons.brush_outlined,
    'freetext' => Icons.text_fields_outlined,
    _ => Icons.comment_outlined,
  };

  static String _labelFor(String type) {
    if (type.isEmpty) return 'Comment';
    return switch (type.toLowerCase()) {
      'text' => 'Note',
      'freetext' || 'typewriter' => 'Text box',
      'strikeout' || 'strike_out' => 'Strikethrough',
      'square' || 'rectangle' => 'Rectangle',
      _ => '${type[0].toUpperCase()}${type.substring(1).toLowerCase()}',
    };
  }

  static Future<void> _replyDialog(
    BuildContext context,
    ValueChanged<String> onReply,
  ) async {
    final controller = TextEditingController();
    try {
      final text = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Reply'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Reply',
              hintText: 'Write a reply',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Reply'),
            ),
          ],
        ),
      );
      if (text != null && text.trim().isNotEmpty) onReply(text.trim());
    } finally {
      controller.dispose();
    }
  }

  static Future<void> _statusDialog(
    BuildContext context,
    ValueChanged<String> onStatus,
  ) async {
    const statuses = ['none', 'accepted', 'rejected', 'cancelled', 'completed'];
    final status = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Review status'),
        children: [
          for (final s in statuses)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, s),
              child: Text(s),
            ),
        ],
      ),
    );
    if (status != null) onStatus(status);
  }

  static Future<void> _editDialog(
    BuildContext context,
    String current,
    ValueChanged<String> onEdit,
  ) async {
    final controller = TextEditingController(text: current);
    try {
      final text = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Edit comment'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Comment text',
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
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (text != null && text.trim().isNotEmpty) onEdit(text.trim());
    } finally {
      controller.dispose();
    }
  }
}
