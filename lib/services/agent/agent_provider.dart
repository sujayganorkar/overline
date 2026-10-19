import 'dart:async';
import 'package:flutter/foundation.dart';

/// The step type emitted by an agent during reasoning, planning, or execution.
enum AgentStepType {
  /// Model chain-of-thought token stream or reasoning progress.
  thinking,

  /// Structured tool invocation requested by the model.
  toolCallProposed,

  /// The native Rust engine is actively executing the tool.
  toolExecuting,

  /// Tool execution completed; status and outputs are available.
  toolExecuted,

  /// Final conversational answer or summary returned to the user.
  answer,

  /// A recoverable or terminal error occurred.
  error,
}

/// An individual event emitted on the agent's reactive event stream.
@immutable
class AgentEvent {
  const AgentEvent({
    required this.type,
    this.text,
    this.toolName,
    this.toolArguments,
    this.executionResultJson,
    this.executionResultPng,
    this.isComplete = false,
  });

  final AgentStepType type;
  final String? text;
  final String? toolName;
  final Map<String, dynamic>? toolArguments;
  final String? executionResultJson;
  final Uint8List? executionResultPng;
  final bool isComplete;

  factory AgentEvent.thought(String token) => AgentEvent(
        type: AgentStepType.thinking,
        text: token,
      );

  factory AgentEvent.toolProposal(String tool, Map<String, dynamic> args) =>
      AgentEvent(
        type: AgentStepType.toolCallProposed,
        toolName: tool,
        toolArguments: args,
      );

  factory AgentEvent.toolExecuting(String tool) => AgentEvent(
        type: AgentStepType.toolExecuting,
        toolName: tool,
      );

  factory AgentEvent.toolExecuted({
    required String tool,
    String? resultJson,
    Uint8List? resultPng,
  }) =>
      AgentEvent(
        type: AgentStepType.toolExecuted,
        toolName: tool,
        executionResultJson: resultJson,
        executionResultPng: resultPng,
      );

  factory AgentEvent.answer(String text) => AgentEvent(
        type: AgentStepType.answer,
        text: text,
        isComplete: true,
      );

  factory AgentEvent.error(String message) => AgentEvent(
        type: AgentStepType.error,
        text: message,
        isComplete: true,
      );

  @override
  String toString() =>
      'AgentEvent(type: $type, text: $text, tool: $toolName, complete: $isComplete)';
}

/// Contextual metadata about the active PDF document provided to the model.
@immutable
class DocumentContext {
  const DocumentContext({
    required this.pageCount,
    required this.currentPageIndex,
    this.documentTitle,
    this.extractedTextSnippet,
    this.bookmarks = const [],
  });

  final int pageCount;
  final int currentPageIndex;
  final String? documentTitle;
  final String? extractedTextSnippet;
  final List<String> bookmarks;

  Map<String, dynamic> toJson() => {
        'pageCount': pageCount,
        'currentPageIndex': currentPageIndex,
        'documentTitle': documentTitle ?? 'Untitled Document',
        'extractedTextSnippet': extractedTextSnippet ?? '',
        'bookmarks': bookmarks,
      };

  @override
  String toString() =>
      'DocumentContext(title: $documentTitle, pages: $pageCount, current: $currentPageIndex)';
}

/// Abstract contract implemented by both local on-device SLM and proprietary cloud inference.
abstract interface class AgentProvider {
  /// Unique identifier for this provider (e.g. 'local_slm', 'cloud_gemini_pro').
  String get providerId;

  /// User-facing display title.
  String get displayName;

  /// True if inference runs strictly on-device without network calls.
  bool get isLocal;

  /// True if the provider is currently ready to accept prompts (e.g. weights downloaded or authenticated).
  bool get isReady;

  /// Streams reasoning tokens, tool proposals, and answers for the given user prompt.
  Stream<AgentEvent> runPrompt({
    required String prompt,
    required DocumentContext context,
    required List<Map<String, dynamic>> tools,
  });

  /// Cancels any active inference or network task.
  Future<void> cancel();
}

