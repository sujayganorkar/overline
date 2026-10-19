import 'package:flutter_test/flutter_test.dart';
import 'package:overline/widgets/annotate_page.dart'
    show selectionQuads, TextLineBox;
import 'package:overline/widgets/annotation_geometry.dart' as geo;

void main() {
  test('image pixels convert to top-left PDF points at the render dpi', () {
    expect(geo.pxToPt(96, 96), 72.0);
    expect(geo.pxToPt(0, 96), 0.0);
    expect(geo.pxToPt(48, 96), 36.0);
    expect(geo.ptToPx(72, 96), 96.0);
  });

  test('ink arguments carry strokes, color and width', () {
    final args = geo.inkArgs(
      page: 2,
      strokes: [
        geo.InkStroke(
          points: const [geo.Point(0, 0), geo.Point(96, 96)],
          color: 'red',
          width: 2,
        ),
      ],
      dpi: 96,
      color: 'blue',
      width: 4,
    );
    expect(args['page'], 2);
    expect(args['type'], 'ink');
    expect(args['strokes'], [
      [
        [0.0, 0.0],
        [72.0, 72.0],
      ],
    ]);
    expect(args['color'], 'blue');
    expect(args['width'], 4);
  });

  test('rectangle arguments normalize corners and convert units', () {
    final args = geo.rectArgs(
      page: 1,
      type: 'rectangle',
      x0: 192,
      y0: 192,
      x1: 96,
      y1: 96,
      dpi: 96,
      color: 'green',
      width: 1,
    );
    expect(args['rect'], [72.0, 72.0, 144.0, 144.0]);
  });

  test('line arguments convert endpoints', () {
    final args = geo.lineArgs(
      page: 1,
      type: 'arrow',
      x0: 0,
      y0: 0,
      x1: 96,
      y1: 0,
      dpi: 96,
      color: 'black',
      width: 2,
    );
    expect(args['from'], [0.0, 0.0]);
    expect(args['to'], [72.0, 0.0]);
  });

  test('selection intersects line boxes and emits engine-ordered quads', () {
    const lines = [
      TextLineBox(text: 'first', rect: [10.0, 10.0, 100.0, 24.0]),
      TextLineBox(text: 'second', rect: [10.0, 30.0, 100.0, 44.0]),
    ];
    final quads = selectionQuads(lines, 0, 0, 50, 20);
    expect(quads, [
      [10.0, 10.0, 100.0, 10.0, 10.0, 24.0, 100.0, 24.0],
    ]);
  });

  test('selection with no overlap returns no quads', () {
    const lines = [
      TextLineBox(text: 'first', rect: [10.0, 10.0, 100.0, 24.0]),
    ];
    expect(selectionQuads(lines, 0, 100, 50, 200), isEmpty);
  });
}
