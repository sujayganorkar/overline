// Short labels describe the action in the phone's tool picker. The engine
// supplies the schema, availability and document requirements at run time.
typedef EngineTaskLabel = ({String group, String title, String detail});

const engineTaskLabels = <String, EngineTaskLabel>{
  'text_replace': (
    group: 'Edit',
    title: 'Find and replace',
    detail: 'Replace matching text while keeping its formatting',
  ),
  'page_enhance_scan': (
    group: 'Scan',
    title: 'Clean up a scan',
    detail: 'Brighten the paper, reduce shadows and improve contrast',
  ),
  'ocr_words': (
    group: 'Scan',
    title: 'Review recognized words',
    detail: 'Check OCR against the page and correct words before applying',
  ),
  'ocr_review_apply': (
    group: 'Scan',
    title: 'Correct scanned text',
    detail: 'Review and apply corrections to recognized words',
  ),
  'doc_audit_redactions': (
    group: 'Protect',
    title: 'Audit redactions',
    detail: 'Find readable text under covers and marks still awaiting removal',
  ),
  'accessibility_autotag_apply': (
    group: 'Accessibility',
    title: 'Tag for screen readers',
    detail: 'Preview headings and paragraphs, then tag the document',
  ),
  'accessibility_autotag_preview': (
    group: 'Accessibility',
    title: 'Preview reading structure',
    detail: 'Inspect proposed headings and paragraphs page by page',
  ),
  'accessibility_autotag_form_fields': (
    group: 'Accessibility',
    title: 'Tag form fields',
    detail: 'Add structure to form controls for assistive readers',
  ),
  'accessibility_find_untagged': (
    group: 'Accessibility',
    title: 'Find untagged content',
    detail: 'Locate page objects missing from the reading structure',
  ),
  'accessibility_layout_table_to_blocks': (
    group: 'Accessibility',
    title: 'Convert a layout table',
    detail: 'Represent its contents as text blocks',
  ),
  'accessibility_mark_tag_artifact': (
    group: 'Accessibility',
    title: 'Mark decorative content',
    detail: 'Exclude decorative objects from the reading order',
  ),
  'accessibility_move_tag': (
    group: 'Accessibility',
    title: 'Move a structure tag',
    detail: 'Change an item’s position in the reading order',
  ),
  'accessibility_review_html': (
    group: 'Accessibility',
    title: 'Export review as HTML',
    detail: 'Compare accessibility findings across two PDFs',
  ),
  'accessibility_review_record': (
    group: 'Accessibility',
    title: 'Export review as JSON',
    detail: 'Save a machine-readable comparison of two PDFs',
  ),
  'accessibility_review_load': (
    group: 'Accessibility',
    title: 'Open review decisions',
    detail: 'Load the accessibility review file for this PDF',
  ),
  'accessibility_review_save': (
    group: 'Accessibility',
    title: 'Save review decisions',
    detail: 'Record rule decisions and notes for this PDF',
  ),
  'accessibility_set_tag_property': (
    group: 'Accessibility',
    title: 'Edit a structure tag',
    detail: 'Change a tag’s role, language or description',
  ),
  'accessibility_tag_content': (
    group: 'Accessibility',
    title: 'Inspect tagged content',
    detail: 'See which document content belongs to a tag',
  ),
  'accessibility_tags': (
    group: 'Accessibility',
    title: 'Inspect reading structure',
    detail: 'Browse the document’s structure tags',
  ),
  'attachment_add': (
    group: 'Files',
    title: 'Attach a file',
    detail: 'Embed a file from Android Files in this PDF',
  ),
  'attachment_delete': (
    group: 'Files',
    title: 'Remove an attachment',
    detail: 'Remove an embedded file from this PDF',
  ),
  'attachment_edit': (
    group: 'Files',
    title: 'Describe an attachment',
    detail: 'Change an embedded file’s description',
  ),
  'bookmark_copy': (
    group: 'Read',
    title: 'Copy bookmarks from a PDF',
    detail: 'Bring a bookmark tree across from another document',
  ),
  'bookmark_export': (
    group: 'Read',
    title: 'Export bookmarks',
    detail: 'Save the document outline as a separate file',
  ),
  'bookmark_import': (
    group: 'Read',
    title: 'Import bookmarks',
    detail: 'Load an outline from a bookmark file',
  ),
  'bookmark_from_text_styles': (
    group: 'Read',
    title: 'Bookmarks from text styles',
    detail: 'Build an outline from the fonts and sizes used for headings',
  ),
  'bookmark_set_style': (
    group: 'Read',
    title: 'Style a bookmark',
    detail: 'Change its color, bold or italic style',
  ),
  'comment_popup': (
    group: 'Edit',
    title: 'Edit a comment pop-up',
    detail: 'Move, open or close a comment’s pop-up',
  ),
  'comments_copy': (
    group: 'Edit',
    title: 'Copy comments',
    detail: 'Select comments to copy to another page',
  ),
  'comments_paste': (
    group: 'Edit',
    title: 'Paste comments',
    detail: 'Place copied comments on a page',
  ),
  'content_copy': (
    group: 'Edit',
    title: 'Copy added content',
    detail: 'Copy placed content to another position',
  ),
  'doc_backdrops': (
    group: 'Pages',
    title: 'Inspect page backdrops',
    detail: 'List backgrounds and watermarks on your pages',
  ),
  'doc_batch': (
    group: 'Files',
    title: 'Process multiple files',
    detail: 'Convert, recognize text or compress selected files',
  ),
  'doc_bates_multi': (
    group: 'Files',
    title: 'Number pages across files',
    detail: 'Apply continuous Bates numbering to several PDFs',
  ),
  'doc_convert_colours': (
    group: 'Print',
    title: 'Convert document colors',
    detail: 'Convert colors for output or printing',
  ),
  'doc_fix_hairlines': (
    group: 'Print',
    title: 'Thicken fine lines',
    detail: 'Make fine strokes easier to see in print',
  ),
  'doc_printer_marks': (
    group: 'Print',
    title: 'Add printer marks',
    detail: 'Add production marks to selected pages',
  ),
  'doc_rename': (
    group: 'Files',
    title: 'Rename working PDF',
    detail: 'Change the name of this working copy',
  ),
  'form_add_field_table': (
    group: 'Forms',
    title: 'Add a grid of fields',
    detail: 'Create rows and columns of text fields',
  ),
  'form_calculation_order': (
    group: 'Forms',
    title: 'Set field calculation order',
    detail: 'Inspect or change the order of calculated fields',
  ),
  'form_focus': (
    group: 'Forms',
    title: 'Focus a form field',
    detail: 'Trigger a field’s focus or blur action',
  ),
  'image_hit': (
    group: 'Edit',
    title: 'Inspect page artwork',
    detail: 'Identify the artwork at a position on a page',
  ),
  'js_advance': (
    group: 'Interactive',
    title: 'Advance animation time',
    detail: 'Run the document’s scheduled timer actions',
  ),
  'js_event': (
    group: 'Interactive',
    title: 'Run a field interaction',
    detail: 'Run the action for a pointer or focus event',
  ),
  'js_page': (
    group: 'Interactive',
    title: 'Run page actions',
    detail: 'Play the actions for opening or closing a page',
  ),
  'layer_set': (
    group: 'Read',
    title: 'Show or hide a layer',
    detail: 'Change which optional content is visible',
  ),
  'link_open': (
    group: 'Read',
    title: 'Open a linked PDF',
    detail: 'Follow a local link to a second document',
  ),
  'link_run_javascript': (
    group: 'Interactive',
    title: 'Run a link action',
    detail: 'Run the document script attached to a link',
  ),
  'model_add': (
    group: 'Interactive',
    title: 'Insert a 3D model',
    detail: 'Place a U3D or PRC model on a page',
  ),
  'model_render': (
    group: 'Interactive',
    title: 'Preview a 3D model',
    detail: 'Render an embedded PRC model from a chosen angle',
  ),
  'object_copy': (
    group: 'Edit',
    title: 'Copy or cut objects',
    detail: 'Select page objects to reuse together',
  ),
  'object_paste': (
    group: 'Edit',
    title: 'Paste objects',
    detail: 'Place copied objects on a page',
  ),
  'ocr_dictionary': (
    group: 'Scan',
    title: 'Edit the OCR dictionary',
    detail: 'Add or remove words used during OCR review',
  ),
  'page_reverse': (
    group: 'Pages',
    title: 'Reverse pages',
    detail: 'Reverse the document or a selection of pages',
  ),
  'page_template_set_hidden': (
    group: 'Pages',
    title: 'Show or hide a template',
    detail: 'Set whether a page template appears in the document',
  ),
  'page_template_spawn': (
    group: 'Pages',
    title: 'Insert from a template',
    detail: 'Add a page from a template inside the PDF',
  ),
  'page_templates': (
    group: 'Pages',
    title: 'Browse page templates',
    detail: 'List templates embedded in this document',
  ),
  'page_transition_set': (
    group: 'Interactive',
    title: 'Set page transitions',
    detail: 'Choose how pages transition during a presentation',
  ),
  'print_color_profiles': (
    group: 'Print',
    title: 'Browse color profiles',
    detail: 'Inspect ICC profiles for print output',
  ),
  'print_readiness': (
    group: 'Print',
    title: 'Check print readiness',
    detail: 'Review document properties that affect printing',
  ),
  'printer_papers': (
    group: 'Print',
    title: 'Choose printer and paper',
    detail: 'View the available paper sizes in Android print preview',
  ),
  'standards_remove_id': (
    group: 'Protect',
    title: 'Remove a standards claim',
    detail: 'Remove PDF/A or PDF/X identification from the document',
  ),
  'text_edit_layout': (
    group: 'Edit',
    title: 'Measure a text draft',
    detail: 'Preview the layout of edited text',
  ),
  'text_font_files': (
    group: 'Edit',
    title: 'Find font files',
    detail: 'Inspect fonts available to the PDF workspace',
  ),
  'text_font_import': (
    group: 'Edit',
    title: 'Import a font',
    detail: 'Choose a font file for document editing',
  ),
  'text_fonts': (
    group: 'Edit',
    title: 'Browse document fonts',
    detail: 'List the fonts available in this PDF',
  ),
  'text_prepare': (
    group: 'Edit',
    title: 'Group text for editing',
    detail: 'Prepare lines and paragraphs on selected pages',
  ),
  'text_script': (
    group: 'Edit',
    title: 'Superscript or subscript',
    detail: 'Raise or lower selected text',
  ),
  'text_styles': (
    group: 'Edit',
    title: 'Inspect text styles',
    detail: 'Find the fonts, sizes and weights used on a page',
  ),
  'text_word_count': (
    group: 'Read',
    title: 'Count words',
    detail: 'Count the words on all pages or a selection',
  ),
  'view_reading_colors': (
    group: 'Read',
    title: 'Reading colors',
    detail: 'Choose high-contrast text and background colors',
  ),
  'xfa_to_static': (
    group: 'Forms',
    title: 'Convert a dynamic XFA form',
    detail: 'Keep the laid-out pages and field values in a standard PDF form',
  ),
};
