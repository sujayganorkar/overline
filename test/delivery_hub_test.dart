import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overline/widgets/delivery_hub_sheet.dart';
import 'package:overline/widgets/output_saver.dart';

void main() {
  testWidgets(
    'non-PDF output has generic save wording and no PDF reader action',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeliveryHubSheet(
              title: 'Your file is ready',
              subtitle: 'export.txt',
              suggestedFileName: 'export.txt',
              bytes: Uint8List.fromList([65]),
              onOpenDocument: (_, _) {},
            ),
          ),
        ),
      );
      expect(find.text('Save to device'), findsOneWidget);
      expect(find.text('Share file'), findsOneWidget);
      expect(find.text('Open in reader'), findsNothing);
      expect(mimeTypeFor('export.txt'), 'text/plain');
      expect(
        mimeTypeFor('export.docx'),
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      );
    },
  );
}
