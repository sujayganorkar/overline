import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../app_diagnostics.dart';
import 'agent_provider.dart';

/// Cloud-managed AgentProvider that streams high-reasoning Gemini 1.5 Pro / Flash
/// inference from the private Overline backend gateway via Server-Sent Events (SSE).
class CloudAgentProvider implements AgentProvider {
  CloudAgentProvider({
    required this.backendUrl,
    required this.getAuthToken,
    this.isSubscriber = true,
  });

  final String backendUrl;
  final Future<String?> Function() getAuthToken;
  final bool isSubscriber;

  http.Client? _activeClient;

  @override
  String get providerId => 'cloud_gemini_pro';

  @override
  String get displayName => 'Overline Cloud Intelligence (Gemini 1.5 Pro)';

  @override
  bool get isLocal => false;

  @override
  bool get isReady => isSubscriber;

  @override
  Stream<AgentEvent> runPrompt({
    required String prompt,
    required DocumentContext context,
    required List<Map<String, dynamic>> tools,
  }) async* {
    final token = await getAuthToken();
    if (token == null || token.isEmpty) {
      yield AgentEvent.error('Authentication required for cloud inference. Please sign in or use On-Device Edge SLM.');
      return;
    }

    yield AgentEvent.thought('Connecting to Overline Cloud Intelligence…');

    _activeClient = http.Client();
    final request = http.Request('POST', Uri.parse('$backendUrl/v1/agent/chat'));
    request.headers['Authorization'] = 'Bearer $token';
    request.headers['Content-Type'] = 'application/json';
    request.headers['Accept'] = 'text/event-stream';

    request.body = jsonEncode({
      'prompt': prompt,
      'document_context': context.toJson(),
      'tools': tools,
    });

    http.StreamedResponse response;
    try {
      response = await _activeClient!.send(request);
    } catch (e) {
      yield AgentEvent.error('Failed to reach cloud gateway: $e. You can continue using On-Device Edge SLM.');
      return;
    }

    if (response.statusCode == 401) {
      yield AgentEvent.error('Your session has expired or cloud subscription is required.');
      return;
    }

    if (response.statusCode == 429) {
      yield AgentEvent.error('Monthly cloud token quota exceeded. Please switch to On-Device Edge SLM until next month.');
      return;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      yield AgentEvent.error('Cloud inference returned HTTP ${response.statusCode}.');
      return;
    }

    // Process SSE Stream
    final lines = response.stream.transform(utf8.decoder).transform(const LineSplitter());
    final answerBuffer = StringBuffer();

    try {
      await for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith(':')) {
          // Keep-alive or comment
          continue;
        }

        if (trimmed.startsWith('data:')) {
          final jsonStr = trimmed.substring('data:'.length).trim();
          try {
            final payload = jsonDecode(jsonStr) as Map<String, dynamic>;
            final type = payload['type'] as String?;

            if (type == 'thought') {
              final text = payload['text'] as String?;
              if (text != null) {
                answerBuffer.write(text);
                yield AgentEvent.thought(text);
              }
            } else if (type == 'tool_call') {
              final tool = payload['tool'] as String;
              final args = payload['arguments'] as Map<String, dynamic>? ?? <String, dynamic>{};
              yield AgentEvent.toolProposal(tool, args);
            } else if (type == 'done') {
              final tokens = payload['tokens_consumed'];
              AppDiagnostics.instance.record(
                category: 'cloud_agent',
                message: 'Cloud inference finished. Tokens consumed: $tokens',
              );
              break;
            }
          } catch (e) {
            debugPrint('Failed to parse SSE line: $jsonStr, err: $e');
          }
        }
      }

      final text = answerBuffer.toString().trim();
      if (text.isNotEmpty) {
        yield AgentEvent.answer(text);
      }
    } catch (e) {
      yield AgentEvent.error('Inference stream interrupted: $e');
    } finally {
      _activeClient?.close();
      _activeClient = null;
    }
  }

  @override
  Future<void> cancel() async {
    _activeClient?.close();
    _activeClient = null;
  }
}

