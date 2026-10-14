import 'package:flutter/material.dart';

/// Floating zoom controls providing accessible single-pointer Zoom In,
/// Zoom Out, and Reset Zoom to 100% (fit scale) without requiring
/// multi-point pinch gestures (WCAG 2.5.1).
class ZoomControlsHud extends StatelessWidget {
  const ZoomControlsHud({
    super.key,
    required this.transformController,
    this.minScale = 1.0,
    this.maxScale = 8.0,
    this.viewportSize,
  });

  final TransformationController transformController;
  final double minScale;
  final double maxScale;
  final Size? viewportSize;

  void _zoomBy(double factor) {
    final current = transformController.value;
    final currentScale = current.getMaxScaleOnAxis();
    final targetScale = (currentScale * factor).clamp(minScale, maxScale);
    if ((targetScale - currentScale).abs() < 0.01) return;
    final scaleRatio = targetScale / currentScale;

    if (viewportSize != null &&
        viewportSize!.width > 0 &&
        viewportSize!.height > 0) {
      final center = Offset(viewportSize!.width / 2, viewportSize!.height / 2);
      final sceneCenter = transformController.toScene(center);
      final dx = center.dx - sceneCenter.dx * targetScale;
      final dy = center.dy - sceneCenter.dy * targetScale;
      final matrix = Matrix4.identity()
        ..translateByDouble(dx, dy, 0, 1)
        ..scaleByDouble(targetScale, targetScale, 1, 1);
      transformController.value = matrix;
    } else {
      final matrix = current.clone()
        ..scaleByDouble(scaleRatio, scaleRatio, 1, 1);
      transformController.value = matrix;
    }
  }

  void _resetZoom() {
    transformController.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      elevation: 4,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(24),
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.92),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Zoom in',
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              icon: const Icon(Icons.zoom_in, size: 22),
              onPressed: () => _zoomBy(1.3),
            ),
            ValueListenableBuilder<Matrix4>(
              valueListenable: transformController,
              builder: (context, matrix, _) {
                final scalePercent = (matrix.getMaxScaleOnAxis() * 100).round();
                final isZoomed = scalePercent > 102;

                return Semantics(
                  button: true,
                  label:
                      'Zoom level $scalePercent percent.${isZoomed ? ' Double tap to reset to 100% fit scale.' : ''}',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: isZoomed ? _resetZoom : () => _zoomBy(1.5),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Text(
                        '$scalePercent%',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isZoomed ? colorScheme.primary : null,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            IconButton(
              tooltip: 'Zoom out',
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              icon: const Icon(Icons.zoom_out, size: 22),
              onPressed: () => _zoomBy(0.77),
            ),
            ValueListenableBuilder<Matrix4>(
              valueListenable: transformController,
              builder: (context, matrix, _) {
                final isZoomed = matrix.getMaxScaleOnAxis() > 1.02;
                if (!isZoomed) return const SizedBox.shrink();
                return IconButton(
                  tooltip: 'Reset zoom to fit page',
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                  icon: const Icon(Icons.restart_alt, size: 20),
                  onPressed: _resetZoom,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
