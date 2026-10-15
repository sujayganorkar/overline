import 'package:flutter/material.dart';

import 'zoom_controls.dart';

/// One dock owns navigation and zoom; neither floats over the document.
class ReaderControls extends StatefulWidget {
  const ReaderControls({
    super.key,
    required this.page,
    required this.pageCount,
    required this.onNavigate,
    required this.transform,
    this.busy = false,
    this.viewportSize,
  });
  final int page, pageCount;
  final ValueChanged<int> onNavigate;
  final TransformationController transform;
  final bool busy;
  final Size? Function()? viewportSize;
  @override
  State<ReaderControls> createState() => _ReaderControlsState();
}

class _ReaderControlsState extends State<ReaderControls> {
  bool _zoom = false;
  Future<void> _pages() async {
    final page = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      builder: (_) =>
          _PageNavigation(page: widget.page, count: widget.pageCount),
    );
    if (page != null && mounted && !widget.busy) widget.onNavigate(page);
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: widget.busy ? null : _pages,
                icon: const Icon(Icons.unfold_more),
                label: Text('Page ${widget.page} of ${widget.pageCount}'),
              ),
            ),
            TextButton.icon(
              onPressed: () => setState(() => _zoom = !_zoom),
              icon: Icon(_zoom ? Icons.close : Icons.zoom_in),
              label: Text(_zoom ? 'Close zoom' : 'Zoom'),
            ),
            const SizedBox(width: 12),
          ],
        ),
        if (_zoom)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ZoomControlsHud(
              transformController: widget.transform,
              viewportSizeProvider: widget.viewportSize,
            ),
          ),
      ],
    ),
  );
}

class _PageNavigation extends StatefulWidget {
  const _PageNavigation({required this.page, required this.count});
  final int page, count;
  @override
  State<_PageNavigation> createState() => _PageNavigationState();
}

class _PageNavigationState extends State<_PageNavigation> {
  late int _page = widget.page;
  late final _number = TextEditingController(text: '$_page');
  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  void _select(int page) => setState(() {
    _page = page;
    _number.text = '$page';
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      16,
      20,
      16 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Go to page',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                  tooltip: 'Close page navigation',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Row(
              children: [
                IconButton(
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                  tooltip: 'Previous page',
                  onPressed: _page > 1 ? () => _select(_page - 1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: TextField(
                    controller: _number,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Page 1–${widget.count}',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (text) {
                      final value = int.tryParse(text);
                      setState(() {
                        if (value != null &&
                            value >= 1 &&
                            value <= widget.count) {
                          _page = value;
                        }
                      });
                    },
                  ),
                ),
                IconButton(
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                  tooltip: 'Next page',
                  onPressed: _page < widget.count
                      ? () => _select(_page + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            if (widget.count > 1)
              Slider(
                value: _page.toDouble(),
                min: 1,
                max: widget.count.toDouble(),
                divisions: widget.count - 1,
                label: 'Page $_page',
                onChanged: (v) => _select(v.round()),
              ),
            FilledButton(
              onPressed: int.tryParse(_number.text) == _page
                  ? () => Navigator.pop(context, _page)
                  : null,
              child: Text('Go to page $_page'),
            ),
          ],
        ),
      ),
    ),
  );
}

class TextSelectionActions extends StatelessWidget {
  const TextSelectionActions({
    super.key,
    required this.busy,
    required this.onApply,
    required this.onCopy,
    required this.onClear,
    required this.color,
    required this.onColor,
  });
  final bool busy;
  final ValueChanged<String> onApply, onColor;
  final VoidCallback onCopy, onClear;
  final String color;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            TextButton.icon(
              onPressed: busy ? null : () => onApply('highlight'),
              icon: const Icon(Icons.border_color),
              label: const Text('Highlight'),
            ),
            PopupMenuButton<String>(
              tooltip: 'Highlight color',
              initialValue: color,
              enabled: !busy,
              onSelected: onColor,
              icon: const Icon(Icons.palette_outlined),
              itemBuilder: (_) => [
                for (final c in ['yellow', 'green', 'blue', 'red'])
                  PopupMenuItem(value: c, child: Text(c)),
              ],
            ),
            IconButton(
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              tooltip: 'Underline',
              onPressed: busy ? null : () => onApply('underline'),
              icon: const Icon(Icons.format_underlined),
            ),
            IconButton(
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              tooltip: 'Strikethrough',
              onPressed: busy ? null : () => onApply('strikeout'),
              icon: const Icon(Icons.format_strikethrough),
            ),
            IconButton(
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              tooltip: 'Copy text',
              onPressed: onCopy,
              icon: const Icon(Icons.copy_outlined),
            ),
            IconButton(
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              tooltip: 'Clear selection',
              onPressed: onClear,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    ),
  );
}
