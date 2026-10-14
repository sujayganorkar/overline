import 'package:flutter/material.dart';

/// User-facing tasks share one vocabulary at home, in search and in the editor.
class PdfTask {
  const PdfTask(
    this.id,
    this.title,
    this.description,
    this.group,
    this.icon, {
    this.needsDocument = true,
  });
  final String id, title, description, group;
  final IconData icon;
  final bool needsDocument;
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
    'Comments',
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
    'Export Word, HTML or Rich Text',
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
    'Ask PdfCraft',
    'Describe a supported document task',
    'Read',
    Icons.auto_awesome_outlined,
  ),
];

class TaskCatalog extends StatefulWidget {
  const TaskCatalog({super.key, required this.onSelected});
  final ValueChanged<PdfTask> onSelected;
  @override
  State<TaskCatalog> createState() => _TaskCatalogState();
}

class _TaskCatalogState extends State<TaskCatalog> {
  String _query = '';
  String _group = 'All';
  @override
  Widget build(BuildContext context) {
    final tasks = pdfTasks
        .where(
          (task) =>
              (_group == 'All' || task.group == _group) &&
              '${task.title} ${task.description} ${task.group}'
                  .toLowerCase()
                  .contains(_query.toLowerCase().trim()),
        )
        .toList();
    return SafeArea(
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
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search tools, e.g. watermark',
                labelText: 'Find a tool',
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                for (final group in [
                  'All',
                  'Read',
                  'Edit',
                  'Pages',
                  'Create',
                  'Export',
                  'Protect',
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(group),
                      selected: _group == group,
                      onSelected: (_) => setState(() => _group = group),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: tasks.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No matching tools. Try “text”, “pages” or another category.',
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: tasks.length,
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      return ListTile(
                        leading: Icon(task.icon),
                        title: Text(task.title),
                        subtitle: Text(task.description),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => widget.onSelected(task),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
