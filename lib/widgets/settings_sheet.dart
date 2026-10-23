import 'package:flutter/material.dart';

import '../services/recent_documents_store.dart';
import '../services/signature_store.dart';
import '../services/theme_preference.dart';
import '../services/update_checker.dart';
import '../services/view_preference.dart';
import 'app_notice.dart';
import 'diagnostics_sheet.dart';

/// Comprehensive settings sheet for appearance, updates, storage, and privacy.
class SettingsSheet extends StatefulWidget {
  const SettingsSheet({
    super.key,
    this.onRecentsCleared,
    this.onShowLicenses,
  });

  final VoidCallback? onRecentsCleared;
  final VoidCallback? onShowLicenses;

  static Future<void> show(
    BuildContext context, {
    VoidCallback? onRecentsCleared,
    VoidCallback? onShowLicenses,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SettingsSheet(
        onRecentsCleared: onRecentsCleared,
        onShowLicenses: onShowLicenses,
      ),
    );
  }

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  bool _checkingUpdate = false;
  String? _updateStatus;
  UpdateInfo? _availableUpdate;

  Future<void> _checkUpdate() async {
    setState(() {
      _checkingUpdate = true;
      _updateStatus = null;
      _availableUpdate = null;
    });

    final info = await UpdateCheckerService.instance.checkForUpdate();
    if (!mounted) return;

    setState(() {
      _checkingUpdate = false;
      if (info != null && info.hasUpdate) {
        _availableUpdate = info;
        _updateStatus = 'v${info.latestVersion} available';
      } else {
        _updateStatus = 'You are on the latest version';
      }
    });
  }

  Future<void> _confirmClearSignatures() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Saved Signatures?'),
        content: const Text(
          'This will permanently delete your stored handwritten and typed signatures from device flash.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await SignatureStore().clearSignatures();
      if (mounted) {
        AppNotice.show(
          context,
          const AppNotice(
            message: 'Saved signatures cleared',
            kind: NoticeKind.info,
          ),
        );
      }
    }
  }

  Future<void> _confirmClearRecents() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Recent Documents?'),
        content: const Text(
          'This will remove all recent document shortcuts from the home screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await RecentDocumentsStore().clearRecents();
      widget.onRecentsCleared?.call();
      if (mounted) {
        AppNotice.show(
          context,
          const AppNotice(
            message: 'Recent documents history cleared',
            kind: NoticeKind.info,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final readingController =
        context.dependOnInheritedWidgetOfExactType<InheritedNotifier<ReadingPreferenceController>>()
            ?.notifier;
    final themeChoice =
        context.dependOnInheritedWidgetOfExactType<InheritedNotifier<ThemePreferenceController>>()
            ?.notifier
            ?.choice ??
            PdfCraftThemeChoice.system;

    return FractionallySizedBox(
      heightFactor: 0.9,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Settings'),
          centerTitle: false,
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Close',
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            // Section 1: Appearance
            _SectionHeader(title: 'Appearance'),
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Color Theme', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Builder(
                      builder: (ctx) {
                        return SegmentedButton<PdfCraftThemeChoice>(
                          segments: const [
                            ButtonSegment(
                              value: PdfCraftThemeChoice.system,
                              label: Text('System'),
                              icon: Icon(Icons.brightness_auto, size: 18),
                            ),
                            ButtonSegment(
                              value: PdfCraftThemeChoice.light,
                              label: Text('Light'),
                              icon: Icon(Icons.light_mode, size: 18),
                            ),
                            ButtonSegment(
                              value: PdfCraftThemeChoice.dark,
                              label: Text('Dark'),
                              icon: Icon(Icons.dark_mode, size: 18),
                            ),
                          ],
                          selected: {themeChoice},
                          onSelectionChanged: (selection) {
                            if (selection.isNotEmpty) {
                              final choice = selection.first;
                              final inherited = ctx
                                  .findAncestorWidgetOfExactType<InheritedNotifier<ThemePreferenceController>>();
                              inherited?.notifier?.setChoice(choice);
                            }
                          },
                        );
                      },
                    ),
                    if (readingController != null) ...[
                      const Divider(height: 24),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Invert PDF Colors in Dark Mode'),
                        subtitle: const Text('Dims white PDF pages for comfortable nighttime reading'),
                        value: readingController.invertDocumentColors,
                        onChanged: (val) => readingController.setInverted(val),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Section 2: Updates & GitHub
            _SectionHeader(title: 'Updates & Version'),
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.system_update_alt_outlined),
                    title: const Text('Overline v1.0.0'),
                    subtitle: Text(
                      _updateStatus ?? 'Tap to check for updates on GitHub',
                      style: TextStyle(
                        color: _availableUpdate != null
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight: _availableUpdate != null ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    trailing: _checkingUpdate
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : _availableUpdate != null
                            ? FilledButton(
                                onPressed: () =>
                                    UpdateCheckerService.launchUrl(_availableUpdate!.releaseUrl),
                                child: const Text('Download'),
                              )
                            : OutlinedButton(
                                onPressed: _checkUpdate,
                                child: const Text('Check'),
                              ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.code),
                    title: const Text('Source Code on GitHub'),
                    subtitle: const Text('github.com/sujayganorkar/overline'),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: () => UpdateCheckerService.launchUrl('https://github.com/sujayganorkar/overline'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Section 3: Privacy & Data
            _SectionHeader(title: 'Privacy & Storage'),
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.security, color: Colors.green),
                    title: const Text('100% Offline & Private'),
                    subtitle: const Text(
                      'All PDF operations and signatures execute locally on your device CPU. No document is ever uploaded to a cloud server.',
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.history_toggle_off),
                    title: const Text('Clear Recent Documents'),
                    subtitle: const Text('Remove shortcuts from home screen'),
                    trailing: const Icon(Icons.delete_outline, size: 20),
                    onTap: _confirmClearRecents,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.draw_outlined),
                    title: const Text('Clear Saved Signatures'),
                    subtitle: const Text('Erase encrypted signatures from flash'),
                    trailing: const Icon(Icons.delete_outline, size: 20),
                    onTap: _confirmClearSignatures,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.troubleshoot),
                    title: const Text('Session Activity & Diagnostics'),
                    subtitle: const Text('Inspect in-memory diagnostic logs'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pop(context);
                      DiagnosticsSheet.show(context);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Section 4: Feedback & About
            _SectionHeader(title: 'About & Support'),
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.bug_report_outlined),
                    title: const Text('Report an Issue / Suggest Feature'),
                    subtitle: const Text('Submit feedback directly on GitHub'),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: () => UpdateCheckerService.launchUrl(
                      'https://github.com/sujayganorkar/overline/issues/new',
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('About Overline & Licenses'),
                    subtitle: const Text('Legal notices, engine attribution, and fonts'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pop(context);
                      widget.onShowLicenses?.call();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}
