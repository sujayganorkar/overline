import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_diagnostics.dart';
import 'app_notice.dart';

/// Modal bottom sheet displaying recent session diagnostic breadcrumbs with 1-tap copy.
class DiagnosticsSheet extends StatelessWidget {
  const DiagnosticsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const DiagnosticsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final breadcrumbs = AppDiagnostics.instance.breadcrumbs.reversed.toList();

    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.troubleshoot, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Diagnostics & Activity Log',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${breadcrumbs.length} recent session events',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy'),
                  onPressed: () {
                    final log = AppDiagnostics.instance.exportTimeline();
                    Clipboard.setData(ClipboardData(text: log));
                    AppNotice.show(
                      context,
                      const AppNotice(
                        message: 'Diagnostic log copied to clipboard',
                        kind: NoticeKind.success,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: breadcrumbs.isEmpty
                ? const Center(
                    child: Text('No diagnostic events recorded yet in this session.'),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: breadcrumbs.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = breadcrumbs[index];
                      final (color, icon) = switch (item.level) {
                        BreadcrumbLevel.error => (
                          theme.colorScheme.error,
                          Icons.error_outline,
                        ),
                        BreadcrumbLevel.warning => (
                          Colors.amber.shade800,
                          Icons.warning_amber_rounded,
                        ),
                        BreadcrumbLevel.info => (
                          theme.colorScheme.primary,
                          Icons.info_outline,
                        ),
                      };

                      return ListTile(
                        dense: true,
                        leading: Icon(icon, color: color, size: 20),
                        title: Text(
                          item.message,
                          style: TextStyle(
                            fontWeight: item.level == BreadcrumbLevel.error
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(
                          '${item.formattedTime} · [${item.category}]'
                          '${item.details != null ? '\n${item.details}' : ''}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
