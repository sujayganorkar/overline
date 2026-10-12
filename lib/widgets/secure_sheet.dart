import 'dart:convert';

import 'package:flutter/material.dart';

import '../bridge/api.dart' as bridge;
import '../services/pdf_engine.dart';

/// Redaction, sanitizing, password protection, and flattening.
class SecureSheet extends StatefulWidget {
  const SecureSheet({
    super.key,
    required this.engine,
    required this.handle,
    required this.onStatusChanged,
  });

  final PdfEngineApi engine;
  final int handle;
  final ValueChanged<bridge.DocumentStatus> onStatusChanged;

  @override
  State<SecureSheet> createState() => _SecureSheetState();
}

class _SecureSheetState extends State<SecureSheet> {
  bool _busy = false;

  Future<void> _run(
    String tool,
    Map<String, Object?> args, {
    bool confirm = false,
    String confirmTitle = '',
    String confirmBody = '',
    bool closeAfterSuccess = false,
  }) async {
    if (confirm) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(confirmTitle),
          content: Text(confirmBody),
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
      if (ok != true || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final response = await widget.engine.executeTool(
        handle: widget.handle,
        tool: tool,
        argumentsJson: jsonEncode(args),
      );
      if (!mounted) return;
      widget.onStatusChanged(response.status);
      final message = switch (tool) {
        'redact_apply' => 'Redactions applied and checked. Review the page, then Save to keep the changes.',
        'redact_mark' => 'Redaction marks added. Review them before applying.',
        'redact_clear' => 'Redaction marks cleared.',
        'doc_protect' => 'Password protection added. Save to keep the change.',
        'doc_unprotect' =>
          'Password protection removed. Save to keep the change.',
        'doc_remove_hidden' =>
          'Hidden information removed. Save to keep the change.',
        'doc_flatten' => 'Fields and comments flattened.',
        _ => 'Change applied.',
      };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      if (closeAfterSuccess && mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not complete that security action: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _redactPhrase() async {
    final controller = TextEditingController();
    try {
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Mark text for redaction'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Phrase to redact',
                  hintText: 'Enter phrase to mark across document',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              const Text('Every match in the document is marked.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Mark'),
            ),
          ],
        ),
      );
      if (go != true || controller.text.trim().isEmpty || !mounted) return;
      await _run('redact_mark', {'find': controller.text.trim()});
    } finally {
      controller.dispose();
    }
  }

  Future<void> _sanitize() async {
    await _run(
      'doc_remove_hidden',
      {},
      confirm: true,
      confirmTitle: 'Remove hidden information?',
      confirmBody:
          'Metadata, attachments, comments, form data, hidden text and layers, '
          'bookmarks, links and scripts are removed. Form fields are flattened '
          'so values stay visible. Undoable until saved.',
    );
  }

  Future<void> _protect() async {
    final open = TextEditingController();
    final owner = TextEditingController();
    try {
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Protect with passwords'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: open,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Open password (to read)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: owner,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Permissions password (to change)',
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
              child: const Text('Protect'),
            ),
          ],
        ),
      );
      if (go != true || !mounted) return;
      if (open.text.isEmpty && owner.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter at least one password')),
        );
        return;
      }
      await _run('doc_protect', {
        if (open.text.isNotEmpty) 'open_password': open.text,
        if (owner.text.isNotEmpty) 'permissions_password': owner.text,
      });
    } finally {
      open.dispose();
      owner.dispose();
    }
  }

  Future<void> _flatten() async {
    var comments = true;
    var fields = true;
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Flatten'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Comments'),
                value: comments,
                onChanged: (v) => setState(() => comments = v ?? true),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Form fields'),
                value: fields,
                onChanged: (v) => setState(() => fields = v ?? true),
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
              child: const Text('Flatten'),
            ),
          ],
        ),
      ),
    );
    if (go != true || !mounted) return;
    await _run(
      'doc_flatten',
      {'comments': comments, 'fields': fields},
      confirm: true,
      confirmTitle: 'Flatten into page content?',
      confirmBody:
          'Flattened comments and fields become permanent page graphics.',
    );
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
                  'Redact & secure',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 12),
              if (_busy) const LinearProgressIndicator(),
              _section('Redact'),
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: const Text('Mark text for redaction'),
                subtitle: const Text('Find a phrase, or drag a box in Draw'),
                onTap: _busy ? null : _redactPhrase,
              ),
              ListTile(
                leading: const Icon(Icons.gavel_outlined),
                title: const Text('Apply redactions'),
                subtitle: const Text('Permanently removes marked content'),
                onTap: _busy
                    ? null
                    : () => _run(
                        'redact_apply',
                        {},
                        confirm: true,
                        confirmTitle: 'Apply redactions?',
                        confirmBody: 'Covered content is removed for good. PdfCraft checks that marked text is no longer readable. Save afterwards to keep the changes.',
                        closeAfterSuccess: true,
                      ),
              ),
              ListTile(
                leading: const Icon(Icons.clear_all),
                title: const Text('Clear redaction marks'),
                subtitle: const Text('Remove marks without applying'),
                onTap: _busy ? null : () => _run('redact_clear', {}),
              ),
              _section('Clean'),
              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined),
                title: const Text('Remove hidden information'),
                subtitle: const Text('Sanitize metadata, scripts, layers…'),
                onTap: _busy ? null : _sanitize,
              ),
              ListTile(
                leading: const Icon(Icons.layers_clear_outlined),
                title: const Text('Flatten comments & fields'),
                subtitle: const Text('Turn edits into permanent content'),
                onTap: _busy ? null : _flatten,
              ),
              _section('Lock'),
              ListTile(
                leading: const Icon(Icons.lock_outlined),
                title: const Text('Protect with passwords'),
                onTap: _busy ? null : _protect,
              ),
              ListTile(
                leading: const Icon(Icons.lock_open_outlined),
                title: const Text('Remove security'),
                onTap: _busy
                    ? null
                    : () => _run(
                        'doc_unprotect',
                        {},
                        confirm: true,
                        confirmTitle: 'Remove security?',
                        confirmBody: 'Password protection is removed. Undoable until saved.',
                      ),
              ),
            ],
          ),
        ),
      ),
    ); // SafeArea
  }
} // _SecureSheetState
