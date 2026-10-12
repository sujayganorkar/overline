import 'package:flutter_test/flutter_test.dart';
import 'package:pdfcraft_mobile/widgets/page_viewport.dart';

void main() {
  group('fitPageScale', () {
    test('fits the full portrait page inside the reading viewport', () {
      final scale = fitPageScale(
        viewportWidth: 360,
        viewportHeight: 600,
        pageWidth: 816,
        pageHeight: 1056,
      );
      expect(816 * scale, lessThanOrEqualTo(360));
      expect(1056 * scale, lessThanOrEqualTo(600));
      expect(816 * scale / (1056 * scale), closeTo(816 / 1056, 0.0001));
    });

    test('fits landscape pages without cropping', () {
      final scale = fitPageScale(
        viewportWidth: 360,
        viewportHeight: 600,
        pageWidth: 1056,
        pageHeight: 816,
      );
      expect(1056 * scale, lessThanOrEqualTo(360));
      expect(816 * scale, lessThanOrEqualTo(600));
    });
  });

  group('pageForSwipe', () {
    test('left and up turn forward; right and down turn backward', () {
      expect(
        pageForSwipe(
          const Offset(-100, 8),
          currentPage: 2,
          pageCount: 5,
          scale: 1,
        ),
        3,
      );
      expect(
        pageForSwipe(
          const Offset(100, 8),
          currentPage: 2,
          pageCount: 5,
          scale: 1,
        ),
        1,
      );
      expect(
        pageForSwipe(
          const Offset(10, -100),
          currentPage: 2,
          pageCount: 5,
          scale: 1,
        ),
        3,
      );
      expect(
        pageForSwipe(
          const Offset(10, 100),
          currentPage: 2,
          pageCount: 5,
          scale: 1,
        ),
        1,
      );
    });

    test('ignores taps, boundary swipes, and pans while zoomed', () {
      expect(
        pageForSwipe(
          const Offset(-20, 4),
          currentPage: 2,
          pageCount: 5,
          scale: 1,
        ),
        isNull,
      );
      expect(
        pageForSwipe(
          const Offset(0, 120),
          currentPage: 1,
          pageCount: 5,
          scale: 1,
        ),
        isNull,
      );
      expect(
        pageForSwipe(
          const Offset(-120, 0),
          currentPage: 2,
          pageCount: 5,
          scale: 2,
        ),
        isNull,
      );
    });
  });
}
