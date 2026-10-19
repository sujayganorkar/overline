import 'package:flutter_test/flutter_test.dart';
import 'package:overline/widgets/document_heading.dart';

void main() {
  test(
    'document heading shows the page count with correct singularization',
    () {
      expect(documentHeading('report.pdf', 1), 'report.pdf - 1 page');
      expect(documentHeading('report.pdf', 4), 'report.pdf - 4 pages');
    },
  );
}
