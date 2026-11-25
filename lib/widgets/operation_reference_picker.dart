import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/pdf_engine.dart';

/// Resolve engine-local references from the open PDF when a form would otherwise
/// ask the reader for a numeric index, generation or bookmark path.
class OperationReferencePicker extends StatefulWidget {
  const OperationReferencePicker({
    super.key,
    required this.engine,
    required this.handle,
    required this.tool,
    required this.properties,
    required this.page,
    required this.onSelected,
  });
  final PdfEngineApi engine;
  final int handle, page;
  final String tool;
  final Map<String, dynamic> properties;
  final ValueChanged<Map<String, dynamic>> onSelected;

  @override
  State<OperationReferencePicker> createState() =>
      _OperationReferencePickerState();
}

class _ReferenceSource {
  const _ReferenceSource(
    this.tool,
    this.list,
    this.field,
    this.label, {
    this.onPage = false,
    this.multi = false,
  });
  final String tool, list, field, label;
  final bool onPage, multi;
}

class _Choice {
  const _Choice(this.label, this.value, {this.detail});
  final String label;
  final String? detail;
  final Object value;
}

class _OperationReferencePickerState extends State<OperationReferencePicker> {
  bool busy = false;
  String? error;
  _ReferenceSource? get source {
    final tool = widget.tool;
    final props = widget.properties;
    if (tool.startsWith('accessibility_') &&
        props.containsKey('object') &&
        props.containsKey('generation')) {
      return const _ReferenceSource(
        'accessibility_tags',
        'tags',
        'object',
        'a structure tag',
      );
    }
    if (tool == 'comments_copy') {
      return const _ReferenceSource(
        'comment_list',
        'comments',
        'comments',
        'comments',
        multi: true,
      );
    }
    if (tool == 'comment_popup' ||
        tool.startsWith('comment_') &&
            props.containsKey('id') &&
            props.containsKey('index')) {
      return const _ReferenceSource(
        'comment_list',
        'comments',
        'index',
        'a comment',
      );
    }
    if (tool == 'link_open' ||
        tool == 'link_run_javascript' ||
        tool == 'link_edit') {
      return const _ReferenceSource('link_list', 'links', 'index', 'a link');
    }
    if (tool == 'content_copy' || tool == 'content_update') {
      return const _ReferenceSource(
        'content_list',
        'items',
        'index',
        'added content',
      );
    }
    if (tool.startsWith('page_template_')) {
      return const _ReferenceSource(
        'page_templates',
        'templates',
        'name',
        'a template',
      );
    }
    if (tool == 'bookmark_from_text_styles') {
      return const _ReferenceSource(
        'text_styles',
        'styles',
        'levels',
        'heading styles',
        multi: true,
      );
    }
    if (tool == 'object_move' || tool == 'object_copy') {
      return const _ReferenceSource(
        'object_list',
        'objects',
        'objects',
        'page objects',
        onPage: true,
        multi: true,
      );
    }
    if (tool == 'layer_set') {
      return const _ReferenceSource('doc_info', 'layers', 'layer', 'a layer');
    }
    if (tool == 'attachment_delete' || tool == 'attachment_edit') {
      return _ReferenceSource(
        'doc_info',
        'attachments',
        tool == 'attachment_edit' ? 'key' : 'name',
        'an attachment',
      );
    }
    if (props.containsKey('field') && props['field']['type'] == 'string') {
      return const _ReferenceSource(
        'form_fields',
        'fields',
        'field',
        'a form field',
      );
    }
    // The optional subtree path on bookmark_copy belongs to a second PDF.
    // This chooser shows bookmarks from the current destination document.
    if (tool == 'bookmark_copy' || tool == 'bookmark_import') {
      return const _ReferenceSource(
        'bookmark_list',
        'bookmarks',
        'parent',
        'a destination bookmark',
      );
    }
    if (tool.startsWith('bookmark_') && props['path']?['type'] == 'array') {
      return const _ReferenceSource(
        'bookmark_list',
        'bookmarks',
        'path',
        'a bookmark',
      );
    }
    if (props.containsKey('paragraph')) {
      return const _ReferenceSource(
        'text_paragraphs',
        'paragraphs',
        'paragraph',
        'a paragraph',
        onPage: true,
      );
    }
    if (props['image']?['type'] == 'integer') {
      return const _ReferenceSource(
        'page_images',
        'images',
        'image',
        'an image',
        onPage: true,
      );
    }
    return null;
  }

  List<_Choice> _choices(_ReferenceSource source, List list) {
    final choices = <_Choice>[];
    for (final (index, raw) in list.whereType<Map>().indexed) {
      final row = raw.cast<String, dynamic>();
      switch (source.list) {
        case 'comments':
          if (row['page'] is int && row['index'] is int) {
            choices.add(
              _Choice(
                row['contents']?.toString().trim().isNotEmpty == true
                    ? row['contents']
                    : row['type'] ?? 'Comment',
                source.multi
                    ? [row['page'], row['index']]
                    : {'page': row['page'], 'index': row['index']},
                detail: 'Page ${row['page']} · ${row['type'] ?? 'Comment'}',
              ),
            );
          }
        case 'templates':
          if (row['name'] is String) {
            choices.add(
              _Choice(
                row['name'],
                row['name'],
                detail: row['hidden'] == true ? 'Hidden' : 'Visible',
              ),
            );
          }
        case 'links':
        case 'items':
          if (row['page'] is int && row['index'] is int) {
            choices.add(
              _Choice(
                row['text']?.toString() ??
                    row['url']?.toString() ??
                    row['type']?.toString() ??
                    'Link ${row['index']}',
                {'page': row['page'], 'index': row['index']},
                detail: 'Page ${row['page']}',
              ),
            );
          }
        case 'tags':
          if (row['object'] is int && row['generation'] is int) {
            choices.add(
              _Choice(
                row['title'] ??
                    row['alternate_text'] ??
                    row['actual_text'] ??
                    '${row['type']} · ${row['object']}',
                {'object': row['object'], 'generation': row['generation']},
                detail: '${row['type']} · page ${row['page'] ?? '—'}',
              ),
            );
          }
        case 'objects':
          if (row['kind'] == null || row['index'] == null) continue;
          choices.add(
            _Choice('${row['kind']} ${row['index']}', {
              'kind': row['kind'],
              'index': row['index'],
            }, detail: row['text']?.toString()),
          );
        case 'styles':
          choices.add(
            _Choice('${row['font']} · ${row['size']} pt', {
              for (final k in ['font', 'size', 'bold', 'italic'])
                if (row[k] != null) k: row[k],
            }, detail: row['sample']?.toString()),
          );
        case 'bookmarks':
          if (row['path'] is List) {
            choices.add(
              _Choice(
                row['title']?.toString() ?? 'Untitled',
                row['path'],
                detail: 'Page ${row['page'] ?? '—'}',
              ),
            );
          }
          if (row['children'] is List) {
            choices.addAll(_choices(source, row['children']));
          }
        case 'layers':
          if (row['name'] is String) {
            choices.add(
              _Choice(
                row['name'],
                index + 1,
                detail: row['visible'] == true ? 'Visible' : 'Hidden',
              ),
            );
          }
        case 'attachments':
          if (row[source.field] is String) {
            choices.add(
              _Choice(
                row['name'] ?? row[source.field],
                row[source.field],
                detail: row['description']?.toString(),
              ),
            );
          }
        case 'fields':
          if (row['name'] is String) {
            choices.add(
              _Choice(
                row['name'],
                row['name'],
                detail:
                    '${row['type'] ?? 'Field'} · page ${row['page'] ?? '—'}',
              ),
            );
          }
        case 'paragraphs':
          if (row['paragraph'] is int) {
            choices.add(
              _Choice(
                'Paragraph ${row['paragraph']}',
                row['paragraph'],
                detail: row['text']?.toString(),
              ),
            );
          }
        case 'images':
          final id = row['image'] ?? row['index'];
          if (id is int) {
            choices.add(
              _Choice('Image $id', id, detail: row['kind']?.toString()),
            );
          }
      }
    }
    return choices;
  }

  Future<void> _choose(_ReferenceSource source, {bool anchor = false}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      Future<Map?> load(int offset) async {
        final result = await widget.engine.executeTool(
          handle: widget.handle,
          tool: source.tool,
          argumentsJson: jsonEncode({
            if (source.onPage) 'page': widget.page,
            if (source.list == 'bookmarks' || source.list == 'tags') ...{
              'limit': 1000,
              'offset': offset,
            },
          }),
        );
        return result.contents
            .where((c) => c.json.isNotEmpty)
            .map((c) => jsonDecode(c.json))
            .whereType<Map>()
            .where((data) => data[source.list] is List)
            .firstOrNull;
      }

      final payload = await load(0);
      final choices = payload == null
          ? <_Choice>[]
          : _choices(source, payload[source.list]);
      if (!mounted) return;
      if (choices.isEmpty) {
        setState(() => error = 'No matching entries in this document.');
        return;
      }
      final chosen = await showModalBottomSheet<List<_Choice>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => _PickerSheet(
          source: source,
          choices: choices,
          nextOffset: payload?['next'] as int?,
          loadMore: (offset) async {
            final next = await load(offset);
            return (
              _choices(source, next?[source.list] as List? ?? []),
              next?['next'] as int?,
            );
          },
        ),
      );
      if (chosen == null || chosen.isEmpty || !mounted) return;
      if (!source.multi &&
          (source.list == 'tags' ||
              source.list == 'links' ||
              source.list == 'items' ||
              source.list == 'comments')) {
        final v = chosen.single.value as Map<String, dynamic>;
        widget.onSelected(
          anchor
              ? {'anchor': v['object'], 'anchor_generation': v['generation']}
              : v,
        );
        return;
      }
      widget.onSelected({
        source.field: source.multi
            ? chosen.map((c) => c.value).toList()
            : chosen.single.value,
        if (source.list == 'objects' && payload?['generation'] is int)
          'generation': payload!['generation'],
      });
    } catch (e) {
      if (mounted) {
        setState(() => error = 'Could not read the document choices. $e');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = source;
    if (spec == null || widget.handle <= 0) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: busy ? null : () => _choose(spec),
          icon: const Icon(Icons.checklist),
          label: Text(busy ? 'Reading document…' : 'Choose ${spec.label}'),
        ),
        if (widget.tool == 'accessibility_move_tag')
          OutlinedButton.icon(
            onPressed: busy ? null : () => _choose(spec, anchor: true),
            icon: const Icon(Icons.low_priority),
            label: const Text('Choose position relative to another tag'),
          ),
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

class _PickerSheet extends StatefulWidget {
  const _PickerSheet({
    required this.source,
    required this.choices,
    required this.nextOffset,
    required this.loadMore,
  });
  final _ReferenceSource source;
  final List<_Choice> choices;
  final int? nextOffset;
  final Future<(List<_Choice>, int?)> Function(int) loadMore;
  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  final chosen = <_Choice>[];
  late final choices = [...widget.choices];
  late int? next = widget.nextOffset;
  bool loading = false;
  String? error;
  Future<void> _more() async {
    if (loading || next == null) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final (batch, offset) = await widget.loadMore(next!);
      if (mounted) {
        setState(() {
          choices.addAll(batch);
          next = offset;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = 'Could not read more entries. $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String query = '';
  @override
  Widget build(BuildContext context) {
    final rows = choices
        .where(
          (c) => '${c.label} ${c.detail ?? ''}'.toLowerCase().contains(query),
        )
        .toList();
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: .8,
        child: Column(
          children: [
            ListTile(
              title: Text('Choose ${widget.source.label}'),
              trailing: const CloseButton(),
            ),
            if (choices.length > 6)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'Search entries',
                  ),
                  onChanged: (s) =>
                      setState(() => query = s.trim().toLowerCase()),
                ),
              ),
            if (next != null)
              TextButton(
                onPressed: loading ? null : _more,
                child: Text(loading ? 'Loading…' : 'Load more entries'),
              ),
            if (error != null) Text(error!),
            Expanded(
              child: ListView.builder(
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final row = rows[i];
                  final detail = row.detail;
                  final description = detail == null || detail.isEmpty
                      ? null
                      : Text(
                          detail,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        );
                  if (!widget.source.multi) {
                    return ListTile(
                      title: Text(row.label),
                      subtitle: description,
                      onTap: () => Navigator.pop(context, [row]),
                    );
                  }
                  final selected = chosen.indexOf(row);
                  return CheckboxListTile(
                    value: selected >= 0,
                    title: Text(
                      selected >= 0
                          ? '${selected + 1}. ${row.label}'
                          : row.label,
                    ),
                    subtitle: description,
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        chosen.add(row);
                      } else {
                        chosen.remove(row);
                      }
                    }),
                  );
                },
              ),
            ),
            if (widget.source.multi)
              Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: chosen.isEmpty
                      ? null
                      : () => Navigator.pop(context, chosen),
                  child: Text('Use selection (${chosen.length})'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
