import 'dart:typed_data';
import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'output_saver.dart';

/// The "Final Mile" delivery hub: unified completion screen for finishing a task,
/// sharing via WhatsApp/Email, saving to device files, or opening directly in reader.
class DeliveryHubSheet extends StatelessWidget {
  const DeliveryHubSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.bytes,
    this.suggestedFileName = 'document.pdf',
    this.badgeText,
    this.onOpenInReader,
    this.onOpenDocument,
  });

  final String title;
  final String subtitle;
  final Uint8List bytes;
  final String suggestedFileName;
  final String? badgeText;
  final VoidCallback? onOpenInReader;
  final void Function(Uint8List bytes, String name)? onOpenDocument;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Uint8List bytes,
    String suggestedFileName = 'document.pdf',
    String? badgeText,
    VoidCallback? onOpenInReader,
    void Function(Uint8List bytes, String name)? onOpenDocument,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => DeliveryHubSheet(
        title: title,
        subtitle: subtitle,
        bytes: bytes,
        suggestedFileName: suggestedFileName,
        badgeText: badgeText,
        onOpenInReader: onOpenInReader,
        onOpenDocument: onOpenDocument,
      ),
    );
  }

  Future<void> _share(BuildContext context) async {
    try {
      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            mimeType: 'application/pdf',
            name: suggestedFileName,
          ),
        ],
        subject: suggestedFileName,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sharing failed: $e')),
        );
      }
    }
  }

  Future<void> _save(BuildContext context) async {
    try {
      final uri = await FilePickerPlatform.instance.saveFile(
        fileName: suggestedFileName,
        bytes: bytes,
        mimeType: mimeTypeFor(suggestedFileName),
        dialogTitle: 'Save $suggestedFileName',
      );
      if (!context.mounted) return;
      if (uri != null) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved $suggestedFileName to device')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sizeKb = (bytes.length / 1024).round();
    final sizeLabel = sizeKb > 1024
        ? '${(bytes.length / (1024 * 1024)).toStringAsFixed(2)} MB'
        : '$sizeKb KB';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check_circle_outline,
                    color: theme.colorScheme.onPrimaryContainer,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (badgeText != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                badgeText!,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSecondaryContainer,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$subtitle • $sizeLabel',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 1. Primary Action: Instant Share
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                icon: const Icon(Icons.share_outlined, size: 20),
                label: const Text('Send via WhatsApp or Mail'),
                onPressed: () => _share(context),
              ),
            ),
            const SizedBox(height: 10),

            // 2. Secondary Action: Save to files
            SizedBox(
              height: 46,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.download_outlined, size: 20),
                label: const Text('Save PDF to device'),
                onPressed: () => _save(context),
              ),
            ),

            if (onOpenInReader != null || onOpenDocument != null) ...[
              const SizedBox(height: 10),
              Center(
                child: TextButton.icon(
                  icon: const Icon(Icons.menu_book_outlined, size: 18),
                  label: const Text('Open in reader'),
                  onPressed: () {
                    Navigator.pop(context);
                    if (onOpenDocument != null) {
                      onOpenDocument!(bytes, suggestedFileName);
                    } else if (onOpenInReader != null) {
                      onOpenInReader!();
                    }
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
