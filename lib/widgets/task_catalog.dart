import 'package:flutter/material.dart';

import '../bridge/api.dart' show OperationInfo;
import 'engine_task_labels.dart';

/// User-facing tasks share one vocabulary at home, in search and in the editor.
class PdfTask {
  const PdfTask(
    this.id,
    this.title,
    this.description,
    this.group,
    this.icon, {
    this.needsDocument = true,
    this.operation,
  });
  final String id, title, description, group;
  final IconData icon;
  final bool needsDocument;
  final OperationInfo? operation;
}

const pdfTasks = <PdfTask>[
  PdfTask(
    'sign',
    'Sign & date',
    'Place a signature, date or checkmark',
    'Edit',
    Icons.draw_outlined,
  ),
  PdfTask(
    'compress',
    'Compress PDF',
    'Choose a target file size in KB or MB',
    'Export',
    Icons.compress,
  ),
  PdfTask(
    'images',
    'Photos to PDF',
    'Choose photos and arrange their order',
    'Create',
    Icons.photo_library_outlined,
    needsDocument: false,
  ),
  PdfTask(
    'combine',
    'Combine PDFs',
    'Choose files and arrange their order',
    'Create',
    Icons.merge_outlined,
    needsDocument: false,
  ),
  PdfTask(
    'forms',
    'Fill form',
    'Complete the document’s form fields',
    'Edit',
    Icons.ballot_outlined,
  ),
  PdfTask(
    'protect',
    'Add password',
    'Control who can open or edit the PDF',
    'Protect',
    Icons.lock_outline,
  ),
  PdfTask(
    'blank',
    'Blank PDF',
    'Create a document with empty pages',
    'Create',
    Icons.note_add_outlined,
    needsDocument: false,
  ),
  PdfTask(
    'find',
    'Find in PDF',
    'Search text and move between matches',
    'Read',
    Icons.search,
  ),
  PdfTask(
    'bookmarks',
    'Bookmarks',
    'Save and revisit sections',
    'Read',
    Icons.bookmark_outline,
  ),
  PdfTask(
    'comments',
    'Notes & comments',
    'Read, reply to and manage notes',
    'Read',
    Icons.comment_outlined,
  ),
  PdfTask(
    'insights',
    'Summary & evidence',
    'Review excerpts with page references',
    'Read',
    Icons.summarize_outlined,
  ),
  PdfTask(
    'links',
    'Links',
    'Inspect, open or remove document links',
    'Read',
    Icons.link,
  ),
  PdfTask(
    'draw',
    'Draw & annotate',
    'Add ink, notes, shapes and measurements',
    'Edit',
    Icons.brush_outlined,
  ),
  PdfTask(
    'selectText',
    'Select & mark text',
    'Select lines to highlight, underline or strike out',
    'Edit',
    Icons.select_all,
  ),
  PdfTask(
    'highlight',
    'Highlight a phrase',
    'Find and review matching text',
    'Edit',
    Icons.highlight_outlined,
  ),
  PdfTask(
    'text',
    'Edit text',
    'Select a paragraph and review its replacement',
    'Edit',
    Icons.edit_outlined,
  ),
  PdfTask(
    'pages',
    'Arrange pages',
    'Reorder, rotate, crop, insert or delete pages',
    'Pages',
    Icons.grid_view_outlined,
  ),
  PdfTask(
    'split',
    'Split PDF',
    'Create smaller PDFs by page count or size',
    'Pages',
    Icons.call_split,
  ),
  PdfTask(
    'extract',
    'Extract pages',
    'Choose pages to save as a separate PDF',
    'Pages',
    Icons.output,
  ),
  PdfTask(
    'labels',
    'Page labels',
    'Set the numbering used to identify pages',
    'Pages',
    Icons.format_list_numbered,
  ),
  PdfTask(
    'headerFooter',
    'Header & footer',
    'Add text and page numbers',
    'Pages',
    Icons.vertical_align_bottom,
  ),
  PdfTask(
    'watermark',
    'Watermark',
    'Add a text watermark across pages',
    'Pages',
    Icons.branding_watermark_outlined,
  ),
  PdfTask(
    'background',
    'Page background',
    'Choose a background color',
    'Pages',
    Icons.format_color_fill,
  ),
  PdfTask(
    'removeMarks',
    'Remove page marks',
    'Remove headers, footers or watermarks',
    'Pages',
    Icons.layers_clear_outlined,
  ),
  PdfTask(
    'compressionPresets',
    'Compression quality',
    'Choose a compression preset instead of a target size',
    'Export',
    Icons.tune,
  ),
  PdfTask(
    'office',
    'Convert PDF',
    'Export Word, PowerPoint, Markdown, HTML or Rich Text',
    'Export',
    Icons.description_outlined,
  ),
  PdfTask(
    'exportImages',
    'Pages to images',
    'Export PNG or JPEG images',
    'Export',
    Icons.image_outlined,
  ),
  PdfTask(
    'exportText',
    'Export text',
    'Save document text as a text file',
    'Export',
    Icons.text_snippet_outlined,
  ),
  PdfTask(
    'measurements',
    'Export measurements',
    'Save measurement readings as a spreadsheet',
    'Export',
    Icons.straighten,
  ),
  PdfTask(
    'ocr',
    'Recognize text',
    'Make scanned text searchable with OCR',
    'Export',
    Icons.document_scanner_outlined,
  ),
  PdfTask(
    'ocrBatch',
    'Recognize text in files',
    'Create searchable copies of selected PDFs',
    'Export',
    Icons.library_add_check_outlined,
  ),
  PdfTask(
    'compare',
    'Compare PDFs',
    'Review differences with another document',
    'Read',
    Icons.compare_arrows,
  ),
  PdfTask(
    'verify',
    'Check PDF/A',
    'Check suitability for archival storage',
    'Export',
    Icons.verified_outlined,
  ),
  PdfTask(
    'redact',
    'Mark private text',
    'Find text to mark for removal; review before applying',
    'Protect',
    Icons.visibility_off_outlined,
  ),
  PdfTask(
    'secure',
    'Review redactions & security',
    'Apply or clear redactions and inspect privacy tools',
    'Protect',
    Icons.shield_outlined,
  ),
  PdfTask(
    'sanitize',
    'Remove hidden information',
    'Choose metadata and hidden content to remove',
    'Protect',
    Icons.cleaning_services_outlined,
  ),
  PdfTask(
    'flatten',
    'Flatten fields & comments',
    'Turn interactive content into page content',
    'Protect',
    Icons.layers_outlined,
  ),
  PdfTask(
    'agent',
    'Ask Overline',
    'Describe a supported document task',
    'Read',
    Icons.auto_awesome_outlined,
  ),
];

class TaskCatalog extends StatefulWidget {
  const TaskCatalog({super.key, required this.onSelected, this.loadOperations});
  final ValueChanged<PdfTask> onSelected;
  final Future<List<OperationInfo>> Function()? loadOperations;
  @override
  State<TaskCatalog> createState() => _TaskCatalogState();
}

class _TaskCatalogState extends State<TaskCatalog> {
  final _search = TextEditingController();
  String _query = '';
  String _group = 'All';
  List<PdfTask> _engineTasks = const [];
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final load = widget.loadOperations;
    if (load == null) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final operations = await load();
      if (!mounted) return;
      final engineTasks = <PdfTask>[];
      for (final op in operations) {
        final label = engineTaskLabels[op.id];
        final group = label?.group ?? 'Other tools';
        engineTasks.add(
          PdfTask(
            op.id,
            label?.title ?? op.title,
            label?.detail ?? op.description.split(RegExp(r'\.\s')).first,
            group,
            _groupIcon(group),
            operation: op,
            needsDocument: op.requiresDocument || op.id == 'printer_papers',
          ),
        );
      }
      engineTasks.sort((a, b) => a.title.compareTo(b.title));
      setState(() {
        _engineTasks = engineTasks;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _chooseCategory(List<String> groups) async {
    FocusScope.of(context).unfocus();
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .8,
      ),
      useSafeArea: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          for (final group in groups)
            ListTile(
              title: Text(group == 'All' ? 'All categories' : group),
              leading: Icon(_groupIcon(group)),
              trailing: group == _group ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, group),
            ),
        ],
      ),
    );
    if (mounted && choice != null) setState(() => _group = choice);
  }

  IconData _groupIcon(String group) => switch (group) {
    'Accessibility' => Icons.accessibility_new,
    'Scan' => Icons.document_scanner_outlined,
    'Files' => Icons.folder_open,
    'Interactive' => Icons.touch_app_outlined,
    'Edit' => Icons.edit_outlined,
    'Forms' => Icons.ballot_outlined,
    'Pages' => Icons.grid_view_outlined,
    'Print' => Icons.print_outlined,
    'Protect' => Icons.shield_outlined,
    'Read' => Icons.menu_book_outlined,
    _ => Icons.tune,
  };
  @override
  Widget build(BuildContext context) {
    final all = [...pdfTasks, ..._engineTasks];
    final groups = [
      'All',
      ...(all.map((task) => task.group).toSet().toList()..sort()),
    ];
    final words = _query.toLowerCase().trim().split(RegExp(r'\s+'));
    final tasks = all.where((task) {
      final keywords =
          '${task.title} ${task.description} ${task.group} ${task.id}'
              .toLowerCase();
      return (_group == 'All' || task.group == _group) &&
          words.every(keywords.contains);
    }).toList();
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'All tools',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        tooltip: 'Close tools',
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _search.clear();
                                setState(() => _query = '');
                              },
                            ),
                      hintText: 'Search tools, e.g. watermark',
                      labelText: 'Find a tool',
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Wrap(
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.filter_list),
                        label: Text(
                          _group == 'All' ? 'All categories' : _group,
                        ),
                        onPressed: () => _chooseCategory(groups),
                      ),
                      Text(
                        '${tasks.length} ${tasks.length == 1 ? 'tool' : 'tools'}',
                      ),
                    ],
                  ),
                ),
                if (_loading) const LinearProgressIndicator(),
                if (_failed)
                  ListTile(
                    title: const Text('Additional tools could not load'),
                    trailing: TextButton(
                      onPressed: _load,
                      child: const Text('Retry'),
                    ),
                  ),
              ],
            ),
          ),
          if (tasks.isEmpty)
            const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No matching tools. Try “text”, “pages” or another category.',
                  ),
                ),
              ),
            )
          else
            SliverList.builder(
              itemCount: tasks.length,
              itemBuilder: (context, index) {
                final task = tasks[index];
                return ListTile(
                  leading: Icon(task.icon),
                  title: Text(task.title),
                  subtitle: Text(
                    task.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => widget.onSelected(task),
                );
              },
            ),
        ],
      ),
    );
  }
}
