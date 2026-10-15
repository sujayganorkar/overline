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
    this.viewportSizeProvider,
  });

  final TransformationController transformController;
  final double minScale;
  final double maxScale;
  final Size? viewportSize;
  final Size? Function()? viewportSizeProvider;

  void _zoomBy(double factor) {
    final current = transformController.value;
    final currentScale = current.getMaxScaleOnAxis();
    final targetScale = (currentScale * factor).clamp(minScale, maxScale);
    if ((targetScale - currentScale).abs() < 0.01) return;
    final scaleRatio = targetScale / currentScale;

    final viewportSize = viewportSizeProvider?.call() ?? this.viewportSize;
    if (viewportSize != null &&
        viewportSize.width > 0 &&
        viewportSize.height > 0) {
      final center = Offset(viewportSize.width / 2, viewportSize.height / 2);
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
  Widget build(BuildContext context) => ValueListenableBuilder<Matrix4>(
    valueListenable: transformController,
    builder: (context, matrix, _) {
      final scale = matrix.getMaxScaleOnAxis();
      final zoomed = scale > minScale + .01;
      return Material(
        borderRadius: BorderRadius.circular(24),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              tooltip: 'Zoom out',
              onPressed: scale <= minScale + .01
                  ? null
                  : () => _zoomBy(1 / 1.3),
              icon: const Icon(Icons.zoom_out),
            ),
            Tooltip(
              message: zoomed ? 'Reset zoom to fit page' : 'Page fits view',
              child: SizedBox(
                width: 88,
                height: 48,
                child: TextButton(
                  onPressed: zoomed ? _resetZoom : null,
                  child: Text('${(scale * 100).round()}%'),
                ),
              ),
            ),
            IconButton(
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              tooltip: 'Zoom in',
              onPressed: scale >= maxScale - .01 ? null : () => _zoomBy(1.3),
              icon: const Icon(Icons.zoom_in),
            ),
          ],
        ),
      );
    },
  );
}
