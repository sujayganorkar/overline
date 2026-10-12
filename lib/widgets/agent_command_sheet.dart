import 'package:flutter/material.dart';

/// Lightweight offline task entry. Known requests route to human-reviewed
/// workflows; unsupported requests never become arbitrary engine operations.
class AgentCommandSheet extends StatefulWidget {
  const AgentCommandSheet({super.key});

  @override
  State<AgentCommandSheet> createState() => _AgentCommandSheetState();
}

class _AgentCommandSheetState extends State<AgentCommandSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String request) {
    final text = request.trim();
    if (text.isEmpty) return;
    Navigator.pop(context, routePdfRequest(text));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Ask PdfCraft', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            const Text(
              'Choose a task in your own words. PdfCraft will show the next step before making a change.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              autofocus: false,
              textInputAction: TextInputAction.send,
              onSubmitted: _submit,
              decoration: InputDecoration(
                labelText: 'Describe a PDF task',
                hintText: 'Describe a PDF task…',
                prefixIcon: const Icon(Icons.auto_awesome),
                suffixIcon: IconButton(
                  tooltip: 'Find a workflow',
                  onPressed: () => _submit(_controller.text),
                  icon: const Icon(Icons.arrow_upward),
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Try a reviewed workflow',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _PromptChip(
                  label: 'Highlight every date',
                  onTap: () => _submit('Highlight every date'),
                ),
                _PromptChip(
                  label: 'Redact phone numbers',
                  onTap: () => _submit('Find and redact phone numbers'),
                ),
                _PromptChip(
                  label: 'Compress below 2 MB',
                  onTap: () => _submit('Compress below 2 MB'),
                ),
                _PromptChip(
                  label: 'Compare another PDF',
                  onTap: () => _submit('Compare with another PDF'),
                ),
                _PromptChip(
                  label: 'Review pages to remove',
                  onTap: () => _submit('Review pages to remove'),
                ),
                _PromptChip(
                  label: 'Summarize this PDF',
                  onTap: () => _submit('Summarize this PDF'),
                ),
                _PromptChip(
                  label: 'Make this PDF searchable',
                  onTap: () => _submit('Make this PDF searchable with OCR'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Route supported natural-language starters to safe, reviewable UI flows.
/// Unknown requests become a catalog search query, never an arbitrary action.
String routePdfRequest(String request) {
  final lower = request.toLowerCase();
  if (lower.contains('phone') &&
      (lower.contains('redact') ||
          lower.contains('remove') ||
          lower.contains('find'))) {
    return 'phones';
  }
  if (lower.contains('date') &&
      (lower.contains('highlight') || lower.contains('mark'))) {
    return 'dates';
  }
  if (lower.contains('compress') || lower.contains('smaller')) {
    return 'compress';
  }
  if (lower.contains('merge') || lower.contains('combine')) return 'combine';
  if (lower.contains('ocr') || lower.contains('searchable')) return 'ocr';
  if (lower.contains('word') || lower.contains('convert')) return 'export';
  if (lower.contains('compare') || lower.contains('difference')) {
    return 'compare';
  }
  if (lower.contains('page') &&
      (lower.contains('remove') ||
          lower.contains('delete') ||
          lower.contains('review'))) {
    return 'pages';
  }
  if (lower.contains('form') || lower.contains('address')) return 'forms';
  if (lower.contains('highlight') || lower.contains('underline')) {
    return 'highlight';
  }
  if (lower.contains('redact') ||
      lower.contains('protect') ||
      lower.contains('password')) {
    return 'secure';
  }
  if (lower.contains('sign') || lower.contains('signature')) return 'sign';
  if (lower.contains('summar') || lower.contains('overview')) {
    return 'insights:summary';
  }
  if (RegExp(r'\b(what|who|when|where|which|why|how)\b').hasMatch(lower)) {
    return 'insights:$request';
  }
  return 'unsupported:$request';
}

class _PromptChip extends StatelessWidget {
  const _PromptChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) =>
      ActionChip(label: Text(label), onPressed: onTap);
}
