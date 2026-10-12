import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Scale source-image pixels so the entire PDF page is visible in the reading
/// viewport before the user zooms in.
double fitPageScale({
  required double viewportWidth,
  required double viewportHeight,
  required double pageWidth,
  required double pageHeight,
}) {
  if (viewportWidth <= 0 ||
      viewportHeight <= 0 ||
      pageWidth <= 0 ||
      pageHeight <= 0) {
    return 1;
  }
  return math.min(viewportWidth / pageWidth, viewportHeight / pageHeight);
}

/// Turn the page with a deliberate one-finger swipe while at fit scale.
/// At zoom, null leaves the gesture to InteractiveViewer for panning.
int? pageForSwipe(
  Offset delta, {
  required int currentPage,
  required int pageCount,
  required double scale,
  double threshold = 56,
}) {
  if (scale > 1.02) return null;
  final horizontal = delta.dx.abs() > delta.dy.abs();
  final distance = horizontal ? delta.dx.abs() : delta.dy.abs();
  if (distance < threshold) return null;
  final next = horizontal ? delta.dx < 0 : delta.dy < 0;
  final destination = currentPage + (next ? 1 : -1);
  return destination < 1 || destination > pageCount ? null : destination;
}
