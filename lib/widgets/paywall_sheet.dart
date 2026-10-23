import 'package:flutter/material.dart';

class PaywallSheet extends StatelessWidget {
  const PaywallSheet({
    super.key,
    this.onSubscribeMonthly,
    this.onSubscribeAnnual,
    this.onRestorePurchases,
  });

  final VoidCallback? onSubscribeMonthly;
  final VoidCallback? onSubscribeAnnual;
  final VoidCallback? onRestorePurchases;

  static Future<void> show(
    BuildContext context, {
    VoidCallback? onSubscribeMonthly,
    VoidCallback? onSubscribeAnnual,
    VoidCallback? onRestorePurchases,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PaywallSheet(
        onSubscribeMonthly: onSubscribeMonthly,
        onSubscribeAnnual: onSubscribeAnnual,
        onRestorePurchases: onRestorePurchases,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        24 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Icon(Icons.auto_awesome, size: 48, color: colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            'Unlock Overline Pro',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'High-reasoning cloud models for multi-page complex analysis, unlimited cloud OCR, and priority document synthesis.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          const _FeatureRow(
            icon: Icons.offline_bolt_outlined,
            title: 'Always Free On-Device Core',
            subtitle: 'Manual PDF editing tools and local Edge SLM remain free forever.',
          ),
          const _FeatureRow(
            icon: Icons.psychology_outlined,
            title: 'Gemini 1.5 Pro & Claude Intelligence',
            subtitle: 'Managed cloud reasoning with zero API keys or setup required.',
          ),
          const _FeatureRow(
            icon: Icons.shield_outlined,
            title: 'Ephemeral Cloud Processing',
            subtitle: 'Document excerpts are processed in memory and never stored on disk.',
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              onSubscribeMonthly?.call();
            },
            child: const Text('Start 7-Day Free Trial'),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  onRestorePurchases?.call();
                },
                child: const Text('Restore Purchases'),
              ),
              const Text('•'),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Continue Free'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 24, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

