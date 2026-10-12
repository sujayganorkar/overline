import 'package:flutter/material.dart';

/// Collect a typed signature, then let the person place it directly on the PDF.
class SignatureSheet extends StatefulWidget {
  const SignatureSheet({super.key});

  @override
  State<SignatureSheet> createState() => _SignatureSheetState();
}

class _SignatureSheetState extends State<SignatureSheet> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _continue() {
    final value = _name.text.trim();
    if (value.isEmpty) return;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Type your signature',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          const Text('Next, tap the page to preview where it will go.'),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _continue(),
            decoration: const InputDecoration(
              labelText: 'Name to sign with',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _continue,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Choose placement'),
          ),
        ],
      ),
    ),
  );
}
