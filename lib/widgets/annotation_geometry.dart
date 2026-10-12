import 'dart:convert';

/// Image-pixel to PDF-point conversion for touch-drawn annotations.
///
/// Upstream geometry (`comment_add`) uses points with the origin at the
/// top-left of the displayed page — the same space as a `page_render` image
/// at 72 dpi. A render at [dpi] therefore maps `pt = px * 72 / dpi`.
double pxToPt(double px, int dpi) => px * 72.0 / dpi;

/// Inverse of [pxToPt], for overlaying engine rects on a rendered image.
double ptToPx(double pt, int dpi) => pt * dpi / 72.0;

/// A freehand stroke captured in image pixels.
class InkStroke {
  InkStroke({required this.points, required this.color, required this.width});

  final List<Point> points;
  final String color;
  final double width;

  Map<String, Object?> toJson() => {
    'points': [
      for (final point in points) [point.x, point.y],
    ],
  };
}

/// A 2D point in image pixels.
class Point {
  const Point(this.x, this.y);

  final double x;
  final double y;
}

/// Build `comment_add` arguments for an ink annotation from strokes given in
/// image pixels.
Map<String, Object?> inkArgs({
  required int page,
  required List<InkStroke> strokes,
  required int dpi,
  required String color,
  required double width,
  String author = '',
}) {
  return {
    'page': page,
    'type': 'ink',
    'strokes': [
      for (final stroke in strokes)
        [
          for (final point in stroke.points)
            [pxToPt(point.x, dpi), pxToPt(point.y, dpi)],
        ],
    ],
    'color': color,
    'width': width,
    if (author.isNotEmpty) 'author': author,
  };
}

/// Build `comment_add` arguments for a rectangle/oval annotation from an
/// image-pixel drag box.
Map<String, Object?> rectArgs({
  required int page,
  required String type,
  required double x0,
  required double y0,
  required double x1,
  required double y1,
  required int dpi,
  required String color,
  required double width,
}) {
  final left = x0 < x1 ? x0 : x1;
  final top = y0 < y1 ? y0 : y1;
  final right = x0 < x1 ? x1 : x0;
  final bottom = y0 < y1 ? y1 : y0;
  return {
    'page': page,
    'type': type,
    'rect': [
      pxToPt(left, dpi),
      pxToPt(top, dpi),
      pxToPt(right, dpi),
      pxToPt(bottom, dpi),
    ],
    'color': color,
    'width': width,
  };
}

/// Build `comment_add` arguments for a line/arrow annotation.
Map<String, Object?> lineArgs({
  required int page,
  required String type,
  required double x0,
  required double y0,
  required double x1,
  required double y1,
  required int dpi,
  required String color,
  required double width,
}) {
  return {
    'page': page,
    'type': type,
    'from': [pxToPt(x0, dpi), pxToPt(y0, dpi)],
    'to': [pxToPt(x1, dpi), pxToPt(y1, dpi)],
    'color': color,
    'width': width,
  };
}

/// Encode arguments for `execute_tool`.
String encodeArgs(Map<String, Object?> args) => jsonEncode(args);
