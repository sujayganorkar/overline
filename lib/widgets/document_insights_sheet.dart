import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/pdf_engine.dart';

class DocumentInsightsSheet extends StatefulWidget {
  const DocumentInsightsSheet({
    super.key,
    required this.engine,
    required this.handle,
    required this.onJumpToPage,
    this.initialQuestion,
  });

  final PdfEngineApi engine;
  final int handle;
  final ValueChanged<int> onJumpToPage;
  final String? initialQuestion;

  @override
  State<DocumentInsightsSheet> createState() => _DocumentInsightsSheetState();
}

class _DocumentInsightsSheetState extends State<DocumentInsightsSheet> {
  static const _stopWords = {
    'about',
    'after',
    'again',
    'also',
    'and',
    'are',
    'because',
    'been',
    'before',
    'being',
    'between',
    'could',
    'does',
    'from',
    'have',
    'into',
    'more',
    'most',
    'other',
    'should',
    'than',
    'that',
    'their',
    'there',
    'these',
    'they',
    'this',
    'those',
    'through',
    'under',
    'very',
    'what',
    'when',
    'where',
    'which',
    'while',
    'with',
    'would',
    'your',
    'document',
    'please',
    'tell',
  };

  final _question = TextEditingController();
  List<String>? _pages;
  List<_Evidence> _results = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _question.text = widget.initialQuestion ?? '';
    _loadText();
  }

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _loadText() async {
    try {
      final path =
          'outputs/insights-${DateTime.now().microsecondsSinceEpoch}.txt';
      final response = await widget.engine.executeTool(
        handle: widget.handle,
        tool: 'doc_export_text',
        argumentsJson: jsonEncode({'path': path}),
      );
      final result = response.contents
          .where((content) => content.json.isNotEmpty)
          .map((content) => content.json)
          .firstOrNull;
      if (result == null) {
        throw StateError('Text extraction returned no output');
      }
      final decoded = jsonDecode(result);
      final outputPath = decoded is Map<String, dynamic>
          ? decoded['path']
          : null;
      if (outputPath is! String) {
        throw StateError('Text output path is missing');
      }
      final text = utf8.decode(
        await widget.engine.readOutput(path: outputPath),
        allowMalformed: true,
      );
      if (mounted) setState(() => _pages = text.split('\f'));
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_Evidence> _sentences() {
    final pages = _pages ?? const <String>[];
    final evidence = <_Evidence>[];
    for (var pageIndex = 0; pageIndex < pages.length; pageIndex++) {
      final paragraphs = pages[pageIndex]
          .replaceAll(RegExp(r'\s+'), ' ')
          .split(RegExp(r'(?<=[.!?])\s+'));
      for (final sentence in paragraphs) {
        final value = sentence.trim();
        if (value.length < 24) continue;
        evidence.add(_Evidence(page: pageIndex + 1, text: value));
      }
    }
    return evidence;
  }

  void _summarize() {
    final sentences = _sentences();
    if (sentences.isEmpty) {
      setState(() => _results = const []);
      return;
    }
    final frequencies = <String, int>{};
    for (final sentence in sentences) {
      for (final token in _tokens(sentence.text)) {
        if (!_stopWords.contains(token)) {
          frequencies.update(token, (count) => count + 1, ifAbsent: () => 1);
        }
      }
    }
    final scored = [
      for (var i = 0; i < sentences.length; i++)
        (
          index: i,
          sentence: sentences[i],
          score: _summaryScore(sentences[i], i, frequencies),
        ),
    ]..sort((a, b) => b.score.compareTo(a.score));
    final selected = scored.take(5).toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    setState(() => _results = [for (final item in selected) item.sentence]);
  }

  double _summaryScore(
    _Evidence sentence,
    int index,
    Map<String, int> frequencies,
  ) {
    final words = _tokens(sentence.text)
        .where((word) => !_stopWords.contains(word));
    var score = 0.0;
    var count = 0;
    for (final word in words) {
      score += frequencies[word] ?? 0;
      count++;
    }
    final positionBonus = index < 3 ? 1.5 - index * 0.25 : 0.0;
    return (count == 0 ? 0 : score / count) + positionBonus;
  }

  void _answerFromEvidence() {
    final terms = _tokens(_question.text)
        .where((word) => word.length > 2 && !_stopWords.contains(word))
        .toSet();
    if (terms.isEmpty) {
      setState(() => _error = 'Add a few specific words from your question.');
      return;
    }
    final scored = <({int overlap, _Evidence evidence})>[];
    for (final sentence in _sentences()) {
      final sentenceTerms = _tokens(sentence.text).toSet();
      final overlap = terms.intersection(sentenceTerms).length;
      if (overlap > 0) scored.add((overlap: overlap, evidence: sentence));
    }
    scored.sort((a, b) => b.overlap.compareTo(a.overlap));
    setState(() {
      _error = null;
      _results = [for (final item in scored.take(8)) item.evidence];
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.88,
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
                          'Summary & answers',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Text(
                          'Offline extracts with page references; no generated claims.',
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  TextField(
                    controller: _question,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _answerFromEvidence(),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Ask or search for evidence in this PDF',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _loading ? null : _answerFromEvidence,
                          icon: const Icon(Icons.find_in_page_outlined),
                          label: const Text('Find evidence'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _loading ? null : _summarize,
                          icon: const Icon(Icons.summarize_outlined),
                          label: const Text('Summarize'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: _results.isEmpty
                  ? Center(
                      child: Text(
                        _loading
                            ? 'Reading document…'
                            : 'Choose Summary or search for evidence.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final item = _results[index];
                        return Card(
                          child: ListTile(
                            title: Text(item.text),
                            subtitle: Text('Page ${item.page}'),
                            trailing: const Icon(Icons.arrow_forward),
                            onTap: () {
                              widget.onJumpToPage(item.page);
                              Navigator.pop(context);
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

List<String> _tokens(String text) =>
    RegExp(r"[a-z0-9']+")
        .allMatches(text.toLowerCase())
        .map((match) => match.group(0)!)
        .toList();

class _Evidence {
  const _Evidence({required this.page, required this.text});

  final int page;
  final String text;
}
