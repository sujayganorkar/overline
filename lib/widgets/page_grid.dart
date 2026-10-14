import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';

import 'app_notice.dart';

import '../bridge/api.dart' as bridge;
import '../services/pdf_engine.dart';
import 'crop_page.dart';
import 'output_saver.dart';

/// Page overview: thumbnails with rotate/duplicate/delete/move actions and
/// blank-page insertion. All operations go through the shared operation
/// layer; the viewer refreshes from the returned document status.
class PageGrid extends StatefulWidget {
  const PageGrid({
    super.key,
    required this.engine,
    required this.handle,
    required this.pageCount,
    required this.currentPage,
    required this.onStatusChanged,
    required this.onJumpToPage,
  });

  final PdfEngineApi engine;
  final int handle;
  final int pageCount;
  final int currentPage;
  final ValueChanged<bridge.DocumentStatus> onStatusChanged;
  final ValueChanged<int> onJumpToPage;

  @override
  State<PageGrid> createState() => _PageGridState();
}

class _PageGridState extends State<PageGrid> {
  static const _thumbDpi = 36;
  final Map<int, Future<Uint8List>> _thumbs = {};
  bool _busy = false;
  bool _reordering = false;
  late int _pageCount = widget.pageCount;
  final Set<int> _selectedPages = {};
  List<int> _reorderOrder = const [];

  bool get _selecting => _selectedPages.isNotEmpty;
  List<int> get _orderedPages => _reorderOrder.length == _pageCount
      ? _reorderOrder
      : List<int>.generate(_pageCount, (index) => index + 1);

  Future<Uint8List> _thumb(int page) => _thumbs.putIfAbsent(
    page,
    () => widget.engine.renderPagePng(
      handle: widget.handle,
      page1Based: page,
      dpi: _thumbDpi,
    ),
  );

  Future<void> _run(
    String tool,
    Map<String, Object?> args,
    String label,
  ) async {
    setState(() => _busy = true);
    try {
      final response = await widget.engine.executeTool(
        handle: widget.handle,
        tool: tool,
        argumentsJson: jsonEncode(args),
      );
      if (!mounted) return;
      _thumbs.clear();
      widget.onStatusChanged(response.status);
      setState(() {
        _pageCount = response.status.pageCount;
        _reorderOrder = List<int>.generate(_pageCount, (index) => index + 1);
      });
      AppNotice.show(
        context,
        AppNotice(
          message: '$label complete.',
          kind: NoticeKind.success,
          action: response.status.canUndo.isEmpty
              ? null
              : NoticeAction(label: 'Undo', onPressed: _undoLast),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppNotice.show(
        context,
        AppNotice(
          message: '$label failed.',
          kind: NoticeKind.error,
          details: '$e',
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _insertMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.note_add_outlined),
              title: const Text('Blank page at the end'),
              onTap: () => Navigator.pop(context, 'blank'),
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('Pages from another PDF'),
              subtitle: Text('Inserted after page ${widget.currentPage}'),
              onTap: () => Navigator.pop(context, 'file'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'blank') {
      await _run('page_insert_blank', {
        'at': _pageCount + 1,
      }, 'Insert blank page');
      return;
    }
    final picked = await FilePickerPlatform.instance.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      dialogTitle: 'Choose a PDF to insert',
    );
    if (picked.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      final file = picked.first;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) throw StateError('${file.name} is empty');
      final staged = await widget.engine.stageFile(
        name: 'insert-${file.name}',
        bytes: bytes,
      );
      if (!mounted) return;
      final at = (widget.currentPage + 1).clamp(1, _pageCount + 1);
      await _run('page_insert_file', {
        'path': staged,
        'at': at,
      }, 'Insert pages');
    } catch (e) {
      if (!mounted) return;
      AppNotice.show(
        context,
        AppNotice(
          message: 'Could not insert pages.',
          kind: NoticeKind.error,
          details: '$e',
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undoLast() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final response = await widget.engine.executeTool(
        handle: widget.handle,
        tool: 'edit_undo',
        argumentsJson: '{}',
      );
      if (!mounted) return;
      _thumbs.clear();
      _selectedPages.clear();
      widget.onStatusChanged(response.status);
      setState(() {
        _pageCount = response.status.pageCount;
        _reorderOrder = List<int>.generate(_pageCount, (index) => index + 1);
        _reordering = false;
      });
      AppNotice.show(
        context,
        const AppNotice(
          message: 'Last page change undone.',
          kind: NoticeKind.success,
        ),
      );
    } catch (error) {
      if (mounted) {
        AppNotice.show(
          context,
          AppNotice(
            message: 'Could not undo page change.',
            kind: NoticeKind.error,
            details: '$error',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pageMenu(int page) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.rotate_right),
              title: const Text('Rotate 90° clockwise'),
              onTap: () => Navigator.pop(context, 'r90'),
            ),
            ListTile(
              leading: const Icon(Icons.rotate_left),
              title: const Text('Rotate 90° counter-clockwise'),
              onTap: () => Navigator.pop(context, 'r270'),
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Duplicate page'),
              onTap: () => Navigator.pop(context, 'dup'),
            ),
            ListTile(
              leading: const Icon(Icons.crop_outlined),
              title: const Text('Crop this page'),
              subtitle: const Text('Drag the area to keep'),
              onTap: () => Navigator.pop(context, 'crop'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete page'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'r90':
        await _run('page_rotate', {
          'pages': [page],
          'degrees': 90,
        }, 'Rotate');
      case 'r270':
        await _run('page_rotate', {
          'pages': [page],
          'degrees': 270,
        }, 'Rotate');
      case 'dup':
        await _run('page_duplicate', {
          'pages': [page],
        }, 'Duplicate');
      case 'crop':
        await _openCrop(page);
      case 'delete':
        if (_pageCount <= 1) {
          AppNotice.show(
            context,
            const AppNotice(
              message: 'A PDF must keep at least one page.',
              kind: NoticeKind.warning,
            ),
          );
          return;
        }
        final ok = await _confirmDelete(page);
        if (ok == true) {
          await _run('page_delete', {
            'pages': [page],
          }, 'Delete');
        }
    }
  }

  Future<void> _openCrop(int page) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final png = await widget.engine.renderPagePng(
        handle: widget.handle,
        page1Based: page,
        dpi: 96,
      );
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (context) => CropPage(
            engine: widget.engine,
            handle: widget.handle,
            page: page,
            pageCount: _pageCount,
            png: png,
            onStatusChanged: (status) {
              _thumbs.clear();
              widget.onStatusChanged(status);
              if (mounted) {
                setState(() {
                  _pageCount = status.pageCount;
                  _reorderOrder = List<int>.generate(
                    _pageCount,
                    (index) => index + 1,
                  );
                });
              }
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppNotice.show(
        context,
        AppNotice(
          message: 'Could not open crop.',
          kind: NoticeKind.error,
          details: '$e',
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _replaceSelected() async {
    final pages = _selectedPages.toList()..sort();
    if (pages.isEmpty || _busy) return;
    final picked = await FilePickerPlatform.instance.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      dialogTitle: 'Choose the replacement PDF',
    );
    if (picked.isEmpty || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Replace ${pages.length} pages?'),
        content: Text(
          'Pages ${pages.join(', ')} take content from the start of ${picked.first.name}. This is undoable.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final file = picked.first;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) throw StateError('${file.name} is empty');
      final staged = await widget.engine.stageFile(
        name: 'replace-${file.name}',
        bytes: bytes,
      );
      if (!mounted) return;
      await _run('page_replace', {
        'pages': pages,
        'path': staged,
      }, 'Replace pages');
      if (mounted) setState(_selectedPages.clear);
    } catch (e) {
      if (!mounted) return;
      AppNotice.show(
        context,
        AppNotice(
          message: 'Could not replace pages.',
          kind: NoticeKind.error,
          details: '$e',
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirmDelete(int page) => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete page?'),
      content: Text('Page $page will be removed. This is undoable.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );

  Future<void> _deleteSelected() async {
    final pages = _selectedPages.toList()..sort();
    if (pages.isEmpty || _busy) return;
    if (pages.length >= _pageCount) {
      AppNotice.show(
        context,
        const AppNotice(
          message: 'A PDF must keep at least one page.',
          kind: NoticeKind.warning,
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${pages.length} pages?'),
        content: Text(
          'Pages ${pages.join(', ')} will be removed. You can undo this after deletion.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep pages'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete ${pages.length}'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run('page_delete', {'pages': pages}, 'Delete pages');
    if (mounted) setState(_selectedPages.clear);
  }

  Future<void> _extractSelected() async {
    final pages = _selectedPages.toList()..sort();
    if (pages.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final response = await widget.engine.executeTool(
        handle: widget.handle,
        tool: 'page_extract',
        argumentsJson: jsonEncode({
          'pages': pages,
          'out': 'outputs/extract-${DateTime.now().microsecondsSinceEpoch}.pdf',
        }),
      );
      if (!mounted) return;
      widget.onStatusChanged(response.status);
      await saveToolOutputs(context, widget.engine, [
        for (final content in response.contents) content.json,
      ]);
    } catch (error) {
      if (mounted) {
        AppNotice.show(
          context,
          AppNotice(
            message: 'Could not extract these pages.',
            kind: NoticeKind.error,
            details: '$error',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleSelected(int page) {
    setState(() {
      if (!_selectedPages.add(page)) _selectedPages.remove(page);
    });
  }

  Future<void> _movePage(int oldIndex, int newIndex) async {
    if (_busy || oldIndex == newIndex) return;
    final pageOrder = _orderedPages.toList();
    final page = pageOrder.removeAt(oldIndex);
    pageOrder.insert(newIndex, page);
    setState(() {
      _busy = true;
      _reorderOrder = pageOrder;
    });
    try {
      final response = await widget.engine.executeTool(
        handle: widget.handle,
        tool: 'page_move',
        argumentsJson: jsonEncode({
          'pages': [oldIndex + 1],
          'to': newIndex + 1,
        }),
      );
      if (!mounted) return;
      _thumbs.clear();
      widget.onStatusChanged(response.status);
      setState(() {
        _pageCount = response.status.pageCount;
        _reorderOrder = List<int>.generate(_pageCount, (index) => index + 1);
      });
      AppNotice.show(
        context,
        AppNotice(
          message: 'Page moved to position ${newIndex + 1}.',
          kind: NoticeKind.info,
          action: NoticeAction(label: 'Undo', onPressed: _undoLast),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _reorderOrder = List<int>.generate(_pageCount, (index) => index + 1);
      });
      AppNotice.show(
        context,
        AppNotice(
          message: 'Could not move page.',
          kind: NoticeKind.error,
          details: '$error',
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _selecting
                              ? '${_selectedPages.length} selected'
                              : _reordering
                              ? 'Reorder pages'
                              : 'Pages ($_pageCount)',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      if (_selecting)
                        TextButton(
                          onPressed: () => setState(_selectedPages.clear),
                          child: const Text('Clear'),
                        ),
                      if (!_selecting && !_reordering)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                  _reordering = true;
                                  _reorderOrder = List<int>.generate(
                                    _pageCount,
                                    (index) => index + 1,
                                  );
                                }),
                          child: const Text('Reorder'),
                        ),
                      if (_reordering)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _reordering = false),
                          child: const Text('Done'),
                        ),
                      if (!_selecting && !_reordering)
                        TextButton.icon(
                          onPressed: _busy ? null : _insertMenu,
                          icon: const Icon(Icons.add),
                          label: const Text('Insert'),
                        ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  if (!_selecting && !_reordering)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Tap to open · long-press to select · More for page actions',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  if (_reordering)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Drag pages or use the arrows. Each move can be undone.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            Expanded(
              child: _reordering
                  ? ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      itemCount: _orderedPages.length,
                      onReorderItem: _movePage,
                      itemBuilder: (context, index) {
                        final page = _orderedPages[index];
                        return Card(
                          key: ValueKey(page),
                          child: ListTile(
                            leading: SizedBox(
                              width: 68,
                              height: 88,
                              child: FutureBuilder<Uint8List>(
                                future: _thumb(page),
                                builder: (context, snapshot) => snapshot.hasData
                                    ? Image.memory(
                                        snapshot.data!,
                                        fit: BoxFit.contain,
                                        semanticLabel:
                                            'Page ${index + 1} thumbnail',
                                      )
                                    : const Center(
                                        child: CircularProgressIndicator(),
                                      ),
                              ),
                            ),
                            title: Text('Page ${index + 1}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Move page ${index + 1} earlier',
                                  onPressed: _busy || index == 0
                                      ? null
                                      : () => _movePage(index, index - 1),
                                  icon: const Icon(Icons.arrow_upward),
                                ),
                                IconButton(
                                  tooltip: 'Move page ${index + 1} later',
                                  onPressed: _busy || index == _pageCount - 1
                                      ? null
                                      : () => _movePage(index, index + 1),
                                  icon: const Icon(Icons.arrow_downward),
                                ),
                                ReorderableDragStartListener(
                                  index: index,
                                  child: Semantics(
                                    label: 'Drag handle to reorder page',
                                    child: SizedBox(
                                      width: 48,
                                      height: 48,
                                      child: Icon(Icons.drag_handle),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 0.72,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                      itemCount: _pageCount,
                      itemBuilder: (context, index) {
                        final page = _orderedPages[index];
                        final selected = page == widget.currentPage;
                        final selectedForDelete = _selectedPages.contains(page);
                        return Semantics(
                          label:
                              'Page $page of $_pageCount${page == widget.currentPage ? ", current page" : ""}',
                          selected: _selecting
                              ? selectedForDelete
                              : (page == widget.currentPage),
                          button: true,
                          hint: _selecting
                              ? (selectedForDelete
                                    ? 'Double tap to deselect'
                                    : 'Double tap to select')
                              : 'Double tap to jump to page $page. Double tap and hold to select for bulk actions.',
                          child: GestureDetector(
                            onTap: () {
                              if (_selecting) {
                                _toggleSelected(page);
                              } else {
                                widget.onJumpToPage(page);
                                Navigator.pop(context);
                              }
                            },
                            onLongPress: () {
                              if (_selecting) {
                                _toggleSelected(page);
                              } else {
                                setState(() => _selectedPages.add(page));
                              }
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: selectedForDelete
                                      ? Theme.of(context).colorScheme.error
                                      : selected
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).dividerColor,
                                  width: selectedForDelete || selected ? 3 : 1,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Column(
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(5),
                                      ),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          FutureBuilder<Uint8List>(
                                            future: _thumb(page),
                                            builder: (context, snapshot) {
                                              if (!snapshot.hasData) {
                                                return const Center(
                                                  child:
                                                      CircularProgressIndicator(),
                                                );
                                              }
                                              return Image.memory(
                                                snapshot.data!,
                                                fit: BoxFit.contain,
                                                gaplessPlayback: true,
                                                semanticLabel:
                                                    'Page $page thumbnail',
                                              );
                                            },
                                          ),
                                          if (_selecting)
                                            Align(
                                              alignment: Alignment.topRight,
                                              child: Padding(
                                                padding: const EdgeInsets.all(
                                                  6,
                                                ),
                                                child: Icon(
                                                  selectedForDelete
                                                      ? Icons.check_circle
                                                      : Icons.circle_outlined,
                                                  color: selectedForDelete
                                                      ? Theme.of(context)
                                                            .colorScheme
                                                            .error
                                                      : Theme.of(context)
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                                  size: 28,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    height: 48,
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          '$page',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                        if (!_selecting)
                                          IconButton(
                                            tooltip: 'Page $page actions',
                                            onPressed: () => _pageMenu(page),
                                            icon: const Icon(Icons.more_horiz),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (_selecting)
              Material(
                elevation: 6,
                color: Theme.of(context).colorScheme.surface,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => setState(_selectedPages.clear),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed:
                                  _busy || _selectedPages.length == _pageCount
                                  ? null
                                  : () => setState(() {
                                      _selectedPages
                                        ..clear()
                                        ..addAll(
                                          List.generate(
                                            _pageCount,
                                            (i) => i + 1,
                                          ),
                                        );
                                    }),
                              child: const Text('Select all'),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _busy ? null : _extractSelected,
                                icon: const Icon(Icons.output_outlined),
                                label: Text('Extract ${_selectedPages.length}'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _busy ? null : _deleteSelected,
                                icon: const Icon(Icons.delete_outline),
                                label: Text('Delete ${_selectedPages.length}'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _replaceSelected,
                            icon: const Icon(Icons.find_replace_outlined),
                            label: Text(
                              'Replace ${_selectedPages.length} with another file',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
