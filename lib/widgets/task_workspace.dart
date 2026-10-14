import 'package:flutter/material.dart';

/// A stable place to return to when a task's picker or options are dismissed.
class TaskWorkspace extends StatelessWidget {
  const TaskWorkspace({
    super.key,
    required this.title,
    required this.description,
    required this.scope,
    required this.busy,
    required this.onStart,
    this.progress,
  });
  final String title, description, scope;
  final bool busy;
  final VoidCallback onStart;
  final String? progress;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  onPressed: busy ? null : () => Navigator.pop(context),
                  tooltip: 'Close task',
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(scope, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 16),
            Text(description),
            const SizedBox(height: 24),
            if (busy) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(progress ?? 'Working on your PDF…'),
              ),
            ] else
              FilledButton(onPressed: onStart, child: Text('Continue')),
            const SizedBox(height: 8),
            Text(
              'Review the result before saving or sharing.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}
