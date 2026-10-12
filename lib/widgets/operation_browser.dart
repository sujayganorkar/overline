import 'dart:convert';

import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';

import '../bridge/api.dart' as bridge;
import '../services/pdf_engine.dart';
import 'output_saver.dart';
import 'result_summary.dart';

class OperationBrowser extends StatefulWidget {
  const OperationBrowser({
    super.key,
    required this.engine,
    required this.handle,
    required this.onStatusChanged,
    this.initialQuery = '',
  });

  final PdfEngineApi engine;
  final int handle;
  final ValueChanged<bridge.DocumentStatus> onStatusChanged;
  final String initialQuery;

  @override
  State<OperationBrowser> createState() => _OperationBrowserState();
}

class _OperationBrowserState extends State<OperationBrowser> {
  List<bridge.OperationInfo> _operations = const [];
  String _query = '';
  String? _error;
  String? _running;
  String? _result;
  List<String> _resultPaths = const [];

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery;
    _loadOperations();
  }

  Future<void> _loadOperations() async {
    try {
      final operations = await widget.engine.operationCatalog();
      if (!mounted) return;
      setState(() => _operations = operations);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Could not load editing tools: $error');
    }
  }

  List<bridge.OperationInfo> get _filtered {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _operations;
    return _operations
        .where(
          (operation) =>
              operation.title.toLowerCase().contains(query) ||
              operation.description.toLowerCase().contains(query) ||
              operation.id.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  Future<void> _run(bridge.OperationInfo operation) async {
    final arguments = await _operationArguments(
      context,
      widget.engine,
      operation,
    );
    if (arguments == null || !mounted) return;

    if (operation.destructive) {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(operation.title),
          content: const Text(
            'This operation may remove or replace document content. Continue?',
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
      _running = operation.id;
      _error = null;
      _result = null;
      _resultPaths = const [];
    });
    try {
      final response = await widget.engine.executeTool(
        handle: widget.handle,
        tool: operation.id,
        argumentsJson: jsonEncode(arguments),
      );
      if (!mounted) return;
      widget.onStatusChanged(response.status);
      final resultContents = response.contents
          .where((content) => content.json.isNotEmpty)
          .toList(growable: false);
      setState(() {
        _result = resultContents.isEmpty
            ? '${operation.title} completed.'
            : resultContents
                  .map(
                    (content) =>
                        humanizeToolResult(operation.title, content.json),
                  )
                  .join('\n\n');
        _resultPaths = [
          for (final content in resultContents) ...outputPathsIn(content.json),
        ];
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _running = null);
    }
  }

  Future<void> _saveOutput(String path) async {
    try {
      final bytes = await widget.engine.readOutput(path: path);
      final uri = await FilePickerPlatform.instance.saveFile(
        fileName: path.split('/').last,
        bytes: bytes,
        mimeType: _mimeType(path),
        dialogTitle: 'Save exported file',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            uri == null
                ? 'Export cancelled'
                : 'Saved ${path.split('/').last} through Files',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Could not save exported output: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final operations = _filtered;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.88,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'PDF editing tools',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Find an operation',
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search by operation name or keyword',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_result != null)
              ExpansionTile(
                title: const Text('Last operation result'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(_result!),
                  ),
                  ..._resultPaths.map(
                    (path) => ListTile(
                      leading: const Icon(Icons.download),
                      title: Text(
                        'Save ${path.split('/').last}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _saveOutput(path),
                    ),
                  ),
                ],
              ),
            Expanded(
              child: _operations.isEmpty && _error == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: operations.length,
                      itemBuilder: (context, index) {
                        final operation = operations[index];
                        final busy = _running == operation.id;
                        return ListTile(
                          leading: Icon(
                            operation.readOnly ? Icons.search : Icons.edit,
                          ),
                          title: Text(operation.title),
                          subtitle: Text(
                            operation.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: busy
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : operation.destructive
                              ? const Icon(Icons.warning_amber)
                              : const Icon(Icons.chevron_right),
                          onTap: _running == null
                              ? () => _run(operation)
                              : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<Map<String, Object?>?> _operationArguments(
  BuildContext context,
  PdfEngineApi engine,
  bridge.OperationInfo operation,
) async {
  final schema = jsonDecode(operation.inputSchemaJson) as Map<String, dynamic>;
  final properties =
      (schema['properties'] as Map<String, dynamic>?) ?? const {};
  final requiredFields = ((schema['required'] as List<dynamic>?) ?? const [])
      .whereType<String>()
      .toSet();
  final controllers = <String, TextEditingController>{};
  final booleans = <String, bool>{};
  final selections = <String, Object?>{};
  final selectionLabels = <String, String>{};
  for (final entry in properties.entries) {
    final property = entry.value as Map<String, dynamic>;
    if (property['type'] == 'boolean') {
      booleans[entry.key] = property['default'] as bool? ?? false;
    } else {
      controllers[entry.key] = TextEditingController();
    }
  }
  final formKey = GlobalKey<FormState>();
  final errors = <String, String>{};
  try {
    return await showDialog<Map<String, Object?>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(operation.title),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(operation.description),
                    const SizedBox(height: 12),
                    for (final entry in properties.entries)
                      _argumentField(
                        dialogContext,
                        engine,
                        entry.key,
                        entry.value as Map<String, dynamic>,
                        requiredFields.contains(entry.key),
                        controllers[entry.key],
                        booleans,
                        selections,
                        selectionLabels,
                        errors,
                        setDialogState,
                      ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final output = <String, Object?>{};
                var valid = true;
                for (final entry in properties.entries) {
                  final key = entry.key;
                  final property = entry.value as Map<String, dynamic>;
                  if (property['type'] == 'boolean') {
                    output[key] = booleans[key] ?? false;
                    continue;
                  }
                  if (selections.containsKey(key)) {
                    output[key] = selections[key];
                    errors.remove(key);
                    continue;
                  }
                  final text = controllers[key]!.text.trim();
                  if (text.isEmpty) {
                    if (requiredFields.contains(key)) {
                      errors[key] = 'Required';
                      valid = false;
                    }
                    continue;
                  }
                  try {
                    final parsed = _parseArgument(text, property, name: key);
                    final description =
                        property['description'] as String? ?? '';
                    output[key] = _isOutputPath(key, description)
                        ? _workspaceOutputPath(parsed.toString())
                        : parsed;
                    errors.remove(key);
                  } catch (_) {
                    errors[key] = 'Check this value and its format.';
                    valid = false;
                  }
                }
                if (!valid) {
                  setDialogState(() {});
                } else {
                  Navigator.pop(dialogContext, output);
                }
              },
              child: const Text('Run'),
            ),
          ],
        ),
      ),
    );
  } finally {
    for (final controller in controllers.values) {
      controller.dispose();
    }
  }
}

Widget _argumentField(
  BuildContext context,
  PdfEngineApi engine,
  String name,
  Map<String, dynamic> schema,
  bool required,
  TextEditingController? controller,
  Map<String, bool> booleans,
  Map<String, Object?> selections,
  Map<String, String> selectionLabels,
  Map<String, String> errors,
  StateSetter setDialogState,
) {
  final type = schema['type'] as String?;
  if (type == 'boolean') {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(_argumentLabel(name)),
      value: booleans[name] ?? false,
      onChanged: (value) => setDialogState(() => booleans[name] = value),
    );
  }
  final enumValues = schema['enum'] as List<dynamic>?;
  if (enumValues != null && enumValues.every((value) => value is String)) {
    final options = enumValues.cast<String>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        initialValue: selections[name] as String?,
        decoration: InputDecoration(
          labelText: required
              ? '${_argumentLabel(name)} *'
              : _argumentLabel(name),
          errorText: errors[name],
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final option in options)
            DropdownMenuItem(value: option, child: Text(option)),
        ],
        onChanged: (value) => setDialogState(() {
          if (value == null) {
            selections.remove(name);
          } else {
            selections[name] = value;
          }
          errors.remove(name);
        }),
      ),
    );
  }

  final fileArrayInput = name == 'paths' && type == 'array';
  final description = (schema['description'] as String? ?? '').toLowerCase();
  final inputFile =
      {'file', 'image', 'input_file', 'other_file'}.contains(name) ||
      (name == 'path' &&
          (description.contains('source file') ||
              description.contains('input file') ||
              description.contains('file to compare')));
  final fileInput = fileArrayInput || inputFile;
  if (fileInput) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: OutlinedButton.icon(
        onPressed: () async {
          final picked = await FilePickerPlatform.instance.pickFiles(
            type: FileType.any,
          );
          if (picked.isEmpty) return;
          if (fileArrayInput) {
            final paths = <String>[];
            final names = <String>[];
            for (final file in picked) {
              final bytes = await file.readAsBytes();
              paths.add(await engine.stageFile(name: file.name, bytes: bytes));
              names.add(file.name);
            }
            setDialogState(() {
              selections[name] = paths;
              selectionLabels[name] = names.join(', ');
              controller?.text = '${names.length} files selected';
              errors.remove(name);
            });
            return;
          }
          final file = picked.first;
          final bytes = await file.readAsBytes();
          final path = await engine.stageFile(name: file.name, bytes: bytes);
          setDialogState(() {
            selections[name] = path;
            selectionLabels[name] = file.name;
            controller?.text = file.name;
            errors.remove(name);
          });
        },
        icon: const Icon(Icons.attach_file),
        label: Text(
          selectionLabels[name] ??
              (fileArrayInput ? 'Choose files' : 'Choose a file'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  final outputPath =
      {'path', 'out', 'folder', 'out_dir'}.contains(name) &&
      (description.contains('write') ||
          description.contains('output') ||
          description.contains('folder'));
  final typeLabel = _schemaType(schema['type']);
  final helper = outputPath
      ? 'Name the result; it will be offered to save when the task finishes.'
      : typeLabel == 'array'
      ? (name == 'pages'
            ? 'Enter page numbers or ranges, for example 1, 3, 5-7.'
            : 'Enter one value per line or separate values with commas.')
      : typeLabel == 'object'
      ? 'Enter one setting per line, for example: quality: 70.'
      : (schema['description'] as String?);
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: controller,
      keyboardType: typeLabel == 'integer' || typeLabel == 'number'
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : typeLabel == 'array' || typeLabel == 'object'
          ? TextInputType.multiline
          : TextInputType.text,
      minLines: typeLabel == 'array' || typeLabel == 'object' ? 2 : 1,
      maxLines: typeLabel == 'array' || typeLabel == 'object' ? 4 : 1,
      decoration: InputDecoration(
        labelText: required
            ? '${_argumentLabel(name)} *'
            : _argumentLabel(name),
        helperText: helper,
        hintText: outputPath
            ? (name == 'folder' || name == 'out_dir'
                  ? 'processed-files'
                  : 'result.pdf')
            : null,
        errorText: errors[name],
        border: const OutlineInputBorder(),
      ),
    ),
  );
}

Object _parseArgument(
  String value,
  Map<String, dynamic> schema, {
  String name = '',
}) {
  final type = _schemaType(schema['type']);
  switch (type) {
    case 'integer':
      return int.parse(value);
    case 'number':
      return double.parse(value);
    case 'array':
      final items = schema['items'] as Map<String, dynamic>? ?? const {};
      if (name == 'pages' && _schemaType(items['type']) == 'integer') {
        return _parsePageRanges(value);
      }
      final values = value
          .split(items['type'] == 'array' ? '\n' : RegExp(r'[,\n]'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty);
      return values
          .map((item) {
            if (_schemaType(items['type']) == 'array') {
              final nested =
                  items['items'] as Map<String, dynamic>? ?? const {};
              return item
                  .split(',')
                  .map((value) => _parseArgument(value.trim(), nested))
                  .toList(growable: false);
            }
            return _parseArgument(item, items);
          })
          .toList(growable: false);
    case 'object':
      final fields = schema['properties'] as Map<String, dynamic>? ?? const {};
      if (fields.isEmpty) {
        throw const FormatException(
          'This advanced setting has no simple editor.',
        );
      }
      final output = <String, Object?>{};
      for (final line in value.split('\n')) {
        final separator = line.indexOf(RegExp(r'[:=]'));
        if (separator <= 0) continue;
        final key = line.substring(0, separator).trim();
        final childSchema = fields[key];
        if (childSchema is! Map<String, dynamic>) {
          throw FormatException('Unknown setting: $key');
        }
        output[key] = _parseArgument(
          line.substring(separator + 1).trim(),
          childSchema,
          name: key,
        );
      }
      if (output.isEmpty) {
        throw const FormatException('Enter at least one setting.');
      }
      return output;
    case 'boolean':
      if (value.toLowerCase() == 'true' || value.toLowerCase() == 'yes') {
        return true;
      }
      if (value.toLowerCase() == 'false' || value.toLowerCase() == 'no') {
        return false;
      }
      throw const FormatException('Enter yes or no.');
    default:
      final allowed = schema['enum'];
      if (allowed is List && !allowed.contains(value)) {
        throw FormatException('Choose one of: ${allowed.join(', ')}.');
      }
      return value;
  }
}

String _schemaType(Object? value) {
  if (value is String) return value;
  if (value is List) {
    return value.whereType<String>().firstWhere(
      (type) => type != 'null',
      orElse: () => 'string',
    );
  }
  return 'string';
}

List<int> _parsePageRanges(String source) {
  final pages = <int>{};
  for (final part in source.split(',')) {
    final range = part.trim().split('-');
    final start = int.tryParse(range.first.trim());
    final end = range.length > 1 ? int.tryParse(range.last.trim()) : start;
    if (start == null || end == null || end < start) {
      throw const FormatException('Use page numbers or ranges like 2-4, 7.');
    }
    if (end - start > 10000) {
      throw const FormatException('The page range is too large.');
    }
    for (var page = start; page <= end; page++) {
      pages.add(page);
    }
  }
  return pages.toList()..sort();
}

String _argumentLabel(String name) {
  if (name == 'at') return 'Position on page';
  if (name == 'path' || name == 'out') return 'Output file name';
  return name
      .replaceAll('_', ' ')
      .replaceAllMapped(
        RegExp(r'\b[a-z]'),
        (match) => match.group(0)!.toUpperCase(),
      );
}

bool _isOutputPath(String name, String description) =>
    {'path', 'out', 'folder', 'out_dir'}.contains(name) &&
    (description.toLowerCase().contains('write') ||
        description.toLowerCase().contains('output') ||
        description.toLowerCase().contains('folder'));

String _workspaceOutputPath(String value) {
  final clean = value.replaceAll(RegExp(r'^/+'), '');
  return clean.startsWith('outputs/') ? clean : 'outputs/$clean';
}

String _mimeType(String path) {
  final ext = path.split('.').last.toLowerCase();
  return switch (ext) {
    'pdf' => 'application/pdf',
    'csv' => 'text/csv',
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'tif' || 'tiff' => 'image/tiff',
    'html' => 'text/html',
    'txt' => 'text/plain',
    _ => 'application/octet-stream',
  };
}
