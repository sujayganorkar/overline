import 'dart:convert';

import 'package:flutter/material.dart';

import 'app_notice.dart';
import 'comment_composer.dart';

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

class CommentsScreen extends StatefulWidget {
  const CommentsScreen({
    super.key,
    required this.engine,
    required this.handle,
    required this.onStatusChanged,
    required this.onJumpToPage,
    required this.onAddComment,
    this.currentPage = 1,
    this.pageCount = 1,
    this.initialPage,
    this.focusIndex,
  });
  final PdfEngineApi engine;
  final int handle, currentPage, pageCount;
  final ValueChanged<bridge.DocumentStatus> onStatusChanged;
  final ValueChanged<int> onJumpToPage;
  final Future<void> Function(int page) onAddComment;
  final int? initialPage, focusIndex;
  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  List<CommentThread> _threads = [];
  CommentThread? _selected;
  bool _loading = true, _busy = false, _initialFocus = true;
  bool _allAnnotations = false, _composing = false;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _query = '', _filter = 'all';
  String? _error;
  int? _page;
  bool get _disabled => _loading || _busy;
  String _key(CommentThread t) =>
      t.id.isNotEmpty ? t.id : '${t.page}:${t.index}';
  bool _resolved(CommentThread t) => t.status.toLowerCase() == 'completed';
  Map<String, Object?> _target(CommentThread t) =>
      t.id.isNotEmpty ? {'id': t.id} : {'page': t.page, 'index': t.index};

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage;
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
        argumentsJson: '{}',
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
      final previous = _selected;
      CommentThread? selected;
      for (final t in threads) {
        if (previous != null && _key(t) == _key(previous)) selected = t;
        if (_initialFocus &&
            widget.focusIndex == t.index &&
            (widget.initialPage ?? widget.currentPage) == t.page) {
          selected = t;
        }
      }
      setState(() {
        _threads = threads;
        _selected = selected;
        _initialFocus = false;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load notes. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _mutate(String tool, Map<String, Object?> args) async {
    final response = await widget.engine.executeTool(
      handle: widget.handle,
      tool: tool,
      argumentsJson: jsonEncode(args),
    );
    widget.onStatusChanged(response.status);
  }

  Future<void> _run(String tool, Map<String, Object?> args) async {
    if (_disabled) return;
    setState(() => _busy = true);
    try {
      await _mutate(tool, args);
      if (!mounted) return;
      if (tool == 'comment_delete') setState(() => _selected = null);
      await _reload();
      if (mounted && tool == 'comment_delete') {
        AppNotice.show(
          context,
          AppNotice(
            message: 'Conversation deleted.',
            kind: NoticeKind.success,
            action: NoticeAction(
              label: 'Undo',
              onPressed: () => _run('edit_undo', {}),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        AppNotice.show(
          context,
          AppNotice(
            message: 'Could not ${_commentAction(tool)}.',
            kind: NoticeKind.error,
            details: '$e',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _compose(CommentThread t, {bool edit = false}) async {
    if (_disabled || t.locked) return;
    setState(() {
      _busy = true;
      _composing = true;
    });
    try {
      final saved = await CommentComposer.show(
        context,
        title: edit ? 'Edit note' : 'Reply to note',
        page: t.page,
        submitLabel: edit ? 'Save changes' : 'Add reply',
        initialText: edit ? t.contents : '',
        contextText: edit ? null : t.contents,
        onSubmit: (text) => _mutate(edit ? 'comment_edit' : 'comment_reply', {
          ..._target(t),
          if (edit) 'contents': text else 'text': text,
        }),
      );
      if (saved == true && mounted) await _reload();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _composing = false;
        });
      }
    }
  }

  Future<void> _addComment() async {
    if (_disabled) return;
    int chosen = _page ?? widget.currentPage;
    final page = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Add a note'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Choose a page, then tap where the note belongs.'),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: chosen,
                decoration: const InputDecoration(
                  labelText: 'Page',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (var p = 1; p <= widget.pageCount; p++)
                    DropdownMenuItem(value: p, child: Text('Page $p')),
                ],
                onChanged: (value) {
                  if (value != null) update(() => chosen = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, chosen),
              child: const Text('Place note'),
            ),
          ],
        ),
      ),
    );
    if (page == null || !mounted) return;
    final before = _threads.map(_key).toSet();
    setState(() => _busy = true);
    try {
      await widget.onAddComment(page);
      if (!mounted) return;
      await _reload();
      if (!mounted) return;
      for (final t in _threads) {
        if (t.page == page && !before.contains(_key(t))) {
          setState(() {
            _selected = t;
            _page = null;
          });
          break;
        }
      }
    } catch (e) {
      if (mounted) {
        AppNotice.show(
          context,
          AppNotice(
            message: 'Could not open the page for your note.',
            kind: NoticeKind.error,
            details: '$e',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _more(String action, CommentThread t) async {
    if (_disabled) return;
    if (action == 'edit') {
      await _compose(t, edit: true);
      return;
    }
    if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete conversation?'),
          content: const Text(
            'This removes the note and all replies from the PDF. You can undo this.',
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
      if (ok == true) await _run('comment_delete', _target(t));
    } else if (action == 'lock') {
      await _run('comment_lock', {..._target(t), 'locked': !t.locked});
    } else if (action == 'mark') {
      await _run('comment_mark', {..._target(t), 'marked': !t.marked});
    } else if (action == 'status') {
      final status = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Review status'),
          children: [
            for (final entry in {
              'none': 'Open',
              'accepted': 'Accepted',
              'rejected': 'Rejected',
              'cancelled': 'Cancelled',
              'completed': 'Resolved',
            }.entries)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, entry.key),
                child: Text(entry.value),
              ),
          ],
        ),
      );
      if (status != null) {
        await _run('comment_set_status', {..._target(t), 'status': status});
      }
    }
  }

  Future<void> _summarize() async {
    if (_disabled) return;
    setState(() => _busy = true);
    try {
      final response = await widget.engine.executeTool(
        handle: widget.handle,
        tool: 'comments_summarize',
        argumentsJson: '{"out":"outputs/comments-summary.pdf"}',
      );
      if (mounted) {
        await saveToolOutputs(context, widget.engine, [
          for (final c in response.contents) c.json,
        ]);
      }
    } catch (e) {
      if (mounted) {
        AppNotice.show(
          context,
          AppNotice(
            message: 'Could not export notes.',
            kind: NoticeKind.error,
            details: '$e',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _conversation(CommentThread t) => Column(
    children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(label: Text('Page ${t.page}')),
                Chip(
                  label: Text(
                    _resolved(t)
                        ? 'Resolved'
                        : t.status.toLowerCase() == 'none'
                        ? 'Open'
                        : t.status,
                  ),
                ),
                if (t.locked)
                  const Chip(
                    avatar: Icon(Icons.lock_outline, size: 16),
                    label: Text('Locked'),
                  ),
                if (t.marked) const Chip(label: Text('Checked')),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              t.author.isEmpty ? 'Note' : t.author,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            SelectableText(
              t.contents.isEmpty
                  ? 'No text on this ${t.type} annotation.'
                  : t.contents,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _disabled
                    ? null
                    : () {
                        Navigator.pop(context);
                        widget.onJumpToPage(t.page);
                      },
                icon: const Icon(Icons.find_in_page_outlined),
                label: const Text('Show on page'),
              ),
            ),
            const Divider(height: 32),
            Text(
              '${t.replies.length} ${t.replies.length == 1 ? 'reply' : 'replies'}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            if (t.replies.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Add a reply to continue this conversation.'),
              ),
            for (final r in t.replies)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.author.isEmpty ? 'Reply' : r.author,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        SelectableText(r.contents),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (t.locked)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Unlock this note in More options to make changes.',
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _disabled || t.locked
                          ? null
                          : () => _compose(t),
                      icon: const Icon(Icons.reply),
                      label: const Text('Reply'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _disabled || t.locked
                          ? null
                          : () => _run('comment_set_status', {
                              ..._target(t),
                              'status': _resolved(t) ? 'none' : 'completed',
                            }),
                      icon: Icon(_resolved(t) ? Icons.refresh : Icons.check),
                      label: Text(_resolved(t) ? 'Reopen' : 'Resolve'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _list() {
    final visible = _threads
        .where(
          (t) =>
              (_page == null || t.page == _page) &&
              (_filter == 'all' || (_filter == 'resolved') == _resolved(t)) &&
              (_allAnnotations ||
                  t.type == 'note' ||
                  t.type == 'text' ||
                  t.contents.isNotEmpty ||
                  t.replies.isNotEmpty) &&
              (t.contents.toLowerCase().contains(_query) ||
                  t.author.toLowerCase().contains(_query) ||
                  t.replies.any(
                    (r) => '${r.author} ${r.contents}'.toLowerCase().contains(
                      _query,
                    ),
                  )),
        )
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(
              hintText: 'Search notes and replies',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _query = v.toLowerCase().trim()),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              for (final e in {
                'all': 'All',
                'open': 'Open',
                'resolved': 'Resolved',
              }.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(e.value),
                    selected: _filter == e.key,
                    onSelected: (_) => setState(() => _filter = e.key),
                  ),
                ),
              FilterChip(
                label: Text(
                  _page == null
                      ? 'Page ${widget.currentPage} only'
                      : 'Page $_page only',
                ),
                selected: _page != null,
                onSelected: (v) =>
                    setState(() => _page = v ? widget.currentPage : null),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('All annotations'),
                selected: _allAnnotations,
                onSelected: (v) => setState(() => _allAnnotations = v),
              ),
            ],
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _threads.isEmpty
                          ? 'No notes yet. Add a note where it belongs on the page.'
                          : 'No notes match these filters.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: visible.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, indent: 72),
                  itemBuilder: (context, i) {
                    final t = visible[i];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      leading: CircleAvatar(
                        child: Icon(
                          _resolved(t)
                              ? Icons.check
                              : Icons.chat_bubble_outline,
                        ),
                      ),
                      title: Text(
                        t.contents.isEmpty
                            ? '${t.type} annotation'
                            : t.contents,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        'Page ${t.page} · ${t.replies.length} replies${t.author.isEmpty ? '' : ' · ${t.author}'}${t.locked ? ' · Locked' : ''}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _disabled
                          ? null
                          : () => setState(() => _selected = t),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _selected;
    return PopScope(
      canPop: !_busy && t == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy && t != null) setState(() => _selected = null);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(t == null ? 'Notes & comments' : 'Conversation'),
          leading: BackButton(
            onPressed: _busy
                ? null
                : () {
                    if (t != null) {
                      setState(() => _selected = null);
                    } else {
                      Navigator.pop(context);
                    }
                  },
          ),
          actions: [
            if (t != null)
              PopupMenuButton<String>(
                tooltip: 'More options',
                enabled: !_disabled,
                onSelected: (action) => _more(action, t),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'edit',
                    enabled: !t.locked,
                    child: const Text('Edit note'),
                  ),
                  PopupMenuItem(
                    value: 'status',
                    enabled: !t.locked,
                    child: const Text('Review status'),
                  ),
                  PopupMenuItem(
                    value: 'mark',
                    enabled: !t.locked,
                    child: Text(
                      t.marked ? 'Remove checkmark' : 'Mark as checked',
                    ),
                  ),
                  PopupMenuItem(
                    value: 'lock',
                    child: Text(t.locked ? 'Unlock note' : 'Lock note'),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    enabled: !t.locked,
                    child: const Text('Delete conversation'),
                  ),
                ],
              )
            else
              IconButton(
                tooltip: 'Export notes to PDF',
                onPressed: _disabled ? null : _summarize,
                icon: const Icon(Icons.ios_share),
              ),
          ],
        ),
        body: Column(
          children: [
            if (_loading || (_busy && !_composing))
              const LinearProgressIndicator(),
            if (_error != null)
              MaterialBanner(
                content: Text(_error!),
                actions: [
                  TextButton(
                    onPressed: _disabled ? null : _reload,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            Expanded(child: t == null ? _list() : _conversation(t)),
          ],
        ),
        floatingActionButton: t == null
            ? FloatingActionButton.extended(
                onPressed: _disabled ? null : _addComment,
                icon: const Icon(Icons.add_comment_outlined),
                label: const Text('Add note'),
              )
            : null,
      ),
    );
  }
}
