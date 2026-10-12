import 'dart:convert';

import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';

import '../bridge/api.dart' as bridge;
import '../services/pdf_engine.dart';
import 'file_order_sheet.dart';
import 'output_saver.dart';

/// Combine, split, extract, label, and stamp pages. File outputs go through
/// the shared output saver (workspace paths → Save As).
class OrganizeSheet extends StatefulWidget {
  const OrganizeSheet({
    super.key,
    required this.engine,
    required this.handle,
    required this.pageCount,
    this.hasDocument = true,
    this.onOpenPages,
    required this.onStatusChanged,
  });

  final PdfEngineApi engine;
  final int handle;
  final int pageCount;
  final bool hasDocument;
  final Future<void> Function()? onOpenPages;
  final ValueChanged<bridge.DocumentStatus> onStatusChanged;

  @override
  State<OrganizeSheet> createState() => _OrganizeSheetState();
}

class _OrganizeSheetState extends State<OrganizeSheet> {
  bool _busy = false;

  Future<void> _run(
    String tool,
    Map<String, Object?> args, {
    bool refreshStatus = true,
  }) async {
    setState(() => _busy = true);
    try {
      final response = await widget.engine.executeTool(
        handle: widget.handle,
        tool: tool,
        argumentsJson: jsonEncode(args),
      );
      if (!mounted) return;
      if (refreshStatus) widget.onStatusChanged(response.status);
      await saveToolOutputs(context, widget.engine, [
        for (final c in response.contents) c.json,
      ]);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${_actionName(tool)} complete.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not ${_actionName(tool)}: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _combine() async {
    final picked = await FilePickerPlatform.instance.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (picked.isEmpty || !mounted) return;
    if (picked.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose at least two PDFs to combine.')),
      );
      return;
    }
    final ordered = await showFileOrderSheet(
      context,
      files: picked,
      title: 'Combine PDFs',
      explanation: 'Review the reading order before combining.',
      actionLabel: 'Combine ${picked.length} PDFs',
    );
    if (ordered == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final paths = <String>[];
      var n = 0;
      for (final file in ordered) {
        final bytes = await file.readAsBytes();
        n++;
        paths.add(
          await widget.engine.stageFile(
            name: 'combine-$n-${file.name}',
            bytes: bytes,
          ),
        );
      }
      if (!mounted) return;
      await _run('doc_combine', {
        'paths': paths,
        'out': 'outputs/combined.pdf',
      }, refreshStatus: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Combine failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createFromImages() async {
    final picked = await FilePickerPlatform.instance.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'tif', 'tiff', 'gif', 'bmp'],
    );
    if (picked.isEmpty || !mounted) return;
    final ordered = await showFileOrderSheet(
      context,
      files: picked,
      title: 'Photo page order',
      explanation: 'Each image becomes one page. Review the sequence.',
      actionLabel: 'Create ${picked.length}-page PDF',
    );
    if (ordered == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final paths = <String>[];
      for (var index = 0; index < ordered.length; index++) {
        final file = ordered[index];
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) throw StateError('${file.name} is empty');
        paths.add(
          await widget.engine.stageFile(
            name: 'photo-${index + 1}-${file.name}',
            bytes: bytes,
          ),
        );
      }
      if (!mounted) return;
      await _run('doc_create_multiple', {
        'paths': paths,
        'mode': 'combine',
        'out': 'outputs/photos.pdf',
        'open': false,
      }, refreshStatus: false);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create PDF from photos: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _split() async {
    final controller = TextEditingController(text: '1');
    String mode = 'every';
    try {
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Split document'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: mode,
                  decoration: const InputDecoration(
                    labelText: 'Split by',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'every',
                      child: Text('Every N pages'),
                    ),
                    DropdownMenuItem(
                      value: 'max_mb',
                      child: Text('Max file size (MB)'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => mode = v);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: mode == 'every' ? 'Pages per file' : 'Max MB',
                    border: const OutlineInputBorder(),
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
                child: const Text('Split'),
              ),
            ],
          ),
        ),
      );
      if (go != true || !mounted) return;
      final value = double.tryParse(controller.text.trim());
      if (value == null || value <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a positive number')),
        );
        return;
      }
      await _run('doc_split', {
        if (mode == 'every') 'every': value.toInt(),
        if (mode == 'max_mb') 'max_mb': value,
        'out_dir': 'outputs/split',
      }, refreshStatus: false);
    } finally {
      controller.dispose();
    }
  }

  Future<void> _extract() async {
    await widget.onOpenPages?.call();
  }

  Future<void> _labels() async {
    final from = TextEditingController(text: '1');
    final to = TextEditingController(text: '${widget.pageCount}');
    String style = 'decimal';
    final prefix = TextEditingController();
    try {
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Number pages'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: from,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'From',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: to,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'To',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: style,
                  decoration: const InputDecoration(
                    labelText: 'Style',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'decimal', child: Text('1, 2, 3')),
                    DropdownMenuItem(
                      value: 'lower-roman',
                      child: Text('i, ii, iii'),
                    ),
                    DropdownMenuItem(
                      value: 'upper-roman',
                      child: Text('I, II, III'),
                    ),
                    DropdownMenuItem(
                      value: 'lower-alpha',
                      child: Text('a, b, c'),
                    ),
                    DropdownMenuItem(
                      value: 'upper-alpha',
                      child: Text('A, B, C'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => style = v);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: prefix,
                  decoration: const InputDecoration(
                    labelText: 'Prefix (optional)',
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
                child: const Text('Apply'),
              ),
            ],
          ),
        ),
      );
      if (go != true || !mounted) return;
      await _run('page_number', {
        'from': int.tryParse(from.text) ?? 1,
        'to': int.tryParse(to.text) ?? widget.pageCount,
        'style': style,
        if (prefix.text.trim().isNotEmpty) 'prefix': prefix.text.trim(),
      });
    } finally {
      from.dispose();
      to.dispose();
      prefix.dispose();
    }
  }

  Future<void> _marks(String kind) async {
    final text = TextEditingController();
    try {
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            kind == 'header_footer'
                ? 'Header & footer'
                : kind == 'watermark'
                ? 'Watermark'
                : 'Background',
          ),
          content: TextField(
            controller: text,
            decoration: const InputDecoration(
              hintText: 'Text to show on pages',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Apply'),
            ),
          ],
        ),
      );
      if (go != true || text.text.trim().isEmpty || !mounted) return;
      final tool = kind == 'header_footer'
          ? 'doc_header_footer'
          : kind == 'watermark'
          ? 'doc_watermark'
          : 'doc_background';
      await _run(
        tool,
        kind == 'header_footer'
            ? {'footer_center': text.text.trim(), 'start_number': 1}
            : {'text': text.text.trim()},
      );
    } finally {
      text.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Organize pages & files',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (_busy) const LinearProgressIndicator(),
            ListTile(
              leading: const Icon(Icons.merge_outlined),
              title: const Text('Combine PDFs'),
              subtitle: const Text('Pick files to join into one PDF'),
              onTap: _busy ? null : _combine,
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Create PDF from photos'),
              subtitle: const Text(
                'Choose images, confirm page order, then Save As',
              ),
              onTap: _busy ? null : _createFromImages,
            ),
            if (widget.hasDocument)
              ListTile(
                leading: const Icon(Icons.call_split_outlined),
                title: const Text('Split document'),
                subtitle: const Text('Every N pages or by file size'),
                onTap: _busy ? null : _split,
              ),
            if (widget.hasDocument)
              ListTile(
                leading: const Icon(Icons.output_outlined),
                title: const Text('Extract pages'),
                subtitle: const Text('Copy a range into a new PDF'),
                onTap: _busy ? null : _extract,
              ),
            if (widget.hasDocument)
              ListTile(
                leading: const Icon(Icons.format_list_numbered),
                title: const Text('Number pages'),
                subtitle: const Text('Labels like i, ii or A-1'),
                onTap: _busy ? null : _labels,
              ),
            if (widget.hasDocument)
              ListTile(
                leading: const Icon(Icons.vertical_align_bottom_outlined),
                title: const Text('Header & footer'),
                onTap: _busy ? null : () => _marks('header_footer'),
              ),
            if (widget.hasDocument)
              ListTile(
                leading: const Icon(Icons.branding_watermark_outlined),
                title: const Text('Watermark'),
                onTap: _busy ? null : () => _marks('watermark'),
              ),
            if (widget.hasDocument)
              ListTile(
                leading: const Icon(Icons.format_color_fill_outlined),
                title: const Text('Background'),
                onTap: _busy ? null : () => _marks('background'),
              ),
          ],
        ),
      ),
    );
  }
}

String _actionName(String tool) => switch (tool) {
  'doc_combine' => 'Combine PDFs',
  'doc_create_multiple' => 'Create PDF',
  'doc_split' => 'Split PDF',
  'page_extract' => 'Extract pages',
  'page_number' => 'Number pages',
  'doc_header_footer' => 'Add page headers or footers',
  'doc_watermark' => 'Add watermark',
  'doc_background' => 'Add background',
  _ => 'Organize pages',
};
