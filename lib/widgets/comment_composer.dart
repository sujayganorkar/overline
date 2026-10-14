import 'package:flutter/material.dart';

/// A draft is only dismissed after the document accepts it. Retry preserves text.
class CommentComposer extends StatefulWidget {
  const CommentComposer({
    super.key,
    required this.title,
    required this.page,
    required this.submitLabel,
    required this.onSubmit,
    this.initialText = '',
    this.contextText,
  });
  final String title, submitLabel, initialText;
  final String? contextText;
  final int page;
  final Future<void> Function(String text) onSubmit;

  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required int page,
    required String submitLabel,
    required Future<void> Function(String text) onSubmit,
    String initialText = '',
    String? contextText,
  }) => showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => CommentComposer(
      title: title,
      page: page,
      submitLabel: submitLabel,
      onSubmit: onSubmit,
      initialText: initialText,
      contextText: contextText,
    ),
  );

  @override
  State<CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends State<CommentComposer> {
  late final _text = TextEditingController(text: widget.initialText);
  bool _saving = false;
  bool _discardPrompt = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_saving || _discardPrompt) return;
    if (_text.text != widget.initialText) {
      _discardPrompt = true;
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard this draft?'),
          content: const Text('Your text has not been added to the PDF.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep writing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard draft'),
            ),
          ],
        ),
      );
      _discardPrompt = false;
      if (discard != true) return;
    }
    if (mounted) Navigator.pop(context, false);
  }

  Future<void> _submit() async {
    if (_saving || _text.text.trim().isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_text.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not save this text. Your draft is still here. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _close();
    },
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close draft',
                    onPressed: _saving ? null : _close,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Text(
                'Page ${widget.page}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              if (widget.contextText?.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    widget.contextText!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _text,
                autofocus: true,
                enabled: !_saving,
                minLines: 3,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Your text',
                  hintText: 'Write here…',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving || _text.text.trim().isEmpty
                    ? null
                    : _submit,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(widget.submitLabel),
              ),
              const SizedBox(height: 8),
              Text(
                'Save the PDF when you finish to keep your changes.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
