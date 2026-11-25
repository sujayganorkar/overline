import 'dart:convert';
import 'dart:typed_data';

/// Untagged text with only the PDF text operators supported by auto-tag Apply.
Uint8List textPdf(List<List<String>> pages, {bool firstLineIsHeading = false}) {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Count ${pages.length} /Kids [${[for (var i = 0; i < pages.length; i++) '${4 + 2 * i} 0 R'].join(' ')}] >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  for (final lines in pages) {
    final content = StringBuffer();
    for (final (index, line) in lines.indexed) {
      final text = line
          .replaceAll(r'\', r'\\')
          .replaceAll('(', r'\(')
          .replaceAll(')', r'\)');
      final size = index == 0 && firstLineIsHeading ? 24 : 12;
      content.writeln(
        'BT /F1 $size Tf 50 ${730 - index * 40} Td ($text) Tj ET',
      );
    }
    objects.add(
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
      '/Resources << /Font << /F1 3 0 R >> >> /Contents ${objects.length + 2} 0 R >>',
    );
    objects.add('<< /Length ${content.length} >>\nstream\n${content}endstream');
  }

  final file = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (final (index, object) in objects.indexed) {
    offsets.add(file.length);
    file.write('${index + 1} 0 obj\n$object\nendobj\n');
  }
  final xref = file.length;
  file.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    file.writeln("${offset.toString().padLeft(10, '0')} 00000 n ");
  }
  file.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n',
  );
  return Uint8List.fromList(ascii.encode(file.toString()));
}
