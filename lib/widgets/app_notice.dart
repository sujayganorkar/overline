import 'dart:async';

import 'package:flutter/material.dart';

enum NoticeKind { info, success, warning, error }

class NoticeAction {
  const NoticeAction({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;
}

/// In-app feedback. Progress belongs in the working screen, not in this layer.
class AppNotice {
  const AppNotice({
    required this.message,
    this.kind = NoticeKind.info,
    this.details,
    this.action,
    this.duration,
  });
  final String message;
  final NoticeKind kind;
  final String? details;
  final NoticeAction? action;
  final Duration? duration;

  static final _presenters = Expando<_NoticePresenter>();

  static void show(BuildContext context, AppNotice notice) {
    if (!context.mounted) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final presenter = _presenters[overlay] ??= _NoticePresenter(overlay);
    presenter.show(context, notice);
  }

  static void dismissAction(BuildContext context) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final presenter = _presenters[overlay];
    if (presenter?._current?.action != null) presenter?.dismiss();
  }

  static void dismiss(BuildContext context) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay != null) _presenters[overlay]?.dismiss();
  }
}

/// Clears obsolete feedback on navigation without hiding a plain completion
/// message when a task closes itself after success.
class NoticeNavigatorObserver extends NavigatorObserver {
  _NoticePresenter? get _presenter {
    final overlay = navigator?.overlay;
    return overlay == null ? null : AppNotice._presenters[overlay];
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _presenter?.dismiss();
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _presenter?.dismiss();
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _presenter?.dismissActionFrom(route);
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _presenter?.dismissActionFrom(route);
}

class _NoticePresenter {
  _NoticePresenter(this.overlay);
  final OverlayState overlay;
  OverlayEntry? _entry;
  int _version = 0;
  AppNotice? _current;
  ModalRoute<dynamic>? _sourceRoute;
  void dismissActionFrom(Route<dynamic> route) {
    if (_current?.action != null && identical(_sourceRoute, route)) dismiss();
  }

  void dismiss() {
    _version++;
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
    _current = null;
    _sourceRoute = null;
  }

  void show(BuildContext source, AppNotice notice) {
    if (notice.action == null &&
        _current?.action == null &&
        _current?.message == notice.message &&
        _current?.kind == notice.kind &&
        _current?.details == notice.details) {
      return;
    }
    // Replace rather than queue: feedback always describes the latest action.
    dismiss();
    final version = _version;
    _current = notice;
    _sourceRoute = ModalRoute.of(source);
    final theme = Theme.of(source);
    final accessible =
        MediaQuery.maybeOf(source)?.accessibleNavigation ?? false;
    _entry = OverlayEntry(
      builder: (context) => _NoticeCard(
        notice: notice,
        theme: theme,
        autoDismissAfter:
            !accessible &&
                notice.kind != NoticeKind.error &&
                notice.action == null
            ? notice.duration ??
                  Duration(seconds: notice.kind == NoticeKind.success ? 3 : 5)
            : null,
        onDismiss: () {
          if (_version == version) dismiss();
        },
        onAction: notice.action == null
            ? null
            : () {
                if (_version != version) return;
                dismiss();
                // Undo callbacks often belong to a page that may since have closed.
                if (source.mounted) notice.action!.onPressed();
              },
      ),
    );
    overlay.insert(_entry!);
  }
}

class _NoticeCard extends StatefulWidget {
  const _NoticeCard({
    required this.notice,
    required this.theme,
    required this.onDismiss,
    required this.onAction,
    required this.autoDismissAfter,
  });
  final AppNotice notice;
  final Duration? autoDismissAfter;
  final ThemeData theme;
  final VoidCallback onDismiss;
  final VoidCallback? onAction;
  @override
  State<_NoticeCard> createState() => _NoticeCardState();
}

class _NoticeCardState extends State<_NoticeCard> {
  bool _expanded = false;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    if (widget.autoDismissAfter != null) {
      _timer = Timer(widget.autoDismissAfter!, widget.onDismiss);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notice = widget.notice;
    final colors = widget.theme.colorScheme;
    final color = switch (notice.kind) {
      NoticeKind.error => colors.error,
      NoticeKind.warning => colors.onSurface,
      NoticeKind.success => colors.primary,
      NoticeKind.info => colors.onSurfaceVariant,
    };
    final icon = switch (notice.kind) {
      NoticeKind.error => Icons.error_outline,
      NoticeKind.warning => Icons.warning_amber_rounded,
      NoticeKind.success => Icons.check_circle_outline,
      NoticeKind.info => Icons.info_outline,
    };
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 560,
                maxHeight: MediaQuery.sizeOf(context).height * .45,
              ),
              child: Theme(
                data: widget.theme,
                child: Material(
                  elevation: 8,
                  color: colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 12,
                                  right: 12,
                                ),
                                child: Icon(icon, color: color),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  child: Semantics(
                                    liveRegion: true,
                                    child: Text(
                                      notice.message,
                                      style: widget.theme.textTheme.bodyMedium
                                          ?.copyWith(color: colors.onSurface),
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Dismiss notification',
                                onPressed: widget.onDismiss,
                                constraints: const BoxConstraints(
                                  minWidth: 48,
                                  minHeight: 48,
                                ),
                                icon: const Icon(Icons.close, size: 20),
                              ),
                            ],
                          ),
                          if (notice.action != null || notice.details != null)
                            Wrap(
                              spacing: 8,
                              alignment: WrapAlignment.end,
                              children: [
                                if (notice.details != null)
                                  TextButton(
                                    onPressed: () =>
                                        setState(() => _expanded = !_expanded),
                                    child: Text(
                                      _expanded
                                          ? 'Hide details'
                                          : 'Show details',
                                    ),
                                  ),
                                if (notice.action != null)
                                  TextButton(
                                    onPressed: widget.onAction,
                                    child: Text(notice.action!.label),
                                  ),
                              ],
                            ),
                          if (_expanded && notice.details != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                              child: SelectableText(
                                notice.details!,
                                style: widget.theme.textTheme.bodySmall,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
