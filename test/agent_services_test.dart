import 'package:flutter_test/flutter_test.dart';
import 'package:overline/bridge/api.dart' as bridge;
import 'package:overline/services/agent/agent_provider.dart';
import 'package:overline/services/agent/local_slm_provider.dart';
import 'package:overline/services/agent/schema_exporter.dart';

void main() {
  group('SchemaExporter', () {
    test('exports bridge OperationInfo into valid LLM function declaration', () {
      const sampleSchema = '''
      {
        "type": "object",
        "properties": {
          "degrees": {"type": "integer", "enum": [90, 180, 270]},
          "page_range": {"type": "string"}
        },
        "required": ["degrees"]
      }
      ''';

      const op = bridge.OperationInfo(
        id: 'page_rotate',
        title: 'Rotate Pages',
        description: 'Rotates designated pages by 90, 180, or 270 degrees clockwise.',
        inputSchemaJson: sampleSchema,
        readOnly: false,
        destructive: false,
        commandId: 'rotate',
        requiresDocument: true,
      );

      final exported = SchemaExporter.exportToFunctionDeclarations([op]);
      expect(exported.length, 1);

      final decl = exported.first;
      expect(decl['name'], 'page_rotate');
      expect(decl['description'], contains('Rotate Pages: Rotates designated pages'));
      expect(decl['readOnly'], isFalse);
      expect(decl['destructive'], isFalse);

      final params = decl['parameters'] as Map<String, dynamic>;
      expect(params['type'], 'object');
      expect(params['properties'], isA<Map<String, dynamic>>());
      expect((params['properties'] as Map<String, dynamic>).containsKey('degrees'), isTrue);
      expect(params['required'], contains('degrees'));
    });

    test('handles empty or malformed schema gracefully', () {
      const op = bridge.OperationInfo(
        id: 'doc_info',
        title: 'Document Info',
        description: 'Read-only document metadata.',
        inputSchemaJson: 'INVALID_JSON',
        readOnly: true,
        destructive: false,
        commandId: 'info',
        requiresDocument: true,
      );

      final exported = SchemaExporter.exportToFunctionDeclarations([op]);
      expect(exported.length, 1);
      final decl = exported.first;
      expect(decl['name'], 'doc_info');
      expect(decl['readOnly'], isTrue);
      final params = decl['parameters'] as Map<String, dynamic>;
      expect(params['type'], 'object');
      expect((params['properties'] as Map<String, dynamic>).isEmpty, isTrue);
    });
  });

  group('DocumentContext & AgentEvent', () {
    test('serializes DocumentContext to JSON', () {
      const ctx = DocumentContext(
        pageCount: 5,
        currentPageIndex: 2,
        documentTitle: 'Quarterly Report.pdf',
        extractedTextSnippet: 'Financial highlights for Q3...',
        bookmarks: ['Overview', 'Balance Sheet'],
      );

      final json = ctx.toJson();
      expect(json['pageCount'], 5);
      expect(json['currentPageIndex'], 2);
      expect(json['documentTitle'], 'Quarterly Report.pdf');
      expect(json['extractedTextSnippet'], contains('Financial highlights'));
      expect((json['bookmarks'] as List).length, 2);
    });

    test('creates AgentEvent instances through factory constructors', () {
      final thought = AgentEvent.thought('Processing intent');
      expect(thought.type, AgentStepType.thinking);
      expect(thought.text, 'Processing intent');
      expect(thought.isComplete, isFalse);

      final toolProposal = AgentEvent.toolProposal(
        'page_rotate',
        {'degrees': 90, 'page_range': '1'},
      );
      expect(toolProposal.type, AgentStepType.toolCallProposed);
      expect(toolProposal.toolName, 'page_rotate');
      expect(toolProposal.toolArguments?['degrees'], 90);

      final answer = AgentEvent.answer('Operation completed.');
      expect(answer.type, AgentStepType.answer);
      expect(answer.text, 'Operation completed.');
      expect(answer.isComplete, isTrue);

      final error = AgentEvent.error('Failed to parse arguments.');
      expect(error.type, AgentStepType.error);
      expect(error.text, 'Failed to parse arguments.');
      expect(error.isComplete, isTrue);
    });
  });

  group('LocalSlmProvider', () {
    test('resolves rotation request with accurate parameters via heuristic engine', () async {
      final provider = LocalSlmProvider();
      const ctx = DocumentContext(pageCount: 10, currentPageIndex: 3);

      final events = await provider.runPrompt(
        prompt: 'Rotate page 3 by 90 degrees',
        context: ctx,
        tools: [],
      ).toList();

      final toolEvents = events.where((e) => e.type == AgentStepType.toolCallProposed).toList();
      expect(toolEvents.isNotEmpty, isTrue);

      final proposal = toolEvents.first;
      expect(proposal.toolName, 'page_rotate');
      expect(proposal.toolArguments?['degrees'], 90);
      expect(proposal.toolArguments?['page_range'], '3');
    });

    test('resolves delete page request with accurate parameters', () async {
      final provider = LocalSlmProvider();
      const ctx = DocumentContext(pageCount: 10, currentPageIndex: 4);

      final events = await provider.runPrompt(
        prompt: 'Remove page 5 from this document',
        context: ctx,
        tools: [],
      ).toList();

      final toolEvents = events.where((e) => e.type == AgentStepType.toolCallProposed).toList();
      expect(toolEvents.isNotEmpty, isTrue);

      final proposal = toolEvents.first;
      expect(proposal.toolName, 'page_delete');
      expect(proposal.toolArguments?['pages'], '5');
    });

    test('resolves optimization / compression request', () async {
      final provider = LocalSlmProvider();
      const ctx = DocumentContext(pageCount: 5, currentPageIndex: 1);

      final events = await provider.runPrompt(
        prompt: 'Compress and reduce size of this PDF',
        context: ctx,
        tools: [],
      ).toList();

      final toolEvents = events.where((e) => e.type == AgentStepType.toolCallProposed).toList();
      expect(toolEvents.isNotEmpty, isTrue);

      final proposal = toolEvents.first;
      expect(proposal.toolName, 'doc_optimize');
    });

    test('answers page count inquiry without modifying document', () async {
      final provider = LocalSlmProvider();
      const ctx = DocumentContext(pageCount: 14, currentPageIndex: 1);

      final events = await provider.runPrompt(
        prompt: 'How many pages does this document have?',
        context: ctx,
        tools: [],
      ).toList();

      final answerEvents = events.where((e) => e.type == AgentStepType.answer).toList();
      expect(answerEvents.isNotEmpty, isTrue);
      expect(answerEvents.first.text, contains('14 pages'));
    });
  });
}

