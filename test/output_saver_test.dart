import 'package:flutter_test/flutter_test.dart';
import 'package:overline/widgets/output_saver.dart';

void main() {
  test('real output files are offered through Save As', () {
    expect(outputPathsIn('{"path": "outputs/combined.pdf", "bytes": 42}'), [
      'outputs/combined.pdf',
    ]);
    expect(
      outputPathsIn(
        '{"count": 2, "files": ["outputs/a.png", "outputs/b.png"]}',
      ),
      ['outputs/a.png', 'outputs/b.png'],
    );
  });

  test('the open document staging path is never offered as a result', () {
    // Mutating tools echo the document summary, including its own path.
    // Offering it would silently save the pre-edit original bytes.
    expect(
      outputPathsIn(
        '{"doc": 7, "name": "a.pdf", "path": "imports/mobile-1-a.pdf",'
        ' "pages": 2, "dirty": true}',
      ),
      isEmpty,
    );
    expect(outputPathsIn('{"path": "/etc/passwd"}'), isEmpty);
    expect(outputPathsIn('{"path": "../outside.pdf"}'), isEmpty);
  });

  test('unwritten doc_reduce results are ignored while written ones are offered', () {
    expect(
      outputPathsIn(
        '{"path": "outputs/reduced.pdf", "written": false, "bytes_before": 500, "bytes_after": 520}',
      ),
      isEmpty,
    );
    expect(
      outputPathsIn(
        '{"path": "outputs/reduced.pdf", "written": true, "bytes_before": 900, "bytes_after": 500}',
      ),
      ['outputs/reduced.pdf'],
    );
  });
}
