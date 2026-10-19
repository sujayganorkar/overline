import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';

import '../bridge/api.dart' as bridge;
import '../services/agent/agent_provider.dart';
import '../services/agent/local_slm_provider.dart';
import '../services/agent/schema_exporter.dart';
import '../services/pdf_engine.dart';

/// Interactive AI Agent Command Sheet for Overline.
/// Supports both on-device edge SLM / cloud agent execution with tool proposals
/// and pre-reviewed rapid workflow routing.
class AgentCommandSheet extends StatefulWidget {
  const AgentCommandSheet({
    super.key,
    this.engine,
    this.documentHandle,
    this.documentName,
    this.pageCount,
    this.currentPage,
    this.onOperationCommitted,
    this.agentProvider,
  });

  final PdfEngineApi? engine;
  final int? documentHandle;
  final String? documentName;
  final int? pageCount;
  final int? currentPage;
  final ValueChanged<bridge.DocumentStatus>? onOperationCommitted;
  final AgentProvider? agentProvider;

  @override
  State<AgentCommandSheet> createState() => _AgentCommandSheetState();
}

class _AgentCommandSheetState extends State<AgentCommandSheet> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  StreamSubscription<AgentEvent>? _agentSubscription;
  late final AgentProvider _provider;

  bool _isProcessing = false;
  String _liveThoughts = '';
  AgentEvent? _proposedTool;
  String? _finalAnswer;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _provider = widget.agentProvider ?? LocalSlmProvider();
  }

  @override
  void dispose() {
    _agentSubscription?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _submitWorkflow(String request) {
    final text = request.trim();
    if (text.isEmpty) return;
    _agentSubscription?.cancel();
    Navigator.pop(context, routePdfRequest(text));
  }

  Future<void> _submitAgentPrompt(String prompt) async {
    final text = prompt.trim();
    if (text.isEmpty) return;

    // If engine or documentHandle is absent, fallback to legacy router
    if (widget.engine == null || widget.documentHandle == null) {
      _submitWorkflow(text);
      return;
    }

    setState(() {
      _isProcessing = true;
      _liveThoughts = '';
      _proposedTool = null;
      _finalAnswer = null;
      _errorMessage = null;
    });

    try {
      // 1. Fetch available operations catalog from Rust engine
      final catalog = await widget.engine!.operationCatalog();
      final toolSchemas = SchemaExporter.exportToFunctionDeclarations(catalog);

      final docContext = DocumentContext(
        pageCount: widget.pageCount ?? 1,
        currentPageIndex: widget.currentPage ?? 1,
        documentTitle: widget.documentName,
      );

      // 2. Stream agent events
      _agentSubscription?.cancel();
      _agentSubscription = _provider
          .runPrompt(
            prompt: text,
            context: docContext,
            tools: toolSchemas,
          )
          .listen(
            (event) {
              if (!mounted) return;
              setState(() {
                switch (event.type) {
                  case AgentStepType.thinking:
                    if (event.text != null) {
                      _liveThoughts += '${event.text}\n';
                    }
                  case AgentStepType.toolCallProposed:
                    _proposedTool = event;
                  case AgentStepType.answer:
                    _finalAnswer = event.text;
                  case AgentStepType.error:
                    _errorMessage = event.text;
                  case AgentStepType.toolExecuting:
                  case AgentStepType.toolExecuted:
                    break;
                }
              });
              _scrollToBottom();
            },
            onDone: () {
              if (mounted) setState(() => _isProcessing = false);
            },
            onError: (err) {
              if (mounted) {
                setState(() {
                  _isProcessing = false;
                  _errorMessage = 'Agent error: $err';
                });
              }
            },
          );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorMessage = 'Failed to initialize agent: $e';
        });
      }
    }
  }

  Future<void> _applyProposedTool() async {
    if (_proposedTool == null ||
        widget.engine == null ||
        widget.documentHandle == null) {
      return;
    }

    final tool = _proposedTool!.toolName!;
    final args = _proposedTool!.toolArguments ?? <String, dynamic>{};

    setState(() => _isProcessing = true);
    try {
      final response = await widget.engine!.executeTool(
        handle: widget.documentHandle!,
        tool: tool,
        argumentsJson: jsonEncode(args),
      );

      widget.onOperationCommitted?.call(response.status);

      if (mounted) {
        Navigator.pop(context, 'agent_executed');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorMessage = 'Execution failed: $e';
        });
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final insets = MediaQuery.viewInsetsOf(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + insets.bottom),
        child: SingleChildScrollView(
          controller: _scrollController,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome, color: Colors.blueAccent),
                  const SizedBox(width: 8),
                  Text('Ask Overline', style: theme.textTheme.titleLarge),
                  const Spacer(),
                  if (_isProcessing)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Describe what you want to do with your document. Overline proposes the changes for your approval before modifying the file.',
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _controller,
                autofocus: false,
                enabled: !_isProcessing,
                textInputAction: TextInputAction.send,
                onSubmitted: _submitAgentPrompt,
                decoration: InputDecoration(
                  labelText: 'Describe a PDF task',
                  hintText: 'e.g. Rotate page 1 by 90 degrees…',
                  prefixIcon: const Icon(Icons.edit_note),
                  suffixIcon: IconButton(
                    tooltip: 'Send prompt',
                    onPressed: _isProcessing
                        ? null
                        : () => _submitAgentPrompt(_controller.text),
                    icon: const Icon(Icons.arrow_upward),
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),

              // Live agent thoughts & streaming output
              if (_liveThoughts.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  color: theme.colorScheme.surfaceContainerHighest,
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.psychology, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              'Agent Reasoning',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _liveThoughts.trim(),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              // Proposed Tool Confirmation Card
              if (_proposedTool != null) ...[
                const SizedBox(height: 12),
                Card(
                  color: theme.colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.bolt,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Proposed Action',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tool: ${_proposedTool!.toolName}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_proposedTool!.toolArguments != null &&
                            _proposedTool!.toolArguments!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Arguments: ${jsonEncode(_proposedTool!.toolArguments)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => setState(() => _proposedTool = null),
                              child: const Text('Discard'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: _isProcessing ? null : _applyProposedTool,
                              icon: const Icon(Icons.check),
                              label: const Text('Apply Changes'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              // Final text answer
              if (_finalAnswer != null) ...[
                const SizedBox(height: 12),
                Card(
                  elevation: 0,
                  color: theme.colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Overline Response',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _finalAnswer!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              // Error notification
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              ],

              // Quick reviewed workflows
              const SizedBox(height: 16),
              Text(
                'Try a reviewed workflow',
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _PromptChip(
                    label: 'Highlight every date',
                    onTap: () => _submitWorkflow('Highlight every date'),
                  ),
                  _PromptChip(
                    label: 'Redact phone numbers',
                    onTap: () => _submitWorkflow('Find and redact phone numbers'),
                  ),
                  _PromptChip(
                    label: 'Compress below 2 MB',
                    onTap: () => _submitWorkflow('Compress below 2 MB'),
                  ),
                  _PromptChip(
                    label: 'Compare another PDF',
                    onTap: () => _submitWorkflow('Compare with another PDF'),
                  ),
                  _PromptChip(
                    label: 'Review pages to remove',
                    onTap: () => _submitWorkflow('Review pages to remove'),
                  ),
                  _PromptChip(
                    label: 'Summarize this PDF',
                    onTap: () => _submitWorkflow('Summarize this PDF'),
                  ),
                  _PromptChip(
                    label: 'Make this PDF searchable',
                    onTap: () => _submitWorkflow('Make this PDF searchable with OCR'),
                  ),
                ],
              ),
            ],
          ),
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
