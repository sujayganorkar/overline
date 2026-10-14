import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';

import 'app_notice.dart';

import 'task_catalog.dart';
import 'task_workspace.dart';

import 'package:share_plus/share_plus.dart';

import '../bridge/api.dart' as bridge;
import '../services/pdf_engine.dart';
import 'output_saver.dart';
import 'result_summary.dart';

/// Export, compare, OCR, compression, and standards: single-file outputs go
/// through the shared output saver; everything else shows its result inline.
class ExportSheet extends StatefulWidget {
  const ExportSheet({
    super.key,
    required this.engine,
    required this.handle,
    required this.page,
    required this.pageCount,
    required this.onStatusChanged,
    this.initialAction,
    this.documentName,
  });

  final PdfEngineApi engine;
  final int handle;
  final int page;
  final int pageCount;
  final ValueChanged<bridge.DocumentStatus> onStatusChanged;
  final String? initialAction;
  final String? documentName;

  @override
  State<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<ExportSheet> {
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    if (widget.initialAction != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startTask();
      });
    }
  }

  Future<void> _verify() async {
    final response = await _run('pdfa_verify', {}, refreshStatus: false);
    if (response == null || !mounted) return;
    await _showReport(
      'PDF/A verification',
      response.contents
          .where((content) => content.json.isNotEmpty)
          .map((content) => humanizeToolResult('PDF/A check', content.json))
          .join('\n'),
    );
  }

  Future<void> _startTask() async {
    if (_busy) return;
    switch (widget.initialAction) {
      case 'compress':
        await _compressToTarget();
      case 'compressionPresets':
        await _compress();
      case 'office':
        await _exportOffice();
      case 'exportImages':
        await _exportImages();
      case 'exportText':
        await _exportSingle('doc_export_text', 'export.txt');
      case 'measurements':
        await _exportMeasurements();
      case 'ocr':
        await _ocr();
      case 'ocrBatch':
        await _ocrBatch();
      case 'compare':
        await _compare();
      case 'verify':
        await _verify();
    }
  }

  String? _progress;

  Future<bridge.OperationResponse?> _run(
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
      if (!mounted) return null;
      if (refreshStatus) widget.onStatusChanged(response.status);
      return response;
    } catch (e) {
      if (!mounted) return null;
      AppNotice.show(
        context,
        AppNotice(
          message: 'Could not complete this PDF task.',
          kind: NoticeKind.error,
          details: '$e',
        ),
      );
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportSingle(String tool, String fileName) async {
    final response = await _run(tool, {'path': 'outputs/$fileName'});
    if (response == null || !mounted) return;
    await saveToolOutputs(context, widget.engine, [
      for (final c in response.contents) c.json,
    ]);
  }

  Future<void> _exportImages() async {
    final choice = await showModalBottomSheet<({String format, bool all})>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('This page as PNG'),
              onTap: () => Navigator.pop(context, (format: 'png', all: false)),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('This page as JPEG'),
              onTap: () => Navigator.pop(context, (format: 'jpeg', all: false)),
            ),
            ListTile(
              leading: const Icon(Icons.collections_outlined),
              title: Text('All ${widget.pageCount} pages as PNG'),
              subtitle: const Text('Each image asks where to save'),
              onTap: () => Navigator.pop(context, (format: 'png', all: true)),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    setState(() {
      _busy = true;
      _progress = 'Rendering page images…';
    });
    try {
      final response = await _run('doc_export_images', {
        'folder': 'outputs/images-${DateTime.now().microsecondsSinceEpoch}',
        'format': choice.format,
        if (!choice.all) 'pages': [widget.page],
      }, refreshStatus: false);
      if (response == null || !mounted) return;
      await saveToolOutputs(context, widget.engine, [
        for (final c in response.contents) c.json,
      ]);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _exportOffice() async {
    final extension = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Microsoft Word (.docx)'),
              onTap: () => Navigator.pop(context, 'docx'),
            ),
            ListTile(
              leading: const Icon(Icons.web_outlined),
              title: const Text('HTML (.html)'),
              onTap: () => Navigator.pop(context, 'html'),
            ),
            ListTile(
              leading: const Icon(Icons.notes_outlined),
              title: const Text('Rich Text (.rtf)'),
              onTap: () => Navigator.pop(context, 'rtf'),
            ),
          ],
        ),
      ),
    );
    if (extension == null || !mounted) return;
    await _exportSingle('doc_export_office', 'converted.$extension');
  }

  Future<void> _showReport(String title, String body) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(child: SelectableText(body)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _ocr() async {
    final status = await _run('ocr_status', {}, refreshStatus: false);
    if (status == null || !mounted) return;
    final rawStatus = status.contents
        .where((content) => content.json.isNotEmpty)
        .map((content) => content.json)
        .firstOrNull;
    final statusData = rawStatus == null ? null : jsonDecode(rawStatus);
    final available =
        statusData is Map<String, dynamic> && statusData['available'] == true;
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recognize text (OCR)'),
        content: Text(
          available
              ? 'Scanned pages will become searchable. Pages that already contain text are skipped.'
              : 'OCR is not ready on this device because its language model is not installed. No document was changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          if (available)
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Recognize'),
            )
          else
            FilledButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Close'),
            ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    final result = await _run('ocr_recognize', {});
    if (result == null || !mounted) return;
    await _showReport(
      'OCR result',
      result.contents
          .where((content) => content.json.isNotEmpty)
          .map((content) => humanizeToolResult('OCR', content.json))
          .join('\n'),
    );
  }

  Future<void> _ocrBatch() async {
    final picked = await FilePickerPlatform.instance.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (picked.isEmpty || !mounted) return;
    final modelStatus = await _run('ocr_status', {}, refreshStatus: false);
    if (modelStatus == null || !mounted) return;
    final statusJson = modelStatus.contents
        .where((content) => content.json.isNotEmpty)
        .map((content) => content.json)
        .firstOrNull;
    final decodedStatus = statusJson == null ? null : jsonDecode(statusJson);
    final available = decodedStatus is Map<String, dynamic>
        ? decodedStatus['available'] == true
        : false;
    if (!available) {
      await _showReport(
        'OCR models are not installed',
        'Batch OCR runs on this device, but its language model is not installed. No files were changed.',
      );
      return;
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Make ${picked.length} PDFs searchable?'),
        content: const Text(
          'Each selected PDF gets a separate searchable copy. Originals stay unchanged, and every result will be offered through Save As.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Start batch OCR'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    setState(() {
      _busy = true;
      _progress = 'Preparing ${picked.length} PDFs…';
    });
    try {
      final paths = <String>[];
      for (var index = 0; index < picked.length; index++) {
        final file = picked[index];
        setState(() => _progress = 'Staging ${index + 1} of ${picked.length}…');
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) throw StateError('${file.name} is empty');
        paths.add(
          await widget.engine.stageFile(
            name: 'batch-ocr-${index + 1}-${file.name}',
            bytes: bytes,
          ),
        );
      }
      if (!mounted) return;
      setState(() => _progress = 'Recognizing text in selected files…');
      final response = await _run('ocr_recognize_files', {
        'paths': paths,
        'folder': 'outputs/ocr-batch-${DateTime.now().microsecondsSinceEpoch}',
        'dpi': 300,
        'language': 'en',
      }, refreshStatus: false);
      if (response == null || !mounted) return;
      final outputs = <String>[];
      final errors = <String>[];
      for (final content in response.contents) {
        if (content.json.isEmpty) continue;
        final result = jsonDecode(content.json);
        final files = result is Map<String, dynamic> ? result['files'] : null;
        if (files is! List) continue;
        for (final item in files) {
          if (item is! Map<String, dynamic>) continue;
          final output = item['output'];
          if (output is String) outputs.add(output);
          final error = item['error'];
          if (error is String) errors.add('${item['path']}: $error');
        }
      }
      if (outputs.isNotEmpty) {
        await saveOutputPaths(context, widget.engine, outputs);
      }
      if (errors.isNotEmpty && mounted) {
        await _showReport('Some files could not be OCRed', errors.join('\n\n'));
      }
    } catch (error) {
      if (mounted) {
        AppNotice.show(
          context,
          AppNotice(
            message: 'Batch OCR failed.',
            kind: NoticeKind.error,
            details: '$error',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _compare() async {
    final picked = await FilePickerPlatform.instance.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      dialogTitle: 'Choose the older PDF version',
    );
    if (picked.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      final file = picked.first;
      final bytes = await file.readAsBytes();
      final staged = await widget.engine.stageFile(
        name: 'compare-${file.name}',
        bytes: bytes,
      );
      if (!mounted) return;
      final result = await _run('doc_compare', {'other': staged});
      if (result == null || !mounted) return;
      await _showReport(
        'Compare result',
        result.contents
            .where((content) => content.json.isNotEmpty)
            .map((content) => humanizeToolResult('Compare', content.json))
            .join('\n'),
      );
      if (!mounted) return;
      final next = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('What next?'),
          content: const Text(
            'The PDF currently open is treated as the newer version. '
            'Save a report PDF, mark the differences as comments in the '
            'open PDF, or stop here.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'done'),
              child: const Text('Done'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'report'),
              child: const Text('Save report'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'mark'),
              child: const Text('Mark differences'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (next == 'report') {
        final response = await _run('doc_compare_report', {
          'other': staged,
          'path': 'outputs/compare-report.pdf',
        }, refreshStatus: false);
        if (response == null || !mounted) return;
        await saveToolOutputs(context, widget.engine, [
          for (final c in response.contents) c.json,
        ]);
      } else if (next == 'mark') {
        final marked = await _run('doc_compare_mark', {'other': staged});
        if (marked != null && mounted) {
          AppNotice.show(
            context,
            const AppNotice(
              message: 'Differences marked as comments. Undo is available.',
              kind: NoticeKind.info,
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      AppNotice.show(
        context,
        AppNotice(
          message: 'Compare failed.',
          kind: NoticeKind.error,
          details: '$e',
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportMeasurements() async {
    final response = await _run('measure_export', {
      'out': 'outputs/measurements.csv',
    }, refreshStatus: false);
    if (response == null || !mounted) return;
    final source = response.contents
        .where((c) => c.json.isNotEmpty)
        .map((c) => c.json)
        .firstOrNull;
    final data = source == null ? null : jsonDecode(source);
    final count = data is Map<String, dynamic> ? data['count'] : null;
    if (count == 0) {
      AppNotice.show(
        context,
        const AppNotice(
          message:
              'No saved measurements yet — measure in Draw & annotate first.',
          kind: NoticeKind.warning,
        ),
      );
      return;
    }
    await saveToolOutputs(context, widget.engine, [
      for (final c in response.contents) c.json,
    ]);
  }

  Future<void> _compress() async {
    final preset = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Compression preset'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'reduce'),
            child: const Text('Reduce file size (150 ppi, high quality)'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'balanced'),
            child: const Text('Balanced (120 ppi JPEG)'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'small'),
            child: const Text('Smallest file (96 ppi JPEG)'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'target'),
            child: const Text('Try to reach a file size…'),
          ),
        ],
      ),
    );
    if (preset == null || !mounted) return;
    if (preset == 'target') {
      await _compressToTarget();
      return;
    }
    final bridge.OperationResponse? response;
    if (preset == 'reduce') {
      response = await _run('doc_reduce', {
        'path': 'outputs/reduced.pdf',
      }, refreshStatus: false);
    } else {
      final (ppi, quality) = preset == 'small' ? (96, 35) : (120, 50);
      response = await _run('doc_optimize', {
        'path': 'outputs/optimized.pdf',
        'color': {
          'downsample': true,
          'ppi': ppi,
          'above_ppi': ppi,
          'compression': 'jpeg',
          'quality': quality,
        },
        'gray': {
          'downsample': true,
          'ppi': ppi,
          'above_ppi': ppi,
          'compression': 'jpeg',
          'quality': quality,
        },
        'discard_thumbnails': true,
        'discard_alternate_images': true,
        'flate_unencoded': true,
      }, refreshStatus: false);
    }
    if (response == null || !mounted) return;
    final raw = response.contents
        .where((c) => c.json.isNotEmpty)
        .map((c) => c.json)
        .firstOrNull;
    final data = raw == null ? null : jsonDecode(raw);
    final written = data is Map<String, dynamic> ? data['written'] : null;
    final before = data is Map<String, dynamic> ? data['bytes_before'] : null;
    final after = data is Map<String, dynamic> ? data['bytes_after'] : null;
    if (written == false ||
        (before is int && after is int && after >= before)) {
      await _showReport(
        'Could not make a smaller copy',
        before is int
            ? 'This PDF is already compact (${_formatFileSize(before)}). Your original is unchanged.'
            : 'The selected preset did not reduce this PDF. Your original is unchanged.',
      );
      return;
    }
    await saveToolOutputs(context, widget.engine, [
      for (final c in response.contents) c.json,
    ]);
    if (mounted && widget.initialAction != null) {
      Navigator.pop(context);
    }
  }

  Future<void> _compressToTarget() async {
    try {
      setState(() {
        _busy = true;
        _progress = 'Reading current document…';
      });
      bridge.SaveSnapshot? snapshot;
      Uint8List original;
      try {
        snapshot = await widget.engine.saveSnapshot(handle: widget.handle);
        original = snapshot.bytes;
      } finally {
        if (snapshot != null) {
          await widget.engine.cancelSave(
            handle: widget.handle,
            token: snapshot.token,
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _progress = null;
      });

      var selectedUnit = 'KB';
      final controller = TextEditingController(text: '200');
      final selection = await showDialog<({double value, String unit})>(
        context: context,
        builder: (dialogCtx) => StatefulBuilder(
          builder: (dialogCtx, setModalState) {
            final presets = [
              (
                label: '< 100 KB',
                value: 100.0,
                unit: 'KB',
                tip: 'Strict portal limit',
              ),
              (
                label: '< 200 KB',
                value: 200.0,
                unit: 'KB',
                tip: 'Gov / Visa portal standard',
              ),
              (
                label: '< 500 KB',
                value: 500.0,
                unit: 'KB',
                tip: 'Job application & resume',
              ),
              (
                label: '< 1 MB',
                value: 1.0,
                unit: 'MB',
                tip: 'Web portal ceiling',
              ),
              (
                label: '< 2 MB',
                value: 2.0,
                unit: 'MB',
                tip: 'Email attachment ceiling',
              ),
            ];
            final currentVal = double.tryParse(controller.text.trim());
            return AlertDialog(
              title: Row(
                children: [
                  Icon(
                    Icons.compress_outlined,
                    color: Theme.of(dialogCtx).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  const Text('Target file size'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(dialogCtx)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.description_outlined,
                            size: 18,
                            color: Theme.of(dialogCtx)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Current size: ${_formatFileSize(original.length)}',
                              style: Theme.of(dialogCtx).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Common portal limits',
                      style: Theme.of(dialogCtx).textTheme.labelMedium
                          ?.copyWith(
                            color: Theme.of(dialogCtx)
                                .colorScheme
                                .onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final preset in presets)
                          ChoiceChip(
                            label: Text(preset.label),
                            selected:
                                selectedUnit == preset.unit &&
                                currentVal != null &&
                                (currentVal - preset.value).abs() < 0.001,
                            onSelected: (selected) {
                              if (selected) {
                                setModalState(() {
                                  selectedUnit = preset.unit;
                                  controller.text =
                                      preset.value.truncateToDouble() ==
                                          preset.value
                                      ? preset.value.toInt().toString()
                                      : preset.value.toString();
                                });
                              }
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Custom target ceiling',
                      style: Theme.of(dialogCtx).textTheme.labelMedium
                          ?.copyWith(
                            color: Theme.of(dialogCtx)
                                .colorScheme
                                .onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: controller,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Max size',
                              hintText: selectedUnit == 'KB'
                                  ? 'e.g. 200'
                                  : 'e.g. 2',
                              border: const OutlineInputBorder(),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                            onChanged: (_) => setModalState(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'KB', label: Text('KB')),
                            ButtonSegment(value: 'MB', label: Text('MB')),
                          ],
                          selected: {selectedUnit},
                          onSelectionChanged: (values) {
                            setModalState(() {
                              final oldUnit = selectedUnit;
                              selectedUnit = values.first;
                              final parsed = double.tryParse(
                                controller.text.trim(),
                              );
                              if (parsed != null && parsed > 0) {
                                if (oldUnit == 'MB' && selectedUnit == 'KB') {
                                  controller.text = (parsed * 1024)
                                      .round()
                                      .toString();
                                } else if (oldUnit == 'KB' &&
                                    selectedUnit == 'MB') {
                                  controller.text = (parsed / 1024)
                                      .toStringAsFixed(2);
                                }
                              }
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'PdfCraft tests multiple downsampling and compression profiles to fit under this limit without unnecessary blur.',
                      style: Theme.of(dialogCtx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(dialogCtx).colorScheme.outline,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.bolt, size: 18),
                  label: const Text('Shrink to limit'),
                  onPressed: () {
                    final val = double.tryParse(controller.text.trim());
                    if (val != null && val > 0) {
                      Navigator.pop(dialogCtx, (
                        value: val,
                        unit: selectedUnit,
                      ));
                    }
                  },
                ),
              ],
            );
          },
        ),
      );
      if (selection == null || !mounted) return;

      final targetValue = selection.value;
      final targetUnit = selection.unit;
      final targetLabel =
          '${targetValue.toStringAsFixed(targetValue.truncateToDouble() == targetValue ? 0 : 1)} $targetUnit';
      final targetBytes = targetUnit == 'KB'
          ? (targetValue * 1024).floor()
          : (targetValue * 1024 * 1024).floor();

      if (targetBytes <= 0 || (targetUnit == 'MB' && targetValue > 10240)) {
        AppNotice.show(
          context,
          const AppNotice(
            message: 'Please enter a valid target size.',
            kind: NoticeKind.warning,
          ),
        );
        return;
      }

      if (original.length <= targetBytes) {
        if (mounted) {
          AppNotice.show(
            context,
            AppNotice(
              message:
                  'This PDF is already ${_formatFileSize(original.length)}, which is below your target ($targetLabel).',
              kind: NoticeKind.info,
            ),
          );
        }
        return;
      }

      setState(() {
        _busy = true;
        _progress = 'Starting optimization for $targetLabel…';
      });

      Uint8List best = original;
      const profiles = [
        (quality: 72, ppi: 180),
        (quality: 58, ppi: 150),
        (quality: 46, ppi: 120),
        (quality: 36, ppi: 96),
        (quality: 26, ppi: 72),
        (quality: 18, ppi: 50),
      ];
      const candidatePath = 'outputs/compressed.pdf';
      for (var index = 0; index < profiles.length; index++) {
        final profile = profiles[index];
        if (!mounted) return;
        setState(() {
          _progress =
              'Trying quality ${profile.quality}, ${profile.ppi} ppi (${index + 1}/${profiles.length})…';
        });
        final response = await _run('doc_optimize', {
          'path': candidatePath,
          'color': {
            'downsample': true,
            'ppi': profile.ppi,
            'above_ppi': profile.ppi,
            'compression': 'jpeg',
            'quality': profile.quality,
          },
          'gray': {
            'downsample': true,
            'ppi': profile.ppi,
            'above_ppi': profile.ppi,
            'compression': 'jpeg',
            'quality': profile.quality,
          },
          'discard_thumbnails': true,
          'discard_alternate_images': true,
          'flate_unencoded': true,
        }, refreshStatus: false);
        if (response == null) return;
        final paths = <String>[
          for (final content in response.contents)
            ...outputPathsIn(content.json),
        ];
        final outputPath = paths.isNotEmpty ? paths.first : candidatePath;
        final candidate = await widget.engine.readOutput(path: outputPath);
        if (candidate.length < best.length) best = candidate;
        if (candidate.length <= targetBytes) {
          best = candidate;
          break;
        }
      }
      if (!mounted) return;
      final reached = best.length <= targetBytes;
      if (best.length >= original.length) {
        await _showReport(
          'Could not make a smaller copy',
          'The tried image settings did not reduce this PDF. Your original is unchanged.',
        );
        return;
      }
      final outcome = await _reviewCompression(
        original: original,
        compressed: best,
        targetLabel: targetLabel,
        targetReached: reached,
      );
      if (outcome == null || !mounted) return;

      if (outcome == 'share') {
        try {
          await SharePlus.instance.share(
            ShareParams(
              files: [
                XFile.fromData(
                  best,
                  mimeType: 'application/pdf',
                  name: 'compressed.pdf',
                ),
              ],
              subject: 'Compressed PDF ($targetLabel)',
              fileNameOverrides: ['compressed.pdf'],
            ),
          );
          if (mounted && widget.initialAction != null) {
            Navigator.pop(context);
          }
        } catch (e) {
          if (mounted) {
            AppNotice.show(
              context,
              AppNotice(
                message: 'Sharing failed.',
                kind: NoticeKind.error,
                details: '$e',
              ),
            );
          }
        }
      } else if (outcome == 'save') {
        final uri = await FilePickerPlatform.instance.saveFile(
          fileName: 'compressed.pdf',
          bytes: best,
          mimeType: 'application/pdf',
          dialogTitle: 'Save compressed PDF',
        );
        if (!mounted || uri == null) return;
        AppNotice.show(
          context,
          AppNotice(
            message: 'Compressed copy saved through Files',
            kind: NoticeKind.success,
          ),
        );
        if (mounted && widget.initialAction != null) {
          Navigator.pop(context);
        }
      }
    } catch (error) {
      if (mounted) {
        AppNotice.show(
          context,
          AppNotice(
            message: 'Target-size compression failed.',
            kind: NoticeKind.error,
            details: '$error',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<String?> _reviewCompression({
    required Uint8List original,
    required Uint8List compressed,
    required String targetLabel,
    required bool targetReached,
  }) async {
    final previewHandle = await widget.engine.open(
      name: 'compression-preview.pdf',
      bytes: compressed,
    );
    try {
      final originalPages = await widget.engine.pageCount(
        handle: widget.handle,
      );
      final compressedPages = await widget.engine.pageCount(
        handle: previewHandle,
      );
      final pageCount = math.min(originalPages, compressedPages);
      if (pageCount == 0) throw StateError('The compressed copy has no pages.');
      var page = 1;
      var viewMode = 'split';
      var splitRatio = 0.5;
      var loading = false;
      var originalPng = await widget.engine.renderPagePng(
        handle: widget.handle,
        page1Based: page,
        dpi: 96,
      );
      var compressedPng = await widget.engine.renderPagePng(
        handle: previewHandle,
        page1Based: page,
        dpi: 96,
      );
      if (!mounted) return null;
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> showPage(int nextPage) async {
              if (loading || nextPage < 1 || nextPage > pageCount) return;
              setDialogState(() => loading = true);
              try {
                final before = await widget.engine.renderPagePng(
                  handle: widget.handle,
                  page1Based: nextPage,
                  dpi: 96,
                );
                final after = await widget.engine.renderPagePng(
                  handle: previewHandle,
                  page1Based: nextPage,
                  dpi: 96,
                );
                if (!dialogContext.mounted) return;
                setDialogState(() {
                  page = nextPage;
                  originalPng = before;
                  compressedPng = after;
                });
              } catch (error) {
                if (dialogContext.mounted) {
                  AppNotice.show(
                    dialogContext,
                    AppNotice(
                      message: 'Could not preview page $nextPage.',
                      kind: NoticeKind.error,
                      details: '$error',
                    ),
                  );
                }
              } finally {
                if (dialogContext.mounted) {
                  setDialogState(() => loading = false);
                }
              }
            }

            final percentSmaller =
                ((original.length - compressed.length) * 100 / original.length)
                    .round();
            return AlertDialog(
              title: Text(
                targetReached ? 'Review compressed copy' : 'Review best result',
              ),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      targetReached
                          ? '${_formatFileSize(compressed.length)} — within $targetLabel.'
                          : '${_formatFileSize(compressed.length)} — still above $targetLabel.',
                    ),
                    Text(
                      'Original ${_formatFileSize(original.length)} · $percentSmaller% smaller',
                      style: Theme.of(dialogContext).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'split',
                          label: Text('Split slider'),
                          icon: Icon(Icons.compare_outlined, size: 16),
                        ),
                        ButtonSegment(
                          value: 'compressed',
                          label: Text('Compressed'),
                        ),
                        ButtonSegment(
                          value: 'original',
                          label: Text('Original'),
                        ),
                      ],
                      selected: {viewMode},
                      onSelectionChanged: (values) =>
                          setDialogState(() => viewMode = values.first),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: MediaQuery.sizeOf(dialogContext).height * 0.34,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: InteractiveViewer(
                              minScale: 1,
                              maxScale: 5,
                              child: viewMode == 'split'
                                  ? LayoutBuilder(
                                      builder: (context, constraints) {
                                        final width = constraints.maxWidth;
                                        final splitX = width * splitRatio;
                                        return Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            // Base: Compressed image
                                            Positioned.fill(
                                              child: Image.memory(
                                                compressedPng,
                                                fit: BoxFit.contain,
                                              ),
                                            ),
                                            // Top: Original clipped to split ratio
                                            Positioned.fill(
                                              child: ClipRect(
                                                clipper:
                                                    _HorizontalSplitClipper(
                                                      splitRatio,
                                                    ),
                                                child: Image.memory(
                                                  originalPng,
                                                  fit: BoxFit.contain,
                                                ),
                                              ),
                                            ),
                                            // Divider line & drag handle
                                            Positioned(
                                              left: splitX - 16,
                                              top: 0,
                                              bottom: 0,
                                              width: 32,
                                              child: GestureDetector(
                                                behavior:
                                                    HitTestBehavior.opaque,
                                                onHorizontalDragUpdate: (details) {
                                                  setDialogState(() {
                                                    splitRatio =
                                                        (splitRatio +
                                                                details
                                                                        .delta
                                                                        .dx /
                                                                    width)
                                                            .clamp(0.05, 0.95);
                                                  });
                                                },
                                                child: Stack(
                                                  alignment: Alignment.center,
                                                  children: [
                                                    Container(
                                                      width: 2.5,
                                                      color: Colors.white,
                                                    ),
                                                    Container(
                                                      width: 28,
                                                      height: 28,
                                                      decoration: BoxDecoration(
                                                        color: Theme.of(
                                                          dialogContext,
                                                        ).colorScheme.primary,
                                                        shape: BoxShape.circle,
                                                        border: Border.all(
                                                          color: Colors.white,
                                                          width: 2,
                                                        ),
                                                        boxShadow: const [
                                                          BoxShadow(
                                                            color:
                                                                Colors.black38,
                                                            blurRadius: 4,
                                                          ),
                                                        ],
                                                      ),
                                                      child: const Icon(
                                                        Icons.code,
                                                        size: 15,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            // Badges
                                            Positioned(
                                              left: 8,
                                              top: 8,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.black54,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: const Text(
                                                  'Original',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            Positioned(
                                              right: 8,
                                              top: 8,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.black54,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: const Text(
                                                  'Compressed',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    )
                                  : Image.memory(
                                      viewMode == 'compressed'
                                          ? compressedPng
                                          : originalPng,
                                      fit: BoxFit.contain,
                                    ),
                            ),
                          ),
                          if (loading)
                            const Center(child: CircularProgressIndicator()),
                        ],
                      ),
                    ),
                    if (viewMode == 'split')
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          children: [
                            Text(
                              'Original',
                              style: Theme.of(dialogContext)
                                  .textTheme
                                  .bodySmall,
                            ),
                            Expanded(
                              child: Slider(
                                value: splitRatio,
                                min: 0.05,
                                max: 0.95,
                                onChanged: (v) =>
                                    setDialogState(() => splitRatio = v),
                              ),
                            ),
                            Text(
                              'Compressed',
                              style: Theme.of(dialogContext)
                                  .textTheme
                                  .bodySmall,
                            ),
                          ],
                        ),
                      ),
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Previous page',
                          onPressed: loading || page <= 1
                              ? null
                              : () => showPage(page - 1),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Expanded(
                          child: Center(
                            child: Text('Page $page of $pageCount'),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Next page',
                          onPressed: loading || page >= pageCount
                              ? null
                              : () => showPage(page + 1),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, null),
                  child: const Text('Keep original'),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(dialogContext, 'share'),
                  icon: const Icon(Icons.share_outlined, size: 16),
                  label: const Text('Share'),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(dialogContext, 'save'),
                  icon: const Icon(Icons.download_outlined, size: 16),
                  label: const Text('Save copy'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      await widget.engine.close(handle: previewHandle, discardChanges: true);
    }
  }

  String _formatFileSize(int bytes) {
    final mb = bytes / (1024 * 1024);
    if (mb >= 1) return '${mb.toStringAsFixed(2)} MB';
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  Widget _section(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
    child: Text(label, style: Theme.of(context).textTheme.labelLarge),
  );

  @override
  Widget build(BuildContext context) {
    if (widget.initialAction != null) {
      final task = pdfTasks.firstWhere(
        (task) => task.id == widget.initialAction,
      );
      return TaskWorkspace(
        title: task.title,
        description: task.description,
        scope:
            '${widget.documentName ?? 'Current PDF'} • ${widget.pageCount} pages',
        busy: _busy,
        onStart: _startTask,
        progress: _progress,
      );
    }

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
                  'Export & more',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 12),
              if (_busy) const LinearProgressIndicator(),
              if (_progress != null) ...[
                const SizedBox(height: 8),
                Text(_progress!, textAlign: TextAlign.center),
                const SizedBox(height: 4),
              ],
              _section('Convert'),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('Export text'),
                onTap: _busy
                    ? null
                    : () => _exportSingle('doc_export_text', 'export.txt'),
              ),
              ListTile(
                leading: const Icon(Icons.table_chart_outlined),
                title: const Text('Convert PDF to Word or another format'),
                subtitle: const Text('Choose Word, HTML, or Rich Text'),
                onTap: _busy ? null : _exportOffice,
              ),
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('Export pages as images'),
                subtitle: const Text('PNG or JPEG, this page or all'),
                onTap: _busy ? null : _exportImages,
              ),
              ListTile(
                leading: const Icon(Icons.straighten_outlined),
                title: const Text('Export measurements'),
                subtitle: const Text('Saved tape readings as a spreadsheet'),
                onTap: _busy ? null : _exportMeasurements,
              ),
              _section('Improve'),
              ListTile(
                leading: const Icon(Icons.document_scanner_outlined),
                title: const Text('Recognize text (OCR)'),
                onTap: _busy ? null : _ocr,
              ),
              ListTile(
                leading: const Icon(Icons.library_add_check_outlined),
                title: const Text('OCR multiple PDFs'),
                subtitle: const Text(
                  'Select files, then save a searchable copy of each',
                ),
                onTap: _busy ? null : _ocrBatch,
              ),
              ListTile(
                leading: const Icon(Icons.compress_outlined),
                title: const Text('Compress'),
                subtitle: const Text('Presets or a target file size'),
                onTap: _busy ? null : _compress,
              ),
              _section('Review'),
              ListTile(
                leading: const Icon(Icons.compare_arrows_outlined),
                title: const Text('Compare with another PDF'),
                subtitle: const Text('Report, or mark differences in place'),
                onTap: _busy ? null : _compare,
              ),
              ListTile(
                leading: const Icon(Icons.verified_outlined),
                title: const Text('Verify PDF/A'),
                onTap: _busy
                    ? null
                    : () async {
                        final response = await _run(
                          'pdfa_verify',
                          {},
                          refreshStatus: false,
                        );
                        if (response == null || !mounted) return;
                        await _showReport(
                          'PDF/A verification',
                          response.contents
                              .where((content) => content.json.isNotEmpty)
                              .map(
                                (content) => humanizeToolResult(
                                  'PDF/A check',
                                  content.json,
                                ),
                              )
                              .join('\n'),
                        );
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Clips content to a horizontal split ratio (from 0.0 to 1.0) for side-by-side comparison.
class _HorizontalSplitClipper extends CustomClipper<Rect> {
  const _HorizontalSplitClipper(this.ratio);

  final double ratio;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, 0, size.width * ratio, size.height);

  @override
  bool shouldReclip(_HorizontalSplitClipper oldClipper) =>
      oldClipper.ratio != ratio;
}
