import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';

import '../bridge/api.dart' as bridge;
import '../services/pdf_engine.dart';
import 'output_saver.dart';

/// A form field reported by `form_fields`.
class FormField {
  FormField({
    required this.name,
    required this.type,
    required this.value,
    required this.options,
    required this.page,
    required this.readOnly,
    this.rect,
  });

  final String name;
  final String type;
  final Object? value;
  final List<String> options;
  final int page;
  final bool readOnly;
  final List<double>? rect;

  static FormField? fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    if (name is! String || name.isEmpty) return null;
    final options = json['options'];
    final rawRect = json['rect'];
    final rect = (rawRect is List && rawRect.length == 4)
        ? [for (final r in rawRect) (r as num).toDouble()]
        : null;
    return FormField(
      name: name,
      type: json['type'] as String? ?? 'text',
      value: json['value'],
      options: options is List
          ? [
              for (final o in options)
                if (o is String) o,
            ]
          : const [],
      page: (json['page'] as num?)?.toInt() ?? 1,
      readOnly: json['read_only'] == true,
      rect: rect,
    );
  }
}

class FormScreen extends StatefulWidget {
  const FormScreen({
    super.key,
    required this.engine,
    required this.handle,
    required this.onStatusChanged,
  });

  final PdfEngineApi engine;
  final int handle;
  final ValueChanged<bridge.DocumentStatus> onStatusChanged;

  @override
  State<FormScreen> createState() => _FormScreenState();
}

class _FormScreenState extends State<FormScreen> {
  List<FormField> _fields = const [];
  final Map<String, Object?> _values = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;
  int _prefillRefresh = 0;

  bool _visualMode = true;
  int _activePageIndex = 1;
  int _totalPages = 1;
  int _focusedFieldIndex = 0;
  final Map<int, Uint8List> _pagePngCache = {};
  final Map<int, Size> _pageSizeCache = {};
  bool _renderingPage = false;
  late final TextEditingController _inlineTextController;
  late final FocusNode _inlineFocusNode;

  @override
  void initState() {
    super.initState();
    _inlineTextController = TextEditingController();
    _inlineFocusNode = FocusNode();
    _load();
  }

  @override
  void dispose() {
    _inlineTextController.dispose();
    _inlineFocusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final response = await widget.engine.executeTool(
        handle: widget.handle,
        tool: 'form_fields',
        argumentsJson: '{}',
      );
      final fields = <FormField>[];
      for (final content in response.contents) {
        if (content.json.isEmpty) continue;
        final decoded = jsonDecode(content.json);
        final list = decoded is List
            ? decoded
            : decoded is Map<String, dynamic>
            ? decoded['fields']
            : null;
        if (list is List) {
          for (final item in list) {
            if (item is Map<String, dynamic>) {
              final field = FormField.fromJson(item);
              if (field != null) fields.add(field);
            }
          }
        }
      }
      final status = await widget.engine.status(handle: widget.handle);
      final totalPages = math.max(1, status.pageCount);
      if (!mounted) return;
      final hasVisualRects = fields.any((f) => f.rect != null);
      setState(() {
        _fields = fields;
        for (final field in fields) {
          _values[field.name] = field.value;
        }
        _totalPages = totalPages;
        _visualMode = hasVisualRects;
        _pagePngCache.clear();
        _pageSizeCache.clear();
        if (fields.isNotEmpty) {
          _focusedFieldIndex = 0;
          _activePageIndex = fields[0].page;
          _inlineTextController.text =
              _values[fields[0].name]?.toString() ?? '';
        }
        _loading = false;
      });
      if (hasVisualRects && fields.isNotEmpty) {
        _loadActivePage(_activePageIndex);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadActivePage(int page) async {
    if (_pagePngCache.containsKey(page) && _pageSizeCache.containsKey(page)) {
      return;
    }
    setState(() => _renderingPage = true);
    try {
      final png = await widget.engine.renderPagePng(
        handle: widget.handle,
        page1Based: page,
        dpi: 96,
      );
      final size = await widget.engine.pageSize(
        handle: widget.handle,
        page1Based: page,
      );
      if (!mounted) return;
      setState(() {
        _pagePngCache[page] = png;
        _pageSizeCache[page] = Size(size.width, size.height);
        _renderingPage = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _renderingPage = false);
    }
  }

  void _focusField(int index) {
    if (index < 0 || index >= _fields.length) return;
    final field = _fields[index];
    setState(() {
      _focusedFieldIndex = index;
      _inlineTextController.text = _values[field.name]?.toString() ?? '';
      if (_activePageIndex != field.page) {
        _activePageIndex = field.page;
        _loadActivePage(field.page);
      }
    });
  }

  void _nextField() {
    if (_focusedFieldIndex + 1 < _fields.length) {
      _focusField(_focusedFieldIndex + 1);
    }
  }

  void _prevField() {
    if (_focusedFieldIndex > 0) {
      _focusField(_focusedFieldIndex - 1);
    }
  }

  Future<void> _detect() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final response = await widget.engine.executeTool(
        handle: widget.handle,
        tool: 'form_detect_fields',
        argumentsJson: '{}',
      );
      if (!mounted) return;
      widget.onStatusChanged(response.status);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Field detection done')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear this form?'),
        content: const Text(
          'Every field returns to its default value. This is undoable.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep values'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear form'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final response = await widget.engine.executeTool(
        handle: widget.handle,
        tool: 'form_reset',
        argumentsJson: '{}',
      );
      if (!mounted) return;
      widget.onStatusChanged(response.status);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Form cleared')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _exportData() async {
    final extension = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: const Text('Spreadsheet (.csv)'),
              onTap: () => Navigator.pop(context, 'csv'),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Form data (.xfdf)'),
              onTap: () => Navigator.pop(context, 'xfdf'),
            ),
          ],
        ),
      ),
    );
    if (extension == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final response = await widget.engine.executeTool(
        handle: widget.handle,
        tool: 'doc_export_data',
        argumentsJson: jsonEncode({
          'path': 'outputs/form-data.$extension',
          'what': 'fields',
        }),
      );
      if (!mounted) return;
      await saveToolOutputs(context, widget.engine, [
        for (final c in response.contents) c.json,
      ]);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _importData() async {
    final picked = await FilePickerPlatform.instance.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xfdf', 'fdf', 'xml', 'csv', 'txt'],
      dialogTitle: 'Choose form data to import',
    );
    if (picked.isEmpty || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final file = picked.first;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) throw StateError('${file.name} is empty');
      final staged = await widget.engine.stageFile(
        name: 'import-${file.name}',
        bytes: bytes,
      );
      if (!mounted) return;
      final response = await widget.engine.executeTool(
        handle: widget.handle,
        tool: 'doc_import_data',
        argumentsJson: jsonEncode({'path': staged}),
      );
      if (!mounted) return;
      widget.onStatusChanged(response.status);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Values imported — review, then Save.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    // Sync current focused inline text if user was typing
    if (_fields.isNotEmpty &&
        _focusedFieldIndex >= 0 &&
        _focusedFieldIndex < _fields.length) {
      final cur = _fields[_focusedFieldIndex];
      if (!cur.readOnly &&
          cur.type != 'checkbox' &&
          cur.type != 'signature' &&
          cur.type != 'button') {
        _values[cur.name] = _inlineTextController.text;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final values = <String, Object?>{};
      for (final field in _fields) {
        if (field.readOnly) continue;
        final value = _values[field.name];
        if (value == null) continue;
        if (value is String && value.isEmpty) continue;
        values[field.name] = value;
      }
      final response = await widget.engine.executeTool(
        handle: widget.handle,
        tool: 'form_fill',
        argumentsJson: jsonEncode({'values': values}),
      );
      if (!mounted) return;
      widget.onStatusChanged(response.status);
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Form values applied to document')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fill form'),
        actions: [
          IconButton(
            onPressed: _loading || _saving ? null : _detect,
            icon: const Icon(Icons.auto_fix_high_outlined),
            tooltip: 'Detect fields',
          ),
          IconButton(
            onPressed: _loading || _saving ? null : _reset,
            icon: const Icon(Icons.restart_alt_outlined),
            tooltip: 'Clear form to defaults',
          ),
          PopupMenuButton<String>(
            tooltip: 'Import or export values',
            onSelected: (choice) {
              if (choice == 'export') {
                _exportData();
              } else {
                _importData();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'export', child: Text('Export values')),
              PopupMenuItem(value: 'import', child: Text('Import values')),
            ],
          ),
          FilledButton.tonal(
            onPressed: _saving || _loading ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Apply'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _fields.isEmpty
          ? Center(
              child: Text(
                _error ?? 'This document has no fillable form fields.',
              ),
            )
          : Column(
              children: [
                // Mode Switcher & Page Selector Strip
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    border: Border(
                      bottom: BorderSide(
                        color: theme.colorScheme.outlineVariant,
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment<bool>(
                            value: true,
                            label: Text('Page View'),
                            icon: Icon(Icons.picture_as_pdf_outlined, size: 16),
                          ),
                          ButtonSegment<bool>(
                            value: false,
                            label: Text('Field List'),
                            icon: Icon(
                              Icons.format_list_bulleted_outlined,
                              size: 16,
                            ),
                          ),
                        ],
                        selected: {_visualMode},
                        onSelectionChanged: (selection) {
                          setState(() {
                            _visualMode = selection.first;
                            if (_visualMode && _fields.isNotEmpty) {
                              _loadActivePage(_activePageIndex);
                            }
                          });
                        },
                      ),
                      const Spacer(),
                      if (_visualMode && _totalPages > 1) ...[
                        IconButton(
                          tooltip: 'Previous page',
                          icon: const Icon(Icons.chevron_left),
                          onPressed: _activePageIndex > 1
                              ? () {
                                  setState(() => _activePageIndex--);
                                  _loadActivePage(_activePageIndex);
                                }
                              : null,
                        ),
                        Text(
                          '$_activePageIndex / $_totalPages',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Next page',
                          icon: const Icon(Icons.chevron_right),
                          onPressed: _activePageIndex < _totalPages
                              ? () {
                                  setState(() => _activePageIndex++);
                                  _loadActivePage(_activePageIndex);
                                }
                              : null,
                        ),
                      ],
                    ],
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                Expanded(
                  child: _visualMode
                      ? _buildVisualCanvas(context)
                      : _buildFieldListView(context),
                ),
                if (_visualMode && _fields.isNotEmpty)
                  _buildBottomAccessoryStrip(theme),
              ],
            ),
      floatingActionButton: !_visualMode && !_loading && !_saving
          ? FloatingActionButton.extended(
              onPressed: _addField,
              icon: const Icon(Icons.add),
              label: const Text('Add field'),
            )
          : null,
    );
  }

  Widget _buildFieldListView(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('Use details to fill fields'),
            subtitle: const Text(
              'Paste labelled details, review matches, then edit before saving',
            ),
            onTap: _saving ? null : _prefillFromDetails,
          ),
        ),
        for (final field in _fields) _fieldInput(field),
      ],
    );
  }

  Widget _buildVisualCanvas(BuildContext context) {
    final png = _pagePngCache[_activePageIndex];
    final pageSize = _pageSizeCache[_activePageIndex];

    if (_renderingPage || png == null || pageSize == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Rendering page...'),
          ],
        ),
      );
    }

    final theme = Theme.of(context);
    final pageFields = _fields
        .where((f) => f.page == _activePageIndex && f.rect != null)
        .toList();

    return InteractiveViewer(
      minScale: 0.8,
      maxScale: 5.0,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scale = math.min(
                constraints.maxWidth / pageSize.width,
                constraints.maxHeight / pageSize.height,
              );
              final renderWidth = pageSize.width * scale;
              final renderHeight = pageSize.height * scale;

              return SizedBox(
                width: renderWidth,
                height: renderHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Base Page Rendering
                    Positioned.fill(child: Image.memory(png, fit: BoxFit.fill)),
                    if (pageFields.isEmpty)
                      Positioned(
                        top: 12,
                        left: 12,
                        right: 12,
                        child: Material(
                          color: theme.colorScheme.surfaceContainerHigh
                              .withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(8),
                          elevation: 2,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 16,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'No form fields on page $_activePageIndex. Switch page to interact with fields.',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    for (final f in pageFields)
                      Builder(
                        builder: (context) {
                          final r = f.rect!;
                          final x1 = math.min(r[0], r[2]);
                          final x2 = math.max(r[0], r[2]);
                          final y1 = math.min(r[1], r[3]);
                          final y2 = math.max(r[1], r[3]);
                          final left = x1 * scale;
                          final top = y1 * scale;
                          final width = math.max(28.0, (x2 - x1) * scale);
                          final height = math.max(24.0, (y2 - y1) * scale);
                          final fieldIndex = _fields.indexOf(f);
                          final isFocused = fieldIndex == _focusedFieldIndex;
                          final valStr =
                              _values[f.name]?.toString().trim() ?? '';
                          final hasValue =
                              valStr.isNotEmpty && valStr != 'false';

                          return Positioned(
                            left: left,
                            top: top,
                            width: width,
                            height: height,
                            child: Semantics(
                              label:
                                  'Form field ${f.name}, type ${f.type}, value ${_values[f.name] ?? "empty"}',
                              button: true,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _focusField(fieldIndex),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  decoration: BoxDecoration(
                                    color: isFocused
                                        ? theme.colorScheme.primary.withValues(
                                            alpha: 0.28,
                                          )
                                        : hasValue
                                        ? Colors.green.withValues(alpha: 0.12)
                                        : theme.colorScheme.primary.withValues(
                                            alpha: 0.08,
                                          ),
                                    border: Border.all(
                                      color: isFocused
                                          ? theme.colorScheme.primary
                                          : hasValue
                                          ? Colors.green.shade600
                                          : theme.colorScheme.primary
                                                .withValues(alpha: 0.6),
                                      width: isFocused ? 2.5 : 1.5,
                                    ),
                                    borderRadius: BorderRadius.circular(3),
                                    boxShadow: isFocused
                                        ? [
                                            BoxShadow(
                                              color: theme.colorScheme.primary
                                                  .withValues(alpha: 0.35),
                                              blurRadius: 6,
                                              spreadRadius: 1,
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      if (hasValue && !isFocused)
                                        Positioned(
                                          top: 1,
                                          right: 1,
                                          child: Container(
                                            padding: const EdgeInsets.all(1),
                                            decoration: BoxDecoration(
                                              color: Colors.green.shade600,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.check,
                                              size: 10,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      if (isFocused)
                                        Positioned(
                                          top: -20,
                                          left: 0,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: theme.colorScheme.primary,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              f.name,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBottomAccessoryStrip(ThemeData theme) {
    if (_fields.isEmpty ||
        _focusedFieldIndex < 0 ||
        _focusedFieldIndex >= _fields.length) {
      return const SizedBox.shrink();
    }
    final activeField = _fields[_focusedFieldIndex];
    final hasPrev = _focusedFieldIndex > 0;
    final hasNext = _focusedFieldIndex + 1 < _fields.length;

    return Material(
      elevation: 8,
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous field',
                    icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                    onPressed: hasPrev ? _prevField : null,
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'Field ${_focusedFieldIndex + 1} of ${_fields.length} (Page ${activeField.page})',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          activeField.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next field',
                    icon: const Icon(Icons.arrow_forward_ios, size: 18),
                    onPressed: hasNext ? _nextField : null,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildFocusedFieldInput(activeField, theme, hasNext),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFocusedFieldInput(
    FormField field,
    ThemeData theme,
    bool hasNext,
  ) {
    if (field.readOnly) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            '${_values[field.name] ?? "(empty)"} (Read-only field)',
            style: TextStyle(color: theme.colorScheme.outline),
          ),
        ),
      );
    }

    if (field.type == 'checkbox') {
      final checked = _values[field.name] == true;
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            checked ? 'Checked' : 'Unchecked',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(width: 8),
          Switch(
            value: checked,
            onChanged: (v) {
              setState(() => _values[field.name] = v);
            },
          ),
          const SizedBox(width: 12),
          if (hasNext)
            FilledButton.tonalIcon(
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: const Text('Next'),
              onPressed: _nextField,
            ),
        ],
      );
    }

    if (['radio', 'combo', 'list'].contains(field.type)) {
      final current = _values[field.name]?.toString();
      final items = field.options.isEmpty && current != null
          ? [current]
          : field.options;

      if (items.length <= 4 && items.isNotEmpty) {
        return Wrap(
          spacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final opt in items)
              ChoiceChip(
                label: Text(opt),
                selected: current == opt,
                onSelected: (selected) {
                  setState(() => _values[field.name] = selected ? opt : null);
                },
              ),
          ],
        );
      } else {
        return DropdownButtonFormField<String>(
          initialValue: items.contains(current) ? current : null,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            hintText: 'Select option',
          ),
          items: [
            for (final opt in items)
              DropdownMenuItem(value: opt, child: Text(opt)),
          ],
          onChanged: (v) {
            setState(() => _values[field.name] = v);
          },
        );
      }
    }

    if (field.type == 'signature' || field.type == 'button') {
      return Center(
        child: Text(
          '${field.type} field · use Sign in Edit to sign',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _inlineTextController,
            focusNode: _inlineFocusNode,
            textInputAction: hasNext
                ? TextInputAction.next
                : TextInputAction.done,
            onChanged: (val) {
              _values[field.name] = val;
            },
            onSubmitted: (_) {
              if (hasNext) {
                _nextField();
              }
            },
            decoration: InputDecoration(
              hintText: 'Enter ${field.name}',
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              suffixIcon: _inlineTextController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _inlineTextController.clear();
                        setState(() => _values[field.name] = '');
                      },
                    )
                  : null,
            ),
          ),
        ),
        if (hasNext) ...[
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'Next field',
            icon: const Icon(Icons.arrow_forward),
            onPressed: _nextField,
          ),
        ],
      ],
    );
  }

  Future<void> _prefillFromDetails() async {
    final controller = TextEditingController();
    try {
      final text = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Paste labelled details'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('One per line, using the form field label:'),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  hintText: 'Full name: Ada Lovelace\nEmail: ada@example.com',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Match fields'),
            ),
          ],
        ),
      );
      if (text == null || !mounted) return;
      final provided = <String, String>{};
      for (final line in text.split('\n')) {
        final delimiter = line.indexOf(RegExp(r'[:=]'));
        if (delimiter <= 0) continue;
        final label = _normalizeFieldName(line.substring(0, delimiter));
        final value = line.substring(delimiter + 1).trim();
        if (label.isNotEmpty && value.isNotEmpty) provided[label] = value;
      }
      final matches = <FormField, Object?>{};
      for (final field in _fields) {
        if (field.readOnly ||
            field.type == 'signature' ||
            field.type == 'button') {
          continue;
        }
        final value = provided[_normalizeFieldName(field.name)];
        if (value == null) continue;
        if (field.type == 'checkbox') {
          final normalized = value.toLowerCase();
          if (['true', 'yes', 'checked', '1'].contains(normalized)) {
            matches[field] = true;
          } else if (['false', 'no', 'unchecked', '0'].contains(normalized)) {
            matches[field] = false;
          }
        } else if (['combo', 'list', 'radio'].contains(field.type)) {
          final option = field.options.cast<String?>().firstWhere(
            (item) => item?.toLowerCase() == value.toLowerCase(),
            orElse: () => null,
          );
          if (option != null) matches[field] = option;
        } else {
          matches[field] = value;
        }
      }
      if (matches.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No exact field labels matched. Check the labels and try again.',
            ),
          ),
        );
        return;
      }
      final selected = matches.keys.toSet();
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Review suggested values'),
            content: SizedBox(
              width: 440,
              height: MediaQuery.sizeOf(context).height * 0.48,
              child: Column(
                children: [
                  const Text(
                    'These values will be placed in the fields below, not saved yet. Review and edit them before tapping Save.',
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final entry in matches.entries)
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(entry.key.name),
                            subtitle: Text('${entry.value}'),
                            value: selected.contains(entry.key),
                            onChanged: (checked) => setDialogState(() {
                              if (checked == true) {
                                selected.add(entry.key);
                              } else {
                                selected.remove(entry.key);
                              }
                            }),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(context, true),
                child: Text('Use ${selected.length} values'),
              ),
            ],
          ),
        ),
      );
      if (approved != true || !mounted) return;
      setState(() {
        for (final field in selected) {
          _values[field.name] = matches[field];
        }
        _prefillRefresh++;
      });
    } finally {
      controller.dispose();
    }
  }

  String _normalizeFieldName(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  Future<void> _addField() async {
    String type = 'text';
    final pageController = TextEditingController(text: '1');
    final nameController = TextEditingController();
    String band = 'top';
    try {
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Add form field'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(
                    labelText: 'Type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'text', child: Text('Text')),
                    DropdownMenuItem(
                      value: 'checkbox',
                      child: Text('Checkbox'),
                    ),
                    DropdownMenuItem(value: 'combo', child: Text('Dropdown')),
                    DropdownMenuItem(
                      value: 'signature',
                      child: Text('Signature'),
                    ),
                    DropdownMenuItem(value: 'date', child: Text('Date')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => type = v);
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: pageController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Page',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: band,
                        decoration: const InputDecoration(
                          labelText: 'Position',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'top', child: Text('Top')),
                          DropdownMenuItem(
                            value: 'middle',
                            child: Text('Middle'),
                          ),
                          DropdownMenuItem(
                            value: 'bottom',
                            child: Text('Bottom'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => band = v);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Add'),
              ),
            ],
          ),
        ),
      );
      if (go != true || !mounted) return;
      final page = int.tryParse(pageController.text.trim()) ?? 0;
      if (page < 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid page number')),
        );
        return;
      }
      setState(() => _saving = true);
      try {
        final size = await widget.engine.pageSize(
          handle: widget.handle,
          page1Based: page,
        );
        final bandY = switch (band) {
          'middle' => size.height / 2 - 15,
          'bottom' => size.height - 90,
          _ => 72.0,
        };
        final rect = type == 'checkbox'
            ? [72.0, bandY, 102.0, bandY + 30]
            : [72.0, bandY, size.width - 72.0, bandY + 30];
        final args = <String, Object?>{
          'page': page,
          'type': type,
          'rect': rect,
          if (nameController.text.trim().isNotEmpty)
            'name': nameController.text.trim(),
        };
        final response = await widget.engine.executeTool(
          handle: widget.handle,
          tool: 'form_add_field',
          argumentsJson: jsonEncode(args),
        );
        if (!mounted) return;
        widget.onStatusChanged(response.status);
        await _load();
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Field added')));
      } catch (e) {
        if (!mounted) return;
        setState(() => _error = '$e');
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    } finally {
      pageController.dispose();
      nameController.dispose();
    }
  }

  Future<void> _previewFieldOnPage(FormField field) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final png = await widget.engine.renderPagePng(
        handle: widget.handle,
        page1Based: field.page,
        dpi: 96,
      );
      final pageSize = await widget.engine.pageSize(
        handle: widget.handle,
        page1Based: field.page,
      );
      if (!mounted) return;
      Navigator.pop(context);

      await showDialog<void>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: Text('${field.name} · Page ${field.page}'),
          content: SizedBox(
            width: 480,
            height: MediaQuery.sizeOf(dialogCtx).height * 0.55,
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 6,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final scale = math.min(
                    constraints.maxWidth / pageSize.width,
                    constraints.maxHeight / pageSize.height,
                  );
                  final renderWidth = pageSize.width * scale;
                  final renderHeight = pageSize.height * scale;
                  final r = field.rect;

                  return Center(
                    child: SizedBox(
                      width: renderWidth,
                      height: renderHeight,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Image.memory(png, fit: BoxFit.fill),
                          ),
                          if (r != null && r.length == 4)
                            Positioned(
                              left: r[0] * scale,
                              top: r[1] * scale,
                              width: (r[2] - r[0]) * scale,
                              height: (r[3] - r[1]) * scale,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.35),
                                  border: Border.all(
                                    color: Colors.deepOrange,
                                    width: 2.5,
                                  ),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(
          context,
          rootNavigator: true,
        ).popUntil((r) => r.isFirst || r is! DialogRoute);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not preview field on page: $e')),
        );
      }
    }
  }

  void _onFieldLocationTap(FormField field) {
    if (field.rect != null) {
      _focusField(_fields.indexOf(field));
      setState(() => _visualMode = true);
    } else {
      _previewFieldOnPage(field);
    }
  }

  Widget _fieldInput(FormField field) {
    if (field.readOnly) {
      return ListTile(
        title: Text(field.name),
        subtitle: Text('${field.value ?? ''} (read-only)'),
        trailing: IconButton(
          tooltip: field.rect != null
              ? 'Focus on page ${field.page}'
              : 'Preview on page ${field.page}',
          icon: const Icon(Icons.location_searching, size: 20),
          onPressed: () => _onFieldLocationTap(field),
        ),
      );
    }
    switch (field.type) {
      case 'checkbox':
        final checked = _values[field.name] == true;
        return CheckboxListTile(
          title: Text(field.name),
          value: checked,
          secondary: IconButton(
            tooltip: field.rect != null
                ? 'Focus on page ${field.page}'
                : 'Preview on page ${field.page}',
            icon: const Icon(Icons.location_searching, size: 20),
            onPressed: () => _onFieldLocationTap(field),
          ),
          onChanged: (v) => setState(() => _values[field.name] = v ?? false),
        );
      case 'radio':
      case 'combo':
      case 'list':
        final current = _values[field.name]?.toString();
        final items = field.options.isEmpty && current != null
            ? [current]
            : field.options;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('form-select-${field.name}-$_prefillRefresh'),
                  initialValue: items.contains(current) ? current : null,
                  decoration: InputDecoration(
                    labelText: '${field.name} (p${field.page})',
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final option in items)
                      DropdownMenuItem(value: option, child: Text(option)),
                  ],
                  onChanged: (v) => setState(() => _values[field.name] = v),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: field.rect != null
                    ? 'Focus on page ${field.page}'
                    : 'Preview on page ${field.page}',
                icon: const Icon(Icons.location_searching, size: 20),
                onPressed: () => _onFieldLocationTap(field),
              ),
            ],
          ),
        );
      case 'button':
      case 'signature':
        return ListTile(
          title: Text(field.name),
          subtitle: Text('${field.type} field — use editing tools'),
          trailing: IconButton(
            tooltip: field.rect != null
                ? 'Focus on page ${field.page}'
                : 'Preview on page ${field.page}',
            icon: const Icon(Icons.location_searching, size: 20),
            onPressed: () => _onFieldLocationTap(field),
          ),
        );
      default:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('form-text-${field.name}-$_prefillRefresh'),
                  initialValue: _values[field.name]?.toString() ?? '',
                  decoration: InputDecoration(
                    labelText: '${field.name} (p${field.page})',
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (v) => _values[field.name] = v,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: field.rect != null
                    ? 'Focus on page ${field.page}'
                    : 'Preview on page ${field.page}',
                icon: const Icon(Icons.location_searching, size: 20),
                onPressed: () => _onFieldLocationTap(field),
              ),
            ],
          ),
        );
    }
  }
}
