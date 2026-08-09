import 'package:meta/meta.dart';

/// Validates decoded JSON data (the result of `jsonDecode`) against a raw
/// JSON Schema map — the same shape emitted by the `typed_llm_generator`
/// build_runner generator and returned by [JsonSchema.toMap].
///
/// ```dart
/// const validator = SchemaValidator();
/// final result = validator.validate(schema.toMap(), decodedJson);
/// if (!result.isValid) {
///   throw SchemaValidationException(errors: result.errors, ...);
/// }
/// ```
///
/// Supports the subset of JSON Schema this package's schema model emits:
/// `type` (string or nullable array form), `properties`/`required`/
/// `additionalProperties` for objects, `items` for arrays, and `format`/
/// `enum` for strings. Never throws on invalid input data — validity is
/// reported via [ValidationResult].
@immutable
final class SchemaValidator {
  /// Creates a schema validator. Stateless and safe to reuse/share.
  const SchemaValidator();

  /// Validates [data] against [schema], returning every violation found
  /// (not just the first).
  ValidationResult validate(Map<String, dynamic> schema, Object? data) {
    final errors = <ValidationError>[];
    _validateNode(schema, data, '', errors);
    return ValidationResult(errors: errors);
  }
}

void _validateNode(
  Map<String, dynamic> schema,
  Object? data,
  String path,
  List<ValidationError> errors,
) {
  final types = _typesOf(schema);
  if (data == null) {
    if (!types.contains('null')) {
      errors.add(
        ValidationError(
          path: path,
          message: 'Expected ${_describeTypes(types)} but got null',
          kind: ValidationErrorKind.typeMismatch,
        ),
      );
    }
    return;
  }

  final nonNullTypes = types.where((type) => type != 'null');
  final matchedType = nonNullTypes.where((type) => _matchesType(type, data));
  if (matchedType.isEmpty) {
    errors.add(
      ValidationError(
        path: path,
        message: 'Expected ${_describeTypes(types)} but got '
            '${data.runtimeType}',
        kind: ValidationErrorKind.typeMismatch,
      ),
    );
    return;
  }

  switch (matchedType.first) {
    case 'string':
      _validateString(schema, data as String, path, errors);
    case 'object':
      _validateObject(schema, data as Map<Object?, Object?>, path, errors);
    case 'array':
      _validateArray(schema, data as List<Object?>, path, errors);
  }
}

List<String> _typesOf(Map<String, dynamic> schema) {
  final type = schema['type'];
  return type is List ? type.cast<String>() : <String>[type as String];
}

String _describeTypes(List<String> types) =>
    types.length == 1 ? types.single : types.join(' or ');

bool _matchesType(String type, Object value) {
  return switch (type) {
    'string' => value is String,
    'boolean' => value is bool,
    'integer' =>
      value is int || (value is double && value == value.roundToDouble()),
    'number' => value is int || value is double,
    'array' => value is List,
    'object' => value is Map,
    _ => false,
  };
}

void _validateString(
  Map<String, dynamic> schema,
  String value,
  String path,
  List<ValidationError> errors,
) {
  final format = schema['format'] as String?;
  if (format == 'date-time' && DateTime.tryParse(value) == null) {
    errors.add(
      ValidationError(
        path: path,
        message: '"$value" is not a valid ISO-8601 date-time string',
        kind: ValidationErrorKind.invalidFormat,
      ),
    );
  }

  final enumValues = (schema['enum'] as List<dynamic>?)?.cast<String>();
  if (enumValues != null && !enumValues.contains(value)) {
    errors.add(
      ValidationError(
        path: path,
        message: '"$value" is not one of the allowed values: $enumValues',
        kind: ValidationErrorKind.unknownEnumValue,
      ),
    );
  }
}

void _validateObject(
  Map<String, dynamic> schema,
  Map<Object?, Object?> data,
  String path,
  List<ValidationError> errors,
) {
  final properties =
      (schema['properties'] as Map<String, dynamic>?) ?? const {};
  final required =
      (schema['required'] as List<dynamic>?)?.cast<String>() ?? const [];
  final additionalProperties = schema['additionalProperties'] as bool? ?? true;

  for (final key in required) {
    if (!data.containsKey(key)) {
      errors.add(
        ValidationError(
          path: '$path/$key',
          message: 'Missing required property "$key"',
          kind: ValidationErrorKind.missingRequiredProperty,
        ),
      );
    }
  }

  for (final entry in data.entries) {
    final key = entry.key as String;
    final propertySchema = properties[key] as Map<String, dynamic>?;
    if (propertySchema == null) {
      if (!additionalProperties) {
        errors.add(
          ValidationError(
            path: '$path/$key',
            message: 'Property "$key" is not allowed by this schema',
            kind: ValidationErrorKind.additionalPropertyNotAllowed,
          ),
        );
      }
      continue;
    }
    _validateNode(propertySchema, entry.value, '$path/$key', errors);
  }
}

void _validateArray(
  Map<String, dynamic> schema,
  List<Object?> data,
  String path,
  List<ValidationError> errors,
) {
  final items = schema['items'] as Map<String, dynamic>?;
  if (items == null) {
    return;
  }
  for (var i = 0; i < data.length; i++) {
    _validateNode(items, data[i], '$path/$i', errors);
  }
}

/// The outcome of [SchemaValidator.validate]: either no [errors] (valid) or
/// one [ValidationError] per violation found.
@immutable
final class ValidationResult {
  /// Creates a validation result. Prefer [SchemaValidator.validate] over
  /// constructing this directly.
  const ValidationResult({required this.errors});

  /// Every violation found, in traversal order. Empty when the data is
  /// valid.
  final List<ValidationError> errors;

  /// Whether [errors] is empty.
  bool get isValid => errors.isEmpty;
}

/// A single schema violation found by [SchemaValidator.validate].
@immutable
final class ValidationError {
  /// Creates a validation error.
  const ValidationError({
    required this.path,
    required this.message,
    required this.kind,
  });

  /// A JSON-Pointer-style path to the offending value, e.g.
  /// `/items/0/dueDate`. Empty string means the root value itself.
  final String path;

  /// A human-readable description of the violation, suitable for including
  /// in a retry prompt.
  final String message;

  /// The category of violation; useful for programmatic handling.
  final ValidationErrorKind kind;

  @override
  String toString() => '${path.isEmpty ? '<root>' : path}: $message';
}

/// Categories of schema violation a [SchemaValidator] can report.
enum ValidationErrorKind {
  /// The value's JSON type does not match any type allowed by the schema.
  typeMismatch,

  /// An object is missing a property listed in the schema's `required`.
  missingRequiredProperty,

  /// A string value is not one of the schema's `enum` values.
  unknownEnumValue,

  /// A string value does not match its schema `format` (e.g. `date-time`).
  invalidFormat,

  /// An object has a property not declared in `properties`, and the schema
  /// sets `additionalProperties: false`.
  additionalPropertyNotAllowed,
}
