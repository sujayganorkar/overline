import 'dart:convert';

import 'package:flutter/material.dart';

import 'app_notice.dart';

import '../bridge/api.dart' as bridge;
import '../services/pdf_engine.dart';
import 'output_saver.dart';

/// Guided multi-step actions. Recipes pause for human review before applying
/// edits and use the same engine tools as the rest of the editor.
class RecipesSheet extends StatefulWidget {
  const RecipesSheet({
    super.key,
    required this.engine,
    required this.handle,
    required this.pageCount,
    required this.onStatusChanged,
    this.initialAction,
  });

  final PdfEngineApi engine;
  final int handle;
  final int pageCount;
  final ValueChanged<bridge.DocumentStatus> onStatusChanged;
  final String? initialAction;

  @override
  State<RecipesSheet> createState() => _RecipesSheetState();
}

class _RecipesSheetState extends State<RecipesSheet> {
  bool _busy = false;
  String? _progress;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.initialAction == 'dates') {
        _highlightDates();
      } else if (widget.initialAction == 'phones') {
        _markPhoneNumbers();
      }
    });
  }

  Future<void> _highlightDates() async {
    setState(() {
      _busy = true;
      _progress = 'Reading page text…';
    });
    try {
      final path =
          'outputs/recipe-dates-${DateTime.now().microsecondsSinceEpoch}.txt';
      final extracted = await widget.engine.executeTool(
        handle: widget.handle,
        tool: 'doc_export_text',
        argumentsJson: jsonEncode({'path': path}),
      );
      final jsonText = extracted.contents
          .where((content) => content.json.isNotEmpty)
          .map((content) => content.json)
          .firstOrNull;
      if (jsonText == null) {
        throw StateError('Text extraction returned no file');
      }
      final paths = outputPathsIn(jsonText);
      if (paths.isEmpty) {
        throw StateError('Text extraction did not return a path');
      }
      final pageTexts = utf8
          .decode(
            await widget.engine.readOutput(path: paths.first),
            allowMalformed: true,
          )
          .split('\f');
      final candidates = _datePattern
          .allMatches(pageTexts.join('\n'))
          .map((match) => match.group(0)!.trim())
          .where((match) => match.isNotEmpty)
          .toList();
      final unique = <String, String>{};
      for (final candidate in candidates) {
        unique.putIfAbsent(candidate.toLowerCase(), () => candidate);
      }
      final values = unique.values.take(30).toList(growable: false);
      if (!mounted) return;
      if (values.isEmpty) {
        setState(() => _progress = null);
        AppNotice.show(
          context,
          const AppNotice(
            message: 'No dates were detected in this PDF.',
            kind: NoticeKind.warning,
          ),
        );
        return;
      }
      final selected = values.toSet();
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Review dates to highlight'),
            content: SizedBox(
              width: 440,
              height: MediaQuery.sizeOf(context).height * 0.52,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${values.length} date-like phrases found. Uncheck anything that is not a date.',
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: values.length,
                      itemBuilder: (context, index) {
                        final value = values[index];
                        final occurrences = pageTexts
                            .where(
                              (page) =>
                                  _normalize(page).contains(_normalize(value)),
                            )
                            .length;
                        return CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(value),
                          subtitle: Text(
                            'Appears on $occurrences page${occurrences == 1 ? '' : 's'}',
                          ),
                          value: selected.contains(value),
                          onChanged: (checked) => setDialogState(() {
                            if (checked == true) {
                              selected.add(value);
                            } else {
                              selected.remove(value);
                            }
                          }),
                        );
                      },
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
                child: Text('Highlight ${selected.length}'),
              ),
            ],
          ),
        ),
      );
      if (approved != true || !mounted) return;
      setState(() {
        _busy = true;
        _progress = 'Placing reviewed highlights…';
      });
      var operations = 0;
      final selectedDates = selected.toList(growable: false);
      for (var dateIndex = 0; dateIndex < selectedDates.length; dateIndex++) {
        final date = selectedDates[dateIndex];
        for (var pageIndex = 0; pageIndex < pageTexts.length; pageIndex++) {
          if (!_normalize(pageTexts[pageIndex]).contains(_normalize(date))) {
            continue;
          }
          if (!mounted) return;
          setState(
            () => _progress =
                'Highlighting date ${dateIndex + 1} of ${selectedDates.length}…',
          );
          final response = await widget.engine.executeTool(
            handle: widget.handle,
            tool: 'comment_add',
            argumentsJson: jsonEncode({
              'page': pageIndex + 1,
              'type': 'highlight',
              'find': date,
              'all': true,
            }),
          );
          widget.onStatusChanged(response.status);
          operations++;
        }
      }
      if (mounted) {
        setState(() => _progress = null);
        AppNotice.show(
          context,
          AppNotice(
            message:
                '$operations page highlight${operations == 1 ? '' : 's'} added. Undo is available.',
            kind: NoticeKind.success,
            action: operations == 0
                ? null
                : NoticeAction(
                    label: 'Undo all',
                    onPressed: () => _undoRecipe(operations),
                  ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        AppNotice.show(
          context,
          AppNotice(
            message: 'Could not highlight dates.',
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

  Future<void> _undoRecipe(int count) async {
    try {
      bridge.DocumentStatus? status;
      var undone = 0;
      while (undone < count) {
        final response = await widget.engine.executeTool(
          handle: widget.handle,
          tool: 'edit_undo',
          argumentsJson: '{}',
        );
        status = response.status;
        undone++;
        if (status.canUndo.isEmpty) break;
      }
      if (status != null) widget.onStatusChanged(status);
      if (mounted) {
        AppNotice.show(
          context,
          AppNotice(
            message: 'Undid $undone highlight changes.',
            kind: NoticeKind.success,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        AppNotice.show(
          context,
          AppNotice(
            message: 'Could not undo highlights.',
            kind: NoticeKind.error,
            details: '$error',
          ),
        );
      }
    }
  }

  Future<void> _markPhoneNumbers() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Find phone numbers'),
        content: const Text(
          'Overline will place reversible redaction marks over phone-number matches. Review the marks on the page; nothing is removed until you choose Apply redactions.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Find & mark'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _progress = 'Finding phone-number matches…';
    });
    try {
      final response = await widget.engine.executeTool(
        handle: widget.handle,
        tool: 'redact_mark',
        argumentsJson: jsonEncode({'pattern': 'phone'}),
      );
      widget.onStatusChanged(response.status);
      if (!mounted) return;
      final source = response.contents
          .where((content) => content.json.isNotEmpty)
          .map((content) => content.json)
          .firstOrNull;
      final decoded = source == null ? null : jsonDecode(source);
      final count = decoded is Map<String, dynamic> ? decoded['marked'] : null;
      setState(() => _progress = null);
      AppNotice.show(
        context,
        AppNotice(
          message:
              'Marked ${count is int ? count : 'matching'} phone number(s). Review before applying.',
          kind: NoticeKind.info,
          action: NoticeAction(
            label: 'Review',
            onPressed: () => Navigator.pop(context, 'reviewPhones'),
          ),
          duration: const Duration(seconds: 8),
        ),
      );
    } catch (error) {
      if (mounted) {
        AppNotice.show(
          context,
          AppNotice(
            message: 'Could not mark phone numbers.',
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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Guided recipes',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Text('Review first. Every edit stays undoable.'),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close recipes',
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_progress != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Text(_progress!, textAlign: TextAlign.center),
              ),
            Expanded(
              child: ListView(
                children: [
                  ListTile(
                    leading: const Icon(Icons.auto_delete_outlined),
                    title: const Text('Review and remove pages'),
                    subtitle: Text(
                      'Inspect ${widget.pageCount} thumbnails, select pages, confirm deletion',
                    ),
                    onTap: _busy ? null : () => Navigator.pop(context, 'pages'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.event_note_outlined),
                    title: const Text('Highlight dates'),
                    subtitle: const Text(
                      'Review detected dates before marking them',
                    ),
                    onTap: _busy ? null : _highlightDates,
                  ),
                  ListTile(
                    leading: const Icon(Icons.phone_disabled_outlined),
                    title: const Text('Find and redact phone numbers'),
                    subtitle: const Text(
                      'Mark first; inspect before permanent removal',
                    ),
                    onTap: _busy ? null : _markPhoneNumbers,
                  ),
                  ListTile(
                    leading: const Icon(Icons.compress_outlined),
                    title: const Text('Reach a target file size'),
                    subtitle: const Text(
                      'Try measured compression levels, then Save As',
                    ),
                    onTap: _busy
                        ? null
                        : () => Navigator.pop(context, 'compress'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.compare_arrows_outlined),
                    title: const Text('Compare two versions'),
                    subtitle: const Text(
                      'Review differences, then optionally mark them',
                    ),
                    onTap: _busy
                        ? null
                        : () => Navigator.pop(context, 'compare'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final _datePattern = RegExp(
  r'(?<!\d)(?:\d{4}[-/.]\d{1,2}[-/.]\d{1,2}|\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4}|(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+\d{1,2},?\s+\d{4}|\d{1,2}\s+(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+\d{4})(?!\d)',
  caseSensitive: false,
);

String _normalize(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
