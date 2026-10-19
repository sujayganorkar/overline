import 'dart:convert';
import '../../bridge/api.dart' as bridge;

/// Exporter that transforms native Rust operation catalogs into standard
/// LLM function calling declarations (compatible with Gemini, OpenAI, and local SLM prompt formats).
class SchemaExporter {
  const SchemaExporter._();

  /// Transforms bridge OperationInfo items into standardized LLM function calling schemas.
  static List<Map<String, dynamic>> exportToFunctionDeclarations(
    List<bridge.OperationInfo> catalog,
  ) {
    return catalog.map((op) {
      Map<String, dynamic> parsedSchema;
      try {
        parsedSchema = jsonDecode(op.inputSchemaJson) as Map<String, dynamic>;
      } catch (_) {
        parsedSchema = const <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{},
        };
      }

      // Ensure the parameters schema has type 'object' and contains valid properties & required lists
      final properties = parsedSchema['properties'] is Map<String, dynamic>
          ? parsedSchema['properties'] as Map<String, dynamic>
          : <String, dynamic>{};

      final required = parsedSchema['required'] is List
          ? (parsedSchema['required'] as List).map((e) => e.toString()).toList()
          : <String>[];

      final parameters = <String, dynamic>{
        'type': 'object',
        'properties': properties,
        if (required.isNotEmpty) 'required': required,
      };

      return <String, dynamic>{
        'name': op.id,
        'description': '${op.title}: ${op.description}',
        'parameters': parameters,
        'readOnly': op.readOnly,
        'destructive': op.destructive,
      };
    }).toList();
  }
}

