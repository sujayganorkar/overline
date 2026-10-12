import 'package:flutter_test/flutter_test.dart';
import 'package:pdfcraft_mobile/widgets/agent_command_sheet.dart';

void main() {
  test('natural-language starters route to a reviewable workflow', () {
    expect(routePdfRequest('Highlight every date in this contract'), 'dates');
    expect(routePdfRequest('Find and redact phone numbers'), 'phones');
    expect(routePdfRequest('Make this PDF smaller than 2 MB'), 'compress');
    expect(routePdfRequest('Compare this with the older version'), 'compare');
    expect(routePdfRequest('Remove pages 2 through 4'), 'pages');
    expect(routePdfRequest('Fill the address fields'), 'forms');
    expect(routePdfRequest('Summarize this PDF'), 'insights:summary');
    expect(
      routePdfRequest('What does this say about warranty?'),
      'insights:What does this say about warranty?',
    );
  });

  test('questions are answered with document evidence', () {
    expect(
      routePdfRequest('Tell me what the document says about liability'),
      'insights:Tell me what the document says about liability',
    );
  });

  test('unhandled tasks do not become hidden engine commands', () {
    expect(
      routePdfRequest('Add a custom stamp to page 4'),
      'unsupported:Add a custom stamp to page 4',
    );
  });
}
