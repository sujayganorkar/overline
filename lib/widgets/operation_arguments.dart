import 'dart:async';
import 'dart:convert';

import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/pdf_engine.dart';

typedef ToolSchema = Map<String, dynamic>;

String argumentLabel(String name) {
  final words = name.replaceAll('_', ' ');
  return words.isEmpty
      ? 'Value'
      : '${words[0].toUpperCase()}${words.substring(1)}';
}

List<String> _types(ToolSchema schema) {
  final type = schema['type'];
  if (type is List) return type.whereType<String>().toList();
  return [if (type is String) type else 'string'];
}

String _valueType(ToolSchema schema, Object? value) {
  final types = _types(schema);
  if (value is _TypedValue) return value.type;
  if (value == null && types.contains('null')) return 'null';
  if (value is int && types.contains('integer')) return 'integer';
  if (value is num && types.contains('number')) return 'number';
  return types.first;
}

enum _FileRole { input, inputs, output, folder, fontFolders }

const _pathOutputs = {
  'doc_export_data',
  'doc_print',
  'sign_id_create',
  'doc_export_office',
  'accessibility_report',
  'accessibility_review_record',
  'accessibility_review_save',
  'accessibility_review_html',
  'form_merge_data',
  'doc_compare_report',
  'doc_export_text',
  'doc_reduce',
  'image_save',
  'doc_optimize',
  'ocr_dictionary',
};

_FileRole? _fileRole(String tool, String key, ToolSchema schema) {
  if (schema['format'] == 'pdf-file' ||
      key == 'linked_file' && tool == 'link_open') {
    return _FileRole.input;
  }
  if (tool == 'text_font_files' && key == 'directories') {
    return _FileRole.fontFolders;
  }
  if (key == 'paths' && _types(schema).contains('array')) {
    return _FileRole.inputs;
  }
  if (tool.startsWith('doc_compare') && key == 'other' ||
      tool == 'bookmark_copy' && key == 'from' ||
      tool.startsWith('accessibility_review_') && key == 'before') {
    return _FileRole.input;
  }
  if (!_types(schema).contains('string')) return null;
  if (key == 'out_dir' || key == 'folder') return _FileRole.folder;
  if (key == 'out' || key == 'output') return _FileRole.output;
  if (key == 'path') {
    return _pathOutputs.contains(tool) ? _FileRole.output : _FileRole.input;
  }
  if ({
        'input',
        'file',
        'input_file',
        'other_file',
        'image',
        'color_profile',
        'poster',
      }.contains(key) ||
      tool == 'sign_document' && key == 'id') {
    return _FileRole.input;
  }
  return null;
}

List<String> _extensions(String tool) => switch (tool) {
  'doc_export_office' => ['docx', 'pptx', 'md', 'html', 'rtf'],
  'doc_export_data' => ['xfdf', 'fdf', 'xml', 'csv', 'txt', 'xdp'],
  'doc_export_text' || 'ocr_dictionary' => ['txt'],
  'bookmark_export' ||
  'accessibility_review_record' ||
  'accessibility_review_save' => ['json'],
  'accessibility_report' || 'accessibility_review_html' => ['html'],
  'measure_export' || 'form_merge_data' => ['csv'],
  'sign_id_create' => ['p12'],
  'image_save' => [], // The engine appends the image's native extension.
  _ => ['pdf'],
};

List<int> _pageRanges(String text) {
  final selected = <int>{};
  for (final item in text.split(',')) {
    final match = RegExp(r'^\s*(\d+)\s*(?:-\s*(\d+))?\s*$').firstMatch(item);
    if (match == null) {
      throw const FormatException(
        'Use page numbers or ranges such as 1, 3–5 (1, 3-5).',
      );
    }
    final first = int.tryParse(match[1]!);
    final last = int.tryParse(match[2] ?? match[1]!);
    if (first == null || last == null || first < 1 || last < first) {
      throw const FormatException('Enter positive, increasing page ranges.');
    }
    if (last - first >= 10000 || selected.length + last - first + 1 > 10000) {
      throw const FormatException('Choose up to 10,000 pages at once.');
    }
    for (var page = first; page <= last; page++) {
      selected.add(page);
    }
  }
  return selected.toList();
}

bool _isPages(String key, ToolSchema schema) =>
    (key == 'pages' || key == 'from_pages') &&
    schema['type'] == 'array' &&
    schema['items']?['type'] == 'integer';

/// Draft values retain partially typed numbers, unchecked optional fields and
/// user-selected file handles until the form is submitted.
class ArgumentDraft {
  ArgumentDraft(this.tool, this.currentPage);

  final String tool;
  final int currentPage;
  final _stamp = DateTime.now().millisecondsSinceEpoch;
  int _fileNumber = 0;
  static const _paths = MethodChannel('app.overline.pdf/paths');
  final _grants = <String>{};
  bool _disposed = false;

  Future<List<_PickedFile>> _pickBatch(bool folder) async {
    final records =
        await _paths.invokeListMethod<Object?>('pickBatchSources', {
          'folder': folder,
        }) ??
        [];
    final selected = [
      for (final row in records.whereType<Map>())
        if (row['name'] is String && row['token'] is String)
          _PickedFile(
            row['name'] as String,
            row['token'] as String,
            folder: row['folder'] == true,
          ),
    ];
    if (_disposed) {
      await _forget(selected.map((f) => f.path));
      return [];
    }
    _grants.addAll(selected.map((f) => f.path));
    return selected;
  }

  Future<String> stageBatch(Map<String, dynamic> arguments) async {
    final staged = await _paths.invokeMapMethod<String, dynamic>(
      'stageBatchSources',
      {
        'tokens': arguments['paths'],
        'recursive': arguments['recursive'] == true,
      },
    );
    final token = staged?['token'];
    final paths = staged?['paths'];
    if (token is! String ||
        paths is! List ||
        paths.isEmpty ||
        !paths.every(
          (p) =>
              p is String &&
              p.startsWith('imports/batch-$token/') &&
              !p.split('/').contains('..'),
        )) {
      if (token is String) await releaseBatch(token);
      throw const FormatException(
        'Could not import the selected files or folders.',
      );
    }
    arguments['paths'] = paths.cast<String>();
    return token;
  }

  Future<void> cancelBatch() => _paths.invokeMethod<void>('cancelBatchImport');
  Future<void> releaseBatch(String token) =>
      _paths.invokeMethod<void>('releaseBatchStage', {'token': token});
  Future<void> _forget(Iterable<String> tokens) => _paths.invokeMethod<void>(
    'forgetBatchSources',
    {'tokens': tokens.toList()},
  );

  void dispose() {
    _disposed = true;
    if (_grants.isNotEmpty) unawaited(_forget(_grants));
  }

  Object? initial(String key, ToolSchema schema) {
    final role = _fileRole(tool, key, schema);
    if (role == _FileRole.output || role == _FileRole.folder) {
      if (tool == 'ocr_dictionary') return 'ocr-dictionary-en.txt';
      final stem =
          '${tool.replaceFirst(RegExp(r"^doc_"), "").replaceAll("_", "-")}-$_stamp-${++_fileNumber}';
      final extensions = _extensions(tool);
      return role == _FileRole.folder || extensions.isEmpty
          ? stem
          : '$stem.${extensions.first}';
    }
    if (role == _FileRole.input) return null;
    if (role == _FileRole.inputs || role == _FileRole.fontFolders) {
      return <Object?>[];
    }
    if (schema.containsKey('default')) return schema['default'];
    if (_isPages(key, schema)) return currentPage.toString();
    final type = _types(schema).first;
    if (type == 'object') {
      final props = schema['properties'] as ToolSchema? ?? {};
      return <String, dynamic>{
        for (final name
            in (schema['required'] as List? ?? []).whereType<String>())
          if (props[name] is ToolSchema) name: initial(name, props[name]),
      };
    }
    if (type == 'array') {
      final items = schema['items'] as ToolSchema? ?? {};
      final count = (schema['minItems'] as int? ?? 0).clamp(0, 8);
      return List<Object?>.generate(
        count,
        (_) => initial('', items),
        growable: true,
      );
    }
    if (schema['enum'] case final List options when options.isNotEmpty) {
      return options.first;
    }
    if (type == 'boolean') return true;
    if (key == 'page' && type == 'integer') return currentPage;
    return '';
  }

  Object? encode(String key, ToolSchema schema, Object? value) {
    final role = _fileRole(tool, key, schema);
    if (role == _FileRole.output || role == _FileRole.folder) {
      final name = (value as String? ?? '').trim();
      if (name.isEmpty ||
          name == '.' ||
          name == '..' ||
          RegExp(r'[\\/:\x00-\x1F]').hasMatch(name)) {
        throw const FormatException(
          'Use a file or folder name without a path.',
        );
      }
      return 'outputs/$name';
    }
    if (role == _FileRole.input) {
      if (value is! _PickedFile) throw const FormatException('Choose a file.');
      return value.path;
    }
    if (role == _FileRole.inputs || role == _FileRole.fontFolders) {
      final paths = (value as List)
          .cast<_PickedFile>()
          .map((item) => item.path)
          .toList();
      _checkCount(paths.length, schema, 'files');
      if (paths.isEmpty) {
        throw const FormatException('Choose at least one file.');
      }
      return role == _FileRole.inputs
          ? paths
          : paths
                .map((p) => p.substring(0, p.lastIndexOf('/')))
                .toSet()
                .toList();
    }
    if (value == null && _types(schema).contains('null')) return null;
    if (value is _TypedValue) {
      return encode(key, {...schema, 'type': value.type}, value.value);
    }
    if (_isPages(key, schema)) {
      final pages = _pageRanges(value.toString().replaceAll('–', '-'));
      _checkCount(pages.length, schema, 'pages');
      return pages;
    }
    final type = _valueType(schema, value);
    if (type == 'object') {
      final values = value as Map;
      final properties = schema['properties'] as ToolSchema? ?? {};
      final extra = schema['additionalProperties'];
      final result = <String, dynamic>{};
      for (final entry in values.entries) {
        final name = entry.key as String;
        final childSchema =
            properties[name] as ToolSchema? ??
            (extra is ToolSchema ? extra : <String, dynamic>{});
        try {
          result[name] = encode(
            properties.containsKey(name) ? name : '',
            childSchema,
            entry.value,
          );
        } on FormatException catch (e) {
          throw FormatException('${argumentLabel(name)} · ${e.message}');
        }
      }
      for (final name in schema['required'] as List? ?? []) {
        if (!result.containsKey(name)) {
          throw FormatException('Add ${argumentLabel(name)}.');
        }
      }
      if (schema['maxProperties'] case final int limit
          when result.length > limit) {
        throw FormatException('Choose at most $limit settings.');
      }
      if (schema['minProperties'] case final int minimum
          when result.length < minimum) {
        throw FormatException('Choose at least $minimum settings.');
      }
      return result;
    }
    if (type == 'array') {
      final items = schema['items'] as ToolSchema? ?? {};
      final list = value as List;
      _checkCount(list.length, schema, 'entries');
      final result = <Object?>[];
      for (var i = 0; i < list.length; i++) {
        try {
          result.add(encode('', items, list[i]));
        } on FormatException catch (e) {
          throw FormatException('Item ${i + 1} · ${e.message}');
        }
      }
      if (schema['uniqueItems'] == true &&
          result.map(jsonEncode).toSet().length != result.length) {
        throw const FormatException('Remove duplicate selections.');
      }
      return result;
    }
    if (type == 'boolean') return value == true;
    if (type == 'null') return null;
    if (type == 'number' || type == 'integer') {
      final number = type == 'integer'
          ? int.tryParse('$value')
          : num.tryParse('$value');
      if (number == null || !number.isFinite) {
        throw FormatException(
          type == 'integer' ? 'Enter a whole number.' : 'Enter a number.',
        );
      }
      for (final (bound, relation) in [
        ('minimum', '>='),
        ('maximum', '<='),
        ('exclusiveMinimum', '>'),
        ('exclusiveMaximum', '<'),
      ]) {
        final limit = schema[bound];
        if (limit is num &&
            (switch (relation) {
              '>=' => number < limit,
              '<=' => number > limit,
              '>' => number <= limit,
              _ => number >= limit,
            })) {
          throw FormatException('The value must be $relation $limit.');
        }
      }
      return number;
    }
    final string = value?.toString() ?? '';
    if (schema['minLength'] case final int minimum
        when string.runes.length < minimum) {
      throw FormatException('Enter at least $minimum characters.');
    }
    if (schema['maxLength'] case final int limit
        when string.runes.length > limit) {
      throw FormatException('Enter at most $limit characters.');
    }
    return string;
  }

  void _checkCount(int length, ToolSchema schema, String unit) {
    if (schema['minItems'] case final int min when length < min) {
      throw FormatException('Choose at least $min $unit.');
    }
    if (schema['maxItems'] case final int max when length > max) {
      throw FormatException('Choose at most $max $unit.');
    }
  }
}

class _PickedFile {
  const _PickedFile(this.name, this.path, {this.folder = false});
  final String name;
  final String path;
  final bool folder;
}

class _TypedValue {
  const _TypedValue(this.type, this.value);
  final String type;
  final Object? value;
}

class ArgumentFields extends StatefulWidget {
  const ArgumentFields({
    super.key,
    required this.engine,
    required this.draft,
    required this.schema,
    required this.values,
    required this.onChanged,
  });
  final PdfEngineApi engine;
  final ArgumentDraft draft;
  final ToolSchema schema;
  final Map<String, dynamic> values;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  State<ArgumentFields> createState() => _ArgumentFieldsState();
}

class _ArgumentFieldsState extends State<ArgumentFields> {
  Future<void> _chooseSetting(List<String> options) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) =>
          _ChoiceSheet(title: 'Add a setting', options: options),
    );
    if (choice == null || !mounted) return;
    final property = widget.schema['properties'][choice] as ToolSchema;
    widget.onChanged({
      ...widget.values,
      choice: widget.draft.initial(choice, property),
    });
  }

  Future<void> _addKey() async {
    final field = await showDialog<String>(
      context: context,
      builder: (context) {
        var name = '';
        return AlertDialog(
          title: const Text('Add a field'),
          content: TextField(
            autofocus: true,
            onChanged: (s) => name = s.trim(),
            decoration: const InputDecoration(labelText: 'Field name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (name.isNotEmpty) Navigator.pop(context, name);
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
    if (!mounted || field == null || widget.values.containsKey(field)) return;
    final spec = widget.schema['additionalProperties'];
    final value = spec is ToolSchema
        ? widget.draft.initial('', spec)
        : const _TypedValue('string', '');
    widget.onChanged({...widget.values, field: value});
  }

  @override
  Widget build(BuildContext context) {
    final props = widget.schema['properties'] as ToolSchema? ?? {};
    final required = (widget.schema['required'] as List? ?? []).toSet();
    final absent = props.keys
        .where((k) => !widget.values.containsKey(k))
        .toList();
    final extra = widget.schema['additionalProperties'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in widget.values.entries)
          Padding(
            key: ValueKey(entry.key),
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!required.contains(entry.key))
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () {
                        final next = {...widget.values}..remove(entry.key);
                        widget.onChanged(next);
                      },
                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                      label: Text('Remove ${argumentLabel(entry.key)}'),
                    ),
                  ),
                _Field(
                  engine: widget.engine,
                  draft: widget.draft,
                  name: props.containsKey(entry.key) ? entry.key : '',
                  label: argumentLabel(entry.key),
                  schema:
                      props[entry.key] as ToolSchema? ??
                      (extra is ToolSchema
                          ? extra
                          : {
                              'type': [
                                'string',
                                'number',
                                'boolean',
                                'array',
                                'object',
                                'null',
                              ],
                            }),
                  value: entry.value,
                  onChanged: (v) =>
                      widget.onChanged({...widget.values, entry.key: v}),
                ),
              ],
            ),
          ),
        if (absent.isNotEmpty &&
            (widget.schema['maxProperties'] as int? ?? props.length) >
                widget.values.length)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _chooseSetting(absent),
              icon: const Icon(Icons.add),
              label: const Text('Add a setting'),
            ),
          ),
        if (extra is ToolSchema || props.isEmpty && extra != false)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _addKey,
              icon: const Icon(Icons.add),
              label: const Text('Add a field'),
            ),
          ),
      ],
    );
  }
}

class _ChoiceSheet extends StatefulWidget {
  const _ChoiceSheet({required this.title, required this.options});
  final String title;
  final List<String> options;
  @override
  State<_ChoiceSheet> createState() => _ChoiceSheetState();
}

class _ChoiceSheetState extends State<_ChoiceSheet> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final filtered = widget.options
        .where(
          (s) => argumentLabel(s).toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: .75,
        child: Column(
          children: [
            ListTile(
              title: Text(
                widget.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              trailing: CloseButton(onPressed: () => Navigator.pop(context)),
            ),
            if (widget.options.length > 7)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'Search settings',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (s) => setState(() => query = s),
                ),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, i) => ListTile(
                  title: Text(argumentLabel(filtered[i])),
                  onTap: () => Navigator.pop(context, filtered[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatefulWidget {
  const _Field({
    super.key,
    required this.engine,
    required this.draft,
    required this.name,
    required this.label,
    required this.schema,
    required this.value,
    required this.onChanged,
  });
  final PdfEngineApi engine;
  final ArgumentDraft draft;
  final String name, label;
  final ToolSchema schema;
  final Object? value;
  final ValueChanged<Object?> onChanged;
  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  bool _picking = false;
  String? _error;

  bool get _batch => widget.draft.tool == 'doc_batch' && widget.name == 'paths';

  Future<void> _files(_FileRole role, {bool folder = false}) async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      if (_batch) {
        final selection = await widget.draft._pickBatch(folder);
        if (mounted && selection.isNotEmpty) {
          final present = (widget.value as List).whereType<_PickedFile>();
          widget.onChanged(
            {
              for (final file in [...present, ...selection]) file.path: file,
            }.values.toList(),
          );
        }
        return;
      }
      final single = role == _FileRole.input;
      final picker = FilePickerPlatform.instance;
      final files = single
          ? [?await picker.pickFile(dialogTitle: widget.label)]
          : await picker.pickFiles(dialogTitle: widget.label);
      if (!mounted || files.isEmpty) return;
      final selected = <_PickedFile>[];
      for (final file in files) {
        final path = await widget.engine.stageFile(
          name: file.name,
          bytes: await file.readAsBytes(),
        );
        selected.add(_PickedFile(file.name, path));
      }
      if (mounted) {
        widget.onChanged(
          single ? selected.first : [...widget.value as List, ...selected],
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not open the selected file. $e');
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Widget _fileChooser(_FileRole role) {
    final v = widget.value;
    final files = v is List
        ? v.whereType<_PickedFile>().toList()
        : [if (v is _PickedFile) v];
    final multiple = role != _FileRole.input;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: Theme.of(context).textTheme.titleSmall),
        for (var i = 0; i < files.length; i++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: _batch
                ? Icon(
                    files[i].folder
                        ? Icons.folder_outlined
                        : Icons.insert_drive_file_outlined,
                  )
                : null,
            title: Text(files[i].name),
            trailing: multiple ? _rowActions(files, i) : null,
          ),
        OutlinedButton.icon(
          onPressed: _picking ? null : () => _files(role),
          icon: const Icon(Icons.folder_open),
          label: Text(
            _picking
                ? 'Opening…'
                : role == _FileRole.fontFolders
                ? 'Choose fonts to scan'
                : multiple
                ? 'Choose files'
                : files.isEmpty
                ? 'Choose a file'
                : 'Change file',
          ),
        ),
        if (_batch)
          OutlinedButton.icon(
            onPressed: _picking ? null : () => _files(role, folder: true),
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('Choose folder'),
          ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }

  Widget _rowActions(List values, int i) => Wrap(
    children: [
      if (i > 0)
        IconButton(
          tooltip: 'Move item ${i + 1} up',
          onPressed: () {
            final next = [...values];
            final value = next.removeAt(i);
            next.insert(i - 1, value);
            widget.onChanged(next);
          },
          icon: const Icon(Icons.arrow_upward),
        ),
      IconButton(
        tooltip: 'Remove item ${i + 1}',
        onPressed: () => widget.onChanged([...values]..removeAt(i)),
        icon: const Icon(Icons.remove_circle_outline),
      ),
    ],
  );

  Widget _text({
    bool multiline = false,
    bool number = false,
    bool integer = false,
    String? helper,
    bool secret = false,
  }) => _TextValue(
    value: widget.value?.toString() ?? '',
    label: widget.label,
    onChanged: widget.onChanged,
    helper: helper,
    multiline: multiline,
    number: number,
    integer: integer,
    secret: secret,
  );

  @override
  Widget build(BuildContext context) {
    final schema = widget.schema;
    final name = widget.name;
    final label = widget.label;
    final value = widget.value;
    final role = _fileRole(widget.draft.tool, name, schema);
    if (role == _FileRole.input ||
        role == _FileRole.inputs ||
        role == _FileRole.fontFolders) {
      return _fileChooser(role!);
    }
    if (role == _FileRole.output || role == _FileRole.folder) {
      final formats = role == _FileRole.output
          ? _extensions(widget.draft.tool)
          : <String>[];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TextValue(
            label: role == _FileRole.folder
                ? 'Output folder name'
                : 'Output file name',
            value: value?.toString() ?? '',
            helper: 'Save or share the result after running the tool.',
            onChanged: widget.onChanged,
          ),
          if (formats.length > 1)
            Wrap(
              spacing: 6,
              children: [
                for (final ext in formats)
                  ChoiceChip(
                    label: Text(ext.toUpperCase()),
                    selected: value.toString().toLowerCase().endsWith('.$ext'),
                    onSelected: (_) {
                      final old = value.toString();
                      final dot = old.lastIndexOf('.');
                      widget.onChanged(
                        '${dot > 0 ? old.substring(0, dot) : old}.$ext',
                      );
                    },
                  ),
              ],
            ),
        ],
      );
    }
    final types = _types(schema);
    if (types.length > 1) {
      final type = _valueType(schema, value);
      final actual = value is _TypedValue ? value.value : value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey('type-$type'),
            initialValue: type,
            decoration: InputDecoration(labelText: '$label type'),
            items: [
              for (final t in types)
                DropdownMenuItem(
                  value: t,
                  child: Text(switch (t) {
                    'string' => 'Text',
                    'null' => 'No value',
                    'integer' => 'Whole number',
                    _ => argumentLabel(t),
                  }),
                ),
            ],
            onChanged: (t) {
              if (t != null) {
                widget.onChanged(
                  _TypedValue(
                    t,
                    widget.draft.initial(name, {...schema, 'type': t}),
                  ),
                );
              }
            },
          ),
          if (type != 'null')
            _Field(
              key: ValueKey(type),
              engine: widget.engine,
              draft: widget.draft,
              name: name,
              label: label,
              schema: {...schema, 'type': type},
              value: actual,
              onChanged: (s) => widget.onChanged(_TypedValue(type, s)),
            ),
        ],
      );
    }
    final options = schema['enum'];
    if (options is List && options.isNotEmpty) {
      return DropdownButtonFormField<Object>(
        key: ValueKey(value),
        initialValue: options.contains(value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final option in options.whereType<Object>())
            DropdownMenuItem(value: option, child: Text('$option')),
        ],
        onChanged: widget.onChanged,
      );
    }
    final type = types.first;
    final desc = schema['description'] as String?;
    if (type == 'boolean') {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        subtitle: desc == null ? null : Text(desc),
        value: value == true,
        onChanged: widget.onChanged,
      );
    }
    if (type == 'object') {
      return _group(
        label,
        ArgumentFields(
          engine: widget.engine,
          draft: widget.draft,
          schema: schema,
          values: (value as Map?)?.cast<String, dynamic>() ?? {},
          onChanged: widget.onChanged,
        ),
      );
    }
    if (_isPages(name, schema)) {
      return _text(helper: 'Page numbers or ranges, for example 1, 3–5.');
    }
    if (type == 'array') {
      final values = value as List? ?? [];
      final items =
          schema['items'] as ToolSchema? ??
          <String, dynamic>{
            'type': ['string', 'number', 'boolean', 'object', 'null'],
          };
      final enumItems = items['enum'];
      if (enumItems is List && schema['uniqueItems'] == true) {
        return _group(
          label,
          Wrap(
            spacing: 8,
            children: [
              for (final item in enumItems)
                FilterChip(
                  label: Text('$item'),
                  selected: values.contains(item),
                  onSelected: (on) {
                    final next = [...values];
                    if (on) {
                      next.add(item);
                    } else {
                      next.remove(item);
                    }
                    widget.onChanged(next);
                  },
                ),
            ],
          ),
        );
      }
      final fixed =
          schema['minItems'] != null &&
          schema['minItems'] == schema['maxItems'];
      final max = schema['maxItems'] as int?;
      return _group(
        label,
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (desc != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(desc),
              ),
            for (var i = 0; i < values.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!fixed)
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Item ${i + 1}',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                          _rowActions(values, i),
                        ],
                      ),
                    _Field(
                      engine: widget.engine,
                      draft: widget.draft,
                      name: '',
                      label: _entryLabel(name, i, values.length, fixed),
                      schema: items,
                      value: values[i],
                      onChanged: (v) => widget.onChanged([...values]..[i] = v),
                    ),
                  ],
                ),
              ),
            if (!fixed && (max == null || values.length < max))
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => widget.onChanged([
                    ...values,
                    widget.draft.initial('', items),
                  ]),
                  icon: const Icon(Icons.add),
                  label: const Text('Add item'),
                ),
              ),
          ],
        ),
      );
    }
    if (type == 'integer' || type == 'number') {
      return _text(number: true, integer: type == 'integer', helper: desc);
    }
    return _text(
      helper: desc,
      multiline: {
        'text',
        'script',
        'note',
        'description',
        'content',
      }.contains(name),
      secret: name.contains('password'),
    );
  }

  Widget _group(String label, Widget child) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        child,
      ],
    ),
  );

  String _entryLabel(String key, int i, int count, bool fixed) {
    if (fixed &&
        count == 2 &&
        {'at', 'point', 'offset', 'scale', ''}.contains(key)) {
      return i == 0 ? 'X' : 'Y';
    }
    if (fixed && count == 4 && {'rect', 'area', 'box'}.contains(key)) {
      return ['X₀', 'Y₀', 'X₁', 'Y₁'][i];
    }
    if (fixed && key == 'color' && count == 3) {
      return ['Red', 'Green', 'Blue'][i];
    }
    return fixed ? 'Value ${i + 1}' : 'Value';
  }
}

/// Keep the caret in place while typing and update it when a format chip,
/// reference picker or reordering gesture replaces the whole value.
class _TextValue extends StatefulWidget {
  const _TextValue({
    required this.label,
    required this.value,
    required this.onChanged,
    this.helper,
    this.multiline = false,
    this.number = false,
    this.integer = false,
    this.secret = false,
  });
  final String label, value;
  final String? helper;
  final bool multiline, number, integer, secret;
  final ValueChanged<String> onChanged;
  @override
  State<_TextValue> createState() => _TextValueState();
}

class _TextValueState extends State<_TextValue> {
  late final _controller = TextEditingController(text: widget.value);
  @override
  void didUpdateWidget(covariant _TextValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    obscureText: widget.secret,
    enableSuggestions: !widget.secret,
    autocorrect: !widget.secret,
    keyboardType: widget.number
        ? TextInputType.numberWithOptions(
            signed: true,
            decimal: !widget.integer,
          )
        : widget.multiline
        ? TextInputType.multiline
        : TextInputType.text,
    minLines: widget.multiline ? 2 : 1,
    maxLines: widget.multiline ? 6 : 1,
    decoration: InputDecoration(
      labelText: widget.label,
      helperText: widget.helper,
      helperMaxLines: 4,
      border: const OutlineInputBorder(),
    ),
    onChanged: widget.onChanged,
  );
}
