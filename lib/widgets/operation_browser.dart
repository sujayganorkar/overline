import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';

import '../bridge/api.dart' as bridge;
import '../services/pdf_engine.dart';
import 'delivery_hub_sheet.dart';
import 'engine_task_labels.dart';
import 'operation_arguments.dart';
import 'operation_reference_picker.dart';
import 'operation_page_picker.dart';
import 'output_saver.dart';

class OperationBrowser extends StatefulWidget {
  const OperationBrowser({
    super.key,
    required this.engine,
    required this.handle,
    required this.onStatusChanged,
    this.initialQuery = '',
    this.initialToolId,
    this.currentPage = 1,
    this.onOpenDocument,
    this.onRename,
    this.onOpenDocumentAtPage,
  });

  final PdfEngineApi engine;
  final int handle, currentPage;
  final ValueChanged<bridge.DocumentStatus> onStatusChanged;
  final String initialQuery;
  final String? initialToolId;
  final void Function(Uint8List, String)? onOpenDocument;
  final ValueChanged<String>? onRename;
  final void Function(Uint8List, String, int)? onOpenDocumentAtPage;

  @override
  State<OperationBrowser> createState() => _OperationBrowserState();
}

class _OperationBrowserState extends State<OperationBrowser> {
  late final _query = TextEditingController(text: widget.initialQuery);
  late final _catalog = widget.engine.operationCatalog();
  bool _opened = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _open(bridge.OperationInfo operation) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => OperationScreen(
            engine: widget.engine,
            handle: widget.handle,
            currentPage: widget.currentPage,
            operation: operation,
            onStatusChanged: widget.onStatusChanged,
            onOpenDocument: widget.onOpenDocument,
            onRename: widget.onRename,
            onOpenDocumentAtPage: widget.onOpenDocumentAtPage,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => SafeArea(
    child: FractionallySizedBox(
      heightFactor: .88,
      child: Column(
        children: [
          ListTile(
            title: Text(
              'PDF editing tools',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            trailing: const CloseButton(),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _query,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Find an operation',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<bridge.OperationInfo>>(
              future: _catalog,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Could not load tools. ${snapshot.error}'),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final query = _query.text.trim().toLowerCase();
                final available = snapshot.requireData.where(
                  (op) => widget.handle > 0 || !op.requiresDocument,
                );
                if (!_opened && widget.initialToolId != null) {
                  _opened = true;
                  final target = available
                      .where((o) => o.id == widget.initialToolId)
                      .firstOrNull;
                  if (target != null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _open(target);
                    });
                  }
                }
                final operations = available
                    .where(
                      (o) => '${o.title} ${o.id} ${o.description}'
                          .toLowerCase()
                          .contains(query),
                    )
                    .toList();
                if (operations.isEmpty) {
                  return const Center(child: Text('No matching tools'));
                }
                return ListView.builder(
                  itemCount: operations.length,
                  itemBuilder: (context, i) {
                    final op = operations[i];
                    return ListTile(
                      leading: Icon(
                        op.readOnly ? Icons.search : Icons.edit_outlined,
                      ),
                      title: Text(op.title),
                      subtitle: Text(
                        op.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(op),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

/// Full-screen route for a tool selected in the mobile task catalog.
class OperationScreen extends StatefulWidget {
  const OperationScreen({
    super.key,
    required this.engine,
    required this.handle,
    required this.operation,
    required this.onStatusChanged,
    this.currentPage = 1,
    this.onOpenDocument,
    this.onRename,
    this.onOpenDocumentAtPage,
  });
  final PdfEngineApi engine;
  final int handle, currentPage;
  final bridge.OperationInfo operation;
  final ValueChanged<bridge.DocumentStatus> onStatusChanged;
  final void Function(Uint8List, String)? onOpenDocument;
  final ValueChanged<String>? onRename;
  final void Function(Uint8List, String, int)? onOpenDocumentAtPage;

  @override
  State<OperationScreen> createState() => _OperationScreenState();
}

final _copiedComments = Expando<String>('copied PDF comments');

String _actionLabel(bridge.OperationInfo operation) {
  final title = operation.title.toLowerCase();
  if (title.startsWith('export')) return 'Export';
  if (title.startsWith('copy')) return 'Copy';
  if (title.startsWith('paste')) return 'Paste';
  if (title.startsWith('find')) return 'Find';
  if (title.startsWith('save')) return 'Save';
  if (title.startsWith('create')) return 'Create';
  if (title.startsWith('render')) return 'Render preview';
  if (title.startsWith('delete')) return 'Delete';
  return operation.readOnly ? 'Show results' : 'Apply';
}

class _OperationScreenState extends State<OperationScreen> {
  late final _draft = ArgumentDraft(widget.operation.id, widget.currentPage);
  late final ToolSchema _schema;
  Map<String, dynamic> _values = {};
  bridge.OperationResponse? _result;
  bool _busy = false;
  bool _importing = false;
  bool _undoAvailable = false;
  String? _error;
  String? _schemaError;
  final _scroll = ScrollController();
  Map<String, dynamic> _payload = {};
  String? _commentsSource;
  String? _importedProfile;
  Future<void> _importProfile() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await FilePickerPlatform.instance.pickFile(
        dialogTitle: 'Choose a printer profile',
        type: FileType.custom,
        allowedExtensions: ['icc', 'icm'],
      );
      if (file == null || !mounted) return;
      final data = BytesBuilder(copy: false);
      await for (final block in file.readAsByteStream()) {
        if (data.length + block.length > 32 * 1024 * 1024) {
          throw const FormatException(
            'Choose a printer profile of 32 MiB or less.',
          );
        }
        data.add(block);
      }
      if (!mounted) return;
      await widget.engine.stageFile(name: file.name, bytes: data.takeBytes());
      if (mounted) setState(() => _importedProfile = file.name);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not import the profile. $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importComments({bool fromClipboard = false}) async {
    try {
      final String? data;
      String label;
      if (fromClipboard) {
        data = (await Clipboard.getData('text/plain'))?.text;
        label = 'Android clipboard';
      } else {
        final file = await FilePickerPlatform.instance.pickFile(
          type: FileType.custom,
          allowedExtensions: ['xfdf'],
          dialogTitle: 'Choose XFDF comments',
        );
        if (file == null) return;
        data = utf8.decode(await file.readAsBytes());
        label = file.name;
      }
      if (!mounted) return;
      if (data == null ||
          !RegExp(
            r'<(?:[\w-]+:)?xfdf(?:\s|>)',
            caseSensitive: false,
          ).hasMatch(data)) {
        setState(
          () => _error = 'Choose an XFDF comment file or copy comments first.',
        );
        return;
      }
      setState(() {
        _values['xfdf'] = data;
        _commentsSource = label;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not read comments. $e');
    }
  }

  @override
  void initState() {
    super.initState();
    try {
      _schema = jsonDecode(widget.operation.inputSchemaJson) as ToolSchema;
      _values = _draft.initial('', _schema) as Map<String, dynamic>;
      if ((widget.operation.id == 'comments_paste'
              ? _copiedComments[widget.engine]
              : null)
          case final String comments) {
        _values['xfdf'] = comments;
        _commentsSource = 'Copied comments';
      }
    } catch (e) {
      _schemaError = 'Could not load the input fields. $e';
    }
  }

  @override
  void dispose() {
    _draft.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    Map<String, dynamic> arguments;
    try {
      arguments = _draft.encode('', _schema, _values) as Map<String, dynamic>;
    } on FormatException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    final op = widget.operation;
    if (op.id == 'comments_paste' && _commentsSource == null) {
      setState(() => _error = 'Choose or copy comments to paste.');
      return;
    }
    if (op.destructive ||
        arguments['cut'] == true ||
        arguments['delete'] == true) {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(op.title),
          content: Text(
            op.readOnly
                ? 'This tool can write or replace an output file. Continue?'
                : 'This tool can remove or replace content or write files. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (approved != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _importing = op.id == 'doc_batch';
      _error = null;
    });
    String? stageToken;
    try {
      if (_importing) {
        stageToken = await _draft.stageBatch(arguments);
        if (!mounted) return;
        setState(() => _importing = false);
      }
      final tracksUndo = op.requiresDocument && !op.readOnly;
      final before = tracksUndo
          ? await widget.engine.status(handle: widget.handle)
          : null;
      final result = await widget.engine.executeTool(
        handle: widget.handle,
        tool: op.id,
        argumentsJson: jsonEncode(arguments),
      );
      if (!mounted) return;
      if (op.requiresDocument &&
          (!op.readOnly || op.id == 'view_reading_colors') &&
          result.status.pageCount > 0) {
        widget.onStatusChanged(result.status);
      }
      if (!mounted) return;
      setState(() {
        _result = result;
        _payload = {};
        for (final content in result.contents) {
          if (content.json.isEmpty) continue;
          try {
            final json = jsonDecode(content.json);
            if (json is Map<String, dynamic>) {
              _payload = json;
              break;
            }
          } on FormatException {
            continue;
          }
        }
        if (op.id == 'comments_copy' && _payload['xfdf'] is String) {
          _copiedComments[widget.engine] = _payload['xfdf'];
        }
        _undoAvailable =
            before != null &&
            result.status.dirty &&
            result.status.canUndo.isNotEmpty &&
            (result.status.canUndo != before.canUndo || !before.dirty);
      });
      if (op.id == 'doc_rename' && _payload['path'] is String) {
        final name = (_payload['path'] as String).split(RegExp(r'[/\\]')).last;
        if (name.isNotEmpty) widget.onRename?.call(name);
      }
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      try {
        if (stageToken != null) await _draft.releaseBatch(stageToken);
      } finally {
        if (mounted) {
          setState(() {
            _busy = false;
            _importing = false;
          });
        }
      }
    }
  }

  Future<void> _undo() async {
    if (_busy || !_undoAvailable) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.engine.executeTool(
        handle: widget.handle,
        tool: 'edit_undo',
        argumentsJson: '{}',
      );
      if (!mounted) return;
      widget.onStatusChanged(r.status);
      if (!mounted) return;
      setState(() {
        _result = null;
        _undoAvailable = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Edit undone.')));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final op = widget.operation;
    final result = _result;
    final mobileLabel = engineTaskLabels[op.id];
    final paste = op.id == 'comments_paste';
    final issues =
        _payload['error'] is String ||
        (_payload['failed'] is num && _payload['failed'] > 0);
    final next = _payload['next'];
    final destination = _payload['destination'];
    final destPage =
        op.id == 'link_open' &&
            _payload['destination_applied'] == true &&
            destination is Map &&
            destination['page'] is int
        ? destination['page'] as int
        : null;
    final String resultTitle = issues
        ? 'Completed with errors'
        : _payload['dry_run'] == true
        ? 'Preview complete'
        : _payload['written'] == false
        ? 'No output written'
        : op.id == 'comments_copy'
        ? 'Comments copied'
        : 'Operation complete';
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(mobileLabel?.title ?? op.title, maxLines: 2),
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_busy)
                const LinearProgressIndicator(
                  semanticsLabel: 'Running operation',
                ),
              if (_importing)
                TextButton.icon(
                  onPressed: _draft.cancelBatch,
                  icon: const Icon(Icons.close),
                  label: const Text('Cancel import'),
                ),
              Expanded(
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_schemaError != null)
                      Text(_schemaError!)
                    else if (result == null) ...[
                      if (op.description.isNotEmpty) ...[
                        _Description(
                          text: op.description,
                          summary: mobileLabel?.detail,
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (!_busy)
                        OperationReferencePicker(
                          engine: widget.engine,
                          handle: widget.handle,
                          tool: op.id,
                          properties:
                              (_schema['properties'] as ToolSchema?) ?? {},
                          page:
                              int.tryParse('${_values['page']}') ??
                              widget.currentPage,
                          onSelected: (v) => setState(() {
                            _values = {..._values, ...v};
                            _error = null;
                          }),
                        ),
                      if (op.id == 'print_color_profiles') ...[
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _importProfile,
                          icon: const Icon(Icons.file_open_outlined),
                          label: const Text('Import an ICC profile'),
                        ),
                        if (_importedProfile != null)
                          Text('Imported $_importedProfile'),
                      ],
                      if (!_busy &&
                          {
                            'page_enhance_camera',
                            'image_hit',
                            'content_copy',
                            'comment_popup',
                            'ocr_words',
                            'ocr_recognize',
                            'model_add',
                            'comment_add',
                            'comment_edit',
                            'comments_paste',
                            'link_add',
                            'link_edit',
                            'page_add_image',
                            'page_add_text',
                            'content_update',
                            'image_edit',
                            'redact_mark',
                            'form_add_field',
                            'form_add_field_table',
                            'form_set_props',
                            'text_extract',
                            'measure_snap',
                            'fill_sign_add',
                          }.contains(op.id))
                        OperationPagePicker(
                          engine: widget.engine,
                          handle: widget.handle,
                          page:
                              int.tryParse('${_values['page']}') ??
                              widget.currentPage,
                          properties:
                              (_schema['properties'] as ToolSchema?) ?? {},
                          onSelected: (v) => setState(() {
                            _values = {..._values, ...v};
                            _error = null;
                          }),
                        ),
                      if (paste)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _commentsSource ?? 'Choose comments to paste',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Wrap(
                              spacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => _importComments(),
                                  icon: const Icon(Icons.folder_open),
                                  label: const Text('Open XFDF'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => _importComments(
                                          fromClipboard: true,
                                        ),
                                  icon: const Icon(Icons.content_paste),
                                  label: const Text('Use clipboard'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      AbsorbPointer(
                        absorbing: _busy,
                        child: ArgumentFields(
                          engine: widget.engine,
                          draft: _draft,
                          schema: _schema,
                          values: paste
                              ? ({..._values}..remove('xfdf'))
                              : _values,
                          onChanged: (v) => setState(() {
                            _values = {
                              ...v,
                              if (paste) 'xfdf': _values['xfdf'],
                            };
                            _error = null;
                          }),
                        ),
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Icon(
                            issues
                                ? Icons.warning_amber
                                : Icons.check_circle_outline,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              resultTitle,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      for (final path in {
                        for (final c in result.contents)
                          if (c.json.isNotEmpty) ...outputPathsIn(c.json),
                      })
                        ListTile(
                          leading: const Icon(Icons.file_download_outlined),
                          title: Text(path.split('/').last),
                          subtitle: Text(
                            destPage == null
                                ? 'Save or share'
                                : 'Destination · page $destPage',
                          ),
                          onTap: () => saveOutputPaths(
                            context,
                            widget.engine,
                            [path],
                            onOpenDocument:
                                destPage != null &&
                                    widget.onOpenDocumentAtPage != null
                                ? (bytes, name) => widget.onOpenDocumentAtPage!(
                                    bytes,
                                    name,
                                    destPage,
                                  )
                                : widget.onOpenDocument,
                          ),
                        ),
                      if (op.id == 'comments_copy' &&
                          _payload['xfdf'] is String)
                        OutlinedButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: _payload['xfdf']),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'XFDF copied to the Android clipboard.',
                                  ),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.copy),
                          label: const Text('Copy XFDF to clipboard'),
                        ),
                      if (op.readOnly &&
                          next is int &&
                          _schema['properties']?['offset']?['type'] ==
                              'integer')
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  setState(() => _values['offset'] = next);
                                  _run();
                                },
                          child: const Text('Next results'),
                        ),
                      for (final c in result.contents) ...[
                        if (c.png.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Image.memory(
                              c.png,
                              semanticLabel: 'Rendered preview',
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) =>
                                  const Text('Preview could not be displayed.'),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => DeliveryHubSheet.show(
                              context,
                              title: 'Rendered image',
                              subtitle: 'PNG',
                              bytes: c.png,
                              suggestedFileName: 'preview.png',
                            ),
                            icon: const Icon(Icons.file_download_outlined),
                            label: const Text('Save or share image'),
                          ),
                        ],
                        if (c.json.isNotEmpty)
                          _ResultData(
                            source: op.id == 'comments_copy'
                                ? jsonEncode({..._payload}..remove('xfdf'))
                                : c.json,
                          ),
                      ],
                    ],
                  ],
                ),
              ),
              if (_error != null)
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Semantics(
                    liveRegion: true,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 90),
                      child: SingleChildScrollView(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (_schemaError == null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: result == null
                      ? FilledButton.icon(
                          key: const ValueKey('execute-operation'),
                          onPressed: _busy ? null : _run,
                          icon: Icon(
                            op.readOnly ? Icons.search : Icons.play_arrow,
                          ),
                          label: Text(_busy ? 'Working…' : _actionLabel(op)),
                        )
                      : Wrap(
                          spacing: 8,
                          children: [
                            if (_undoAvailable)
                              OutlinedButton.icon(
                                onPressed: _busy ? null : _undo,
                                icon: const Icon(Icons.undo),
                                label: Text('Undo ${result.status.canUndo}'),
                              ),
                            OutlinedButton(
                              onPressed: _busy
                                  ? null
                                  : () => setState(() {
                                      _result = null;
                                      _error = null;
                                    }),
                              child: const Text('Edit settings'),
                            ),
                            FilledButton(
                              onPressed: _busy
                                  ? null
                                  : () => Navigator.maybePop(context),
                              child: const Text('Done'),
                            ),
                          ],
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Description extends StatefulWidget {
  const _Description({required this.text, this.summary});
  final String text;
  final String? summary;
  @override
  State<_Description> createState() => _DescriptionState();
}

class _DescriptionState extends State<_Description> {
  bool expanded = false;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        expanded ? widget.text : widget.summary ?? widget.text,
        maxLines: expanded ? null : 4,
        overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
      ),
      if (widget.summary != null || widget.text.length > 190)
        TextButton(
          onPressed: () => setState(() => expanded = !expanded),
          child: Text(expanded ? 'Show less' : 'Show full instructions'),
        ),
    ],
  );
}

class _ResultData extends StatelessWidget {
  const _ResultData({required this.source});
  final String source;
  @override
  Widget build(BuildContext context) {
    Object? value;
    try {
      value = jsonDecode(source);
    } on FormatException {
      return SelectableText(source);
    }
    return _ResultNode(label: 'Details', value: value, root: true);
  }
}

/// Keep the original hierarchy and expose long result sets incrementally so
/// individual findings and nested warnings stay available on a phone.
class _ResultNode extends StatefulWidget {
  const _ResultNode({
    super.key,
    required this.label,
    required this.value,
    this.root = false,
  });
  final String label;
  final Object? value;
  final bool root;
  @override
  State<_ResultNode> createState() => _ResultNodeState();
}

class _ResultNodeState extends State<_ResultNode> {
  int shown = 20;
  @override
  Widget build(BuildContext context) {
    final v = widget.value;
    if (v is! Map && v is! List) {
      final text = switch (v) {
        true => 'Yes',
        false => 'No',
        null => 'None',
        _ => '$v',
      };
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: SelectableText.rich(
          TextSpan(
            style: Theme.of(context).textTheme.bodyMedium,
            children: [
              TextSpan(
                text: '${widget.label}  ',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              TextSpan(text: text),
            ],
          ),
        ),
      );
    }
    final entries = v is List ? v.asMap().entries : (v as Map).entries;
    final rows = <Widget>[];
    for (final e in entries.take(shown)) {
      final item = e.value;
      String label;
      if (e.key is int) {
        label = 'Item ${(e.key as int) + 1}';
        if (item is Map) {
          final name =
              item['title'] ??
              item['name'] ??
              item['message'] ??
              item['rule'] ??
              item['text'];
          if (name is String && name.isNotEmpty) label = name;
        }
      } else {
        label = argumentLabel(e.key.toString());
      }
      rows.add(_ResultNode(key: ValueKey(e.key), label: label, value: item));
    }
    if (entries.length > shown) {
      rows.add(
        TextButton(
          onPressed: () => setState(() => shown += 20),
          child: Text('Show more (${entries.length - shown})'),
        ),
      );
    }
    if (widget.root) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      );
    }
    return ExpansionTile(
      title: Text(
        '${widget.label} (${entries.length})',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      childrenPadding: const EdgeInsets.only(left: 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}
