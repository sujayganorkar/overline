import 'package:flutter_test/flutter_test.dart';
import 'package:overline/widgets/comments_screen.dart';

void main() {
  test('comment thread parses engine list output with nested replies', () {
    final thread = CommentThread.fromJson({
      'id': 'abc',
      'page': 2,
      'index': 3,
      'type': 'highlight',
      'author': 'Ada',
      'contents': 'Important',
      'modified': 'D:20260101',
      'status': 'accepted',
      'marked': true,
      'locked': false,
      'replies': [
        {'author': 'Bo', 'contents': 'Agreed', 'modified': ''},
      ],
    })!;

    expect(thread.page, 2);
    expect(thread.index, 3);
    expect(thread.type, 'highlight');
    expect(thread.status, 'accepted');
    expect(thread.marked, isTrue);
    expect(thread.replies, hasLength(1));
    expect(thread.replies.first.contents, 'Agreed');
  });

  test('comment thread without page or index is rejected', () {
    expect(CommentThread.fromJson({'type': 'note'}), isNull);
  });
}
