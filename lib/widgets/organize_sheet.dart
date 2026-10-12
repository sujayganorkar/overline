import 'dart:convert';
import 'dart:typed_data';

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
    this.documentName,
    this.onOpenPages,
    required this.onStatusChanged,
  });

  final PdfEngineApi engine;
  final int handle;
  final int pageCount;
  final bool hasDocument;
  final String? documentName;
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
    bool collectOutputs = false,
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
      // Only file-producing tools are scanned for outputs: mutating tools
      // echo the document's own staging path, which must never be offered
      // as if it were a result.
      if (collectOutputs) {
        await saveToolOutputs(context, widget.engine, [
          for (final c in response.contents) c.json,
        ]);
      }
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
    setState(() => _busy = true);
    try {
      // The open PDF counts as the first input: snapshotting it here means
      // the user never has to re-pick the file they are looking at.
      final blobs = <String, Uint8List>{};
      final items = <FileOrderItem>[];
      final openName = widget.documentName;
      if (widget.hasDocument && openName != null) {
        bridge.SaveSnapshot? snapshot;
        try {
          snapshot = await widget.engine.saveSnapshot(handle: widget.handle);
          blobs['current'] = snapshot.bytes;
        } finally {
          if (snapshot != null) {
            await widget.engine.cancelSave(
              handle: widget.handle,
              token: snapshot.token,
            );
          }
        }
        items.add(
          FileOrderItem(
            key: 'current',
            name: openName,
            detail:
                'Open now · ${formatFileSize(blobs['current']!.length)} · current version with your edits',
          ),
        );
      }
      for (var i = 0; i < picked.length; i++) {
        final file = picked[i];
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) throw StateError('${file.name} is empty');
        final key = 'picked-$i';
        blobs[key] = bytes;
        items.add(
          FileOrderItem(
            key: key,
            name: file.name,
            detail: formatFileSize(await file.length()),
          ),
        );
      }
      if (items.length < 2) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Choose at least one more PDF to combine.'),
          ),
        );
        return;
      }
      if (!mounted) return;
      final ordered = await showFileOrderSheet(
        context,
        files: items,
        title: 'Combine PDFs',
        explanation: widget.hasDocument
            ? 'The open PDF is already first. Review the reading order before combining.'
            : 'Review the reading order before combining.',
        actionLabel: 'Combine ${items.length} PDFs',
      );
      if (ordered == null || !mounted) return;
      final paths = <String>[];
      for (var n = 0; n < ordered.length; n++) {
        final item = ordered[n];
        paths.add(
          await widget.engine.stageFile(
            name: 'combine-${n + 1}-${item.name}',
            bytes: blobs[item.key]!,
          ),
        );
      }
      if (!mounted) return;
      await _run(
        'doc_combine',
        {'paths': paths, 'out': 'outputs/combined.pdf'},
        refreshStatus: false,
        collectOutputs: true,
      );
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
    final photoItems = <FileOrderItem>[];
    for (var i = 0; i < picked.length; i++) {
      photoItems.add(
        FileOrderItem(
          key: 'photo-$i',
          name: picked[i].name,
          detail: formatFileSize(await picked[i].length()),
        ),
      );
    }
    if (!mounted) return;
    final ordered = await showFileOrderSheet(
      context,
      files: photoItems,
      title: 'Photo page order',
      explanation: 'Each image becomes one page. Review the sequence.',
      actionLabel: 'Create ${picked.length}-page PDF',
    );
    if (ordered == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final paths = <String>[];
      for (var index = 0; index < ordered.length; index++) {
        final file = picked[int.parse(ordered[index].key.split('-').last)];
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
      await _run(
        'doc_create_multiple',
        {
          'paths': paths,
          'mode': 'combine',
          'out': 'outputs/photos.pdf',
          'open': false,
        },
        refreshStatus: false,
        collectOutputs: true,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create PDF from photos: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _newBlank() async {
    final controller = TextEditingController(text: '1');
    try {
      final text = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('New blank PDF'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Pages (1–100)',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Create'),
            ),
          ],
        ),
      );
      if (text == null || !mounted) return;
      final pages = int.tryParse(text.trim());
      if (pages == null || pages < 1 || pages > 100) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Enter 1 to 100 pages.')));
        return;
      }
      await _run(
        'doc_create',
        {'from': 'blank', 'pages': pages, 'out': 'outputs/blank.pdf'},
        refreshStatus: false,
        collectOutputs: true,
      );
    } finally {
      controller.dispose();
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
      await _run(
        'doc_split',
        {
          if (mode == 'every') 'every': value.toInt(),
          if (mode == 'max_mb') 'max_mb': value,
          'out_dir': 'outputs/split',
        },
        refreshStatus: false,
        collectOutputs: true,
      );
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

  Future<void> _headerFooter() async {
    final header = TextEditingController();
    final footer = TextEditingController();
    try {
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Header & footer'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: header,
                decoration: const InputDecoration(
                  labelText: 'Header (top, optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: footer,
                decoration: const InputDecoration(
                  labelText: 'Footer (bottom, optional)',
                  hintText: 'Page <<1>>',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tip: <<1>> inserts the page number, <<n>> the page count.',
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
      );
      if (go != true || !mounted) return;
      final headerText = header.text.trim();
      final footerText = footer.text.trim();
      if (headerText.isEmpty && footerText.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a header, a footer, or both.')),
        );
        return;
      }
      await _run('doc_header_footer', {
        if (headerText.isNotEmpty) 'header_center': headerText,
        if (footerText.isNotEmpty) 'footer_center': footerText,
        'start_number': 1,
      });
    } finally {
      header.dispose();
      footer.dispose();
    }
  }

  Future<void> _watermark() async {
    final text = TextEditingController();
    var opacity = 0.5;
    var behind = true;
    try {
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Watermark'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: text,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Text to show on pages',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Faint'),
                    Expanded(
                      child: Slider(
                        value: opacity,
                        min: 0.1,
                        max: 1.0,
                        divisions: 9,
                        label: '${(opacity * 100).round()}%',
                        onChanged: (v) => setDialogState(() => opacity = v),
                      ),
                    ),
                    const Text('Solid'),
                  ],
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Behind page content'),
                  value: behind,
                  onChanged: (v) => setDialogState(() => behind = v ?? true),
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
      if (go != true || text.text.trim().isEmpty || !mounted) return;
      await _run('doc_watermark', {
        'text': text.text.trim(),
        'opacity': (opacity * 100).round() / 100,
        if (behind) 'behind': true,
      });
    } finally {
      text.dispose();
    }
  }

  Future<void> _background() async {
    const presets = {
      'White': '#FFFFFF',
      'Warm paper': '#F5F5F0',
      'Light gray': '#E8E8E8',
      'Soft yellow': '#FFF9C4',
      'Soft blue': '#E3F2FD',
    };
    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in presets.entries)
              ListTile(
                leading: CircleAvatar(backgroundColor: _hexColor(entry.value)),
                title: Text(entry.key),
                onTap: () => Navigator.pop(context, entry.value),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    await _run('doc_background', {'color': choice});
  }

  Future<void> _removeMarks() async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in const [
              (id: 'header_footer', label: 'Headers & footers'),
              (id: 'watermark', label: 'Watermarks'),
              (id: 'background', label: 'Backgrounds'),
            ])
              ListTile(
                title: Text(option.label),
                onTap: () => Navigator.pop(context, option.id),
              ),
          ],
        ),
      ),
    );
    if (kind == null || !mounted) return;
    await _run('doc_remove_marks', {'kind': kind});
  }

  Widget _section(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
    child: Text(label, style: Theme.of(context).textTheme.labelLarge),
  );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Organize pages & files',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 12),
              if (_busy) const LinearProgressIndicator(),
              _section('Create'),
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
              ListTile(
                leading: const Icon(Icons.note_add_outlined),
                title: const Text('New blank PDF'),
                subtitle: const Text('Choose pages, then Save As'),
                onTap: _busy ? null : _newBlank,
              ),
              if (widget.hasDocument) _section('Pages'),
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
                  subtitle: const Text('Choose pages visually, then Save As'),
                  onTap: _busy ? null : _extract,
                ),
              if (widget.hasDocument)
                ListTile(
                  leading: const Icon(Icons.format_list_numbered),
                  title: const Text('Number pages'),
                  subtitle: const Text('Labels like i, ii or A-1'),
                  onTap: _busy ? null : _labels,
                ),
              if (widget.hasDocument) _section('Stamp'),
              if (widget.hasDocument)
                ListTile(
                  leading: const Icon(Icons.vertical_align_bottom_outlined),
                  title: const Text('Header & footer'),
                  subtitle: const Text('Top and bottom text, page numbers'),
                  onTap: _busy ? null : _headerFooter,
                ),
              if (widget.hasDocument)
                ListTile(
                  leading: const Icon(Icons.branding_watermark_outlined),
                  title: const Text('Watermark'),
                  subtitle: const Text('Faded diagonal text'),
                  onTap: _busy ? null : _watermark,
                ),
              if (widget.hasDocument)
                ListTile(
                  leading: const Icon(Icons.format_color_fill_outlined),
                  title: const Text('Background'),
                  subtitle: const Text('Tint every page'),
                  onTap: _busy ? null : _background,
                ),
              if (widget.hasDocument)
                ListTile(
                  leading: const Icon(Icons.layers_clear_outlined),
                  title: const Text('Remove headers, watermarks…'),
                  subtitle: const Text('Clear previously added marks'),
                  onTap: _busy ? null : _removeMarks,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _hexColor(String hex) {
  final clean = hex.replaceFirst('#', '');
  final value = int.tryParse(clean, radix: 16) ?? 0xFFFFFF;
  return Color(0xFF000000 | value);
}

String _actionName(String tool) => switch (tool) {
  'doc_combine' => 'Combine PDFs',
  'doc_create' => 'Create blank PDF',
  'doc_create_multiple' => 'Create PDF',
  'doc_split' => 'Split PDF',
  'page_extract' => 'Extract pages',
  'page_number' => 'Number pages',
  'doc_header_footer' => 'Add page headers or footers',
  'doc_watermark' => 'Add watermark',
  'doc_background' => 'Add background',
  'doc_remove_marks' => 'Remove marks',
  _ => 'Organize pages',
};
