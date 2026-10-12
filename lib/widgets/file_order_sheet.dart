import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';

/// Reorder files before a workflow whose result depends on input order.
/// Large arrow buttons provide a precise thumb alternative to dragging.
Future<List<PlatformFile>?> showFileOrderSheet(
  BuildContext context, {
  required List<PlatformFile> files,
  required String title,
  required String explanation,
  required String actionLabel,
}) => showModalBottomSheet<List<PlatformFile>>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) => _FileOrderSheet(
    files: files,
    title: title,
    explanation: explanation,
    actionLabel: actionLabel,
  ),
);

class _FileOrderSheet extends StatefulWidget {
  const _FileOrderSheet({
    required this.files,
    required this.title,
    required this.explanation,
    required this.actionLabel,
  });

  final List<PlatformFile> files;
  final String title;
  final String explanation;
  final String actionLabel;

  @override
  State<_FileOrderSheet> createState() => _FileOrderSheetState();
}

class _FileOrderSheetState extends State<_FileOrderSheet> {
  late final List<PlatformFile> _ordered = widget.files.toList();

  void _move(int from, int to) {
    if (to < 0 || to >= _ordered.length || from == to) return;
    setState(() {
      final file = _ordered.removeAt(from);
      _ordered.insert(to, file);
    });
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.82,
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
                        widget.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(widget.explanation),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Cancel',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: _ordered.length,
              onReorderItem: (oldIndex, newIndex) => _move(oldIndex, newIndex),
              itemBuilder: (context, index) {
                final file = _ordered[index];
                return ListTile(
                  key: ValueKey('${file.name}-$index'),
                  leading: CircleAvatar(child: Text('${index + 1}')),
                  title: Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(_formatSize(file.lengthSync())),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Move earlier',
                        onPressed: index == 0
                            ? null
                            : () => _move(index, index - 1),
                        icon: const Icon(Icons.arrow_upward),
                      ),
                      IconButton(
                        tooltip: 'Move later',
                        onPressed: index == _ordered.length - 1
                            ? null
                            : () => _move(index, index + 1),
                        icon: const Icon(Icons.arrow_downward),
                      ),
                      ReorderableDragStartListener(
                        index: index,
                        child: const SizedBox(
                          width: 48,
                          height: 48,
                          child: Icon(Icons.drag_handle),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Material(
            elevation: 6,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _ordered.isEmpty
                        ? null
                        : () => Navigator.pop(context, _ordered.toList()),
                    icon: const Icon(Icons.check),
                    label: Text(widget.actionLabel),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

String _formatSize(int? bytes) {
  if (bytes == null) return 'Size unavailable';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
