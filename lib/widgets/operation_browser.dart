import 'dart:convert';

import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';

import '../bridge/api.dart' as bridge;
import '../services/pdf_engine.dart';

class OperationBrowser extends StatefulWidget {
  const OperationBrowser({
    super.key,
    required this.engine,
    required this.handle,
    required this.onStatusChanged,
  });

  final PdfEngineApi engine;
  final int handle;
  final ValueChanged<bridge.DocumentStatus> onStatusChanged;

  @override
  State<OperationBrowser> createState() => _OperationBrowserState();
}

class _OperationBrowserState extends State<OperationBrowser> {
  List<bridge.OperationInfo> _operations = const [];
  String _query = '';
  String? _error;
  String? _running;
  String? _result;

  @override
  void initState() {
    super.initState();
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
    });
    try {
      final response = await widget.engine.executeTool(
        handle: widget.handle,
        tool: operation.id,
        argumentsJson: jsonEncode(arguments),
      );
      if (!mounted) return;
      widget.onStatusChanged(response.status);
      final jsonResults = response.contents
          .where((content) => content.json.isNotEmpty)
          .map((content) => _prettyJson(content.json))
          .toList(growable: false);
      setState(() {
        _result = jsonResults.isEmpty
            ? '${operation.title} completed.'
            : jsonResults.join('\n\n');
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
            uri == null ? 'Export cancelled' : 'Export saved to $uri',
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
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Find an operation',
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
                  ..._pathsInResult(_result!).map(
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
  for (final entry in properties.entries) {
    final property = entry.value as Map<String, dynamic>;
    if (property['type'] == 'boolean') {
      booleans[entry.key] = property['default'] as bool? ?? false;
    } else {
      controllers[entry.key] = TextEditingController(
        text: switch (property['type']) {
          'array' => '[]',
          'object' => '{}',
          _ => '',
        },
      );
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
                  final text = controllers[key]!.text.trim();
                  if (text.isEmpty) {
                    if (requiredFields.contains(key)) {
                      errors[key] = 'Required';
                      valid = false;
                    }
                    continue;
                  }
                  try {
                    output[key] = _parseArgument(text, property);
                    errors.remove(key);
                  } catch (_) {
                    errors[key] =
                        'Enter a valid ${property['type'] ?? 'value'}';
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
  Map<String, String> errors,
  StateSetter setDialogState,
) {
  final type = schema['type'] as String?;
  final enumValues = schema['enum'] as List<dynamic>?;
  if (type == 'boolean') {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(name),
      value: booleans[name] ?? false,
      onChanged: (value) => setDialogState(() => booleans[name] = value),
    );
  }
  final fileArrayInput = name == 'paths' && type == 'array';
  final fileInput =
      fileArrayInput || {'file', 'image', 'input_file', 'path'}.contains(name);
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: controller,
      keyboardType: type == 'integer' || type == 'number'
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : type == 'array' || type == 'object'
          ? TextInputType.multiline
          : TextInputType.text,
      minLines: type == 'array' || type == 'object' ? 2 : 1,
      maxLines: type == 'array' || type == 'object' ? 4 : 1,
      decoration: InputDecoration(
        labelText: required ? '$name *' : name,
        helperText: enumValues == null
            ? (type == 'array' || type == 'object' ? 'JSON input' : null)
            : 'Options: ${enumValues.join(', ')}',
        errorText: errors[name],
        border: const OutlineInputBorder(),
        suffixIcon: fileInput
            ? IconButton(
                tooltip: 'Choose supporting files',
                icon: const Icon(Icons.attach_file),
                onPressed: () async {
                  final picked = await FilePickerPlatform.instance.pickFiles(
                    type: FileType.any,
                  );
                  if (picked.isEmpty) return;
                  if (fileArrayInput) {
                    final paths = <String>[];
                    for (final file in picked) {
                      final bytes = await file.readAsBytes();
                      paths.add(
                        await engine.stageFile(name: file.name, bytes: bytes),
                      );
                    }
                    controller?.text = jsonEncode(paths);
                    return;
                  }
                  final file = picked.first;
                  final bytes = await file.readAsBytes();
                  final path = await engine.stageFile(
                    name: file.name,
                    bytes: bytes,
                  );
                  controller?.text = path;
                },
              )
            : null,
      ),
    ),
  );
}

Object _parseArgument(String value, Map<String, dynamic> schema) {
  final type = schema['type'];
  if (schema.containsKey('oneOf') ||
      schema.containsKey('anyOf') ||
      type is List) {
    return jsonDecode(value) as Object;
  }
  switch (type) {
    case 'integer':
      return int.parse(value);
    case 'number':
      return double.parse(value);
    case 'array':
    case 'object':
      return jsonDecode(value) as Object;
    case 'boolean':
      return value.toLowerCase() == 'true';
    default:
      return value;
  }
}

String _prettyJson(String source) {
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(source));
  } catch (_) {
    return source;
  }
}

List<String> _pathsInResult(String source) {
  try {
    final value = jsonDecode(source);
    final paths = <String>[];
    void visit(Object? node) {
      if (node is Map<String, dynamic>) {
        for (final entry in node.entries) {
          if (entry.key == 'path' && entry.value is String) {
            paths.add(entry.value as String);
          }
          visit(entry.value);
        }
      } else if (node is List) {
        for (final item in node) {
          visit(item);
        }
      }
    }

    visit(value);
    return paths.toSet().toList(growable: false);
  } catch (_) {
    return const [];
  }
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
