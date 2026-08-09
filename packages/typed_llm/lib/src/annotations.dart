/// Marks a class whose constructor parameters should be turned into a JSON
/// Schema and a validated-JSON factory by the `typed_llm_generator`
/// build_runner generator.
///
/// ```dart
/// @LlmSchema()
/// class Invoice {
///   final String vendorName;
///   final double totalAmount;
///   Invoice({required this.vendorName, required this.totalAmount});
/// }
/// ```
///
/// Requires an unnamed constructor with only named parameters — either a
/// plain generative constructor, or (for freezed classes) an unnamed
/// `const factory` constructor that redirects to the private implementation.
class LlmSchema {
  /// Marks a class for schema generation.
  const LlmSchema();
}

/// Customizes how a single constructor parameter is represented in the
/// generated JSON Schema. Apply directly to the parameter:
///
/// ```dart
/// Invoice({
///   @LlmField(description: 'The vendor issuing the invoice')
///   required this.vendorName,
/// });
/// ```
///
/// Descriptions materially improve extraction accuracy and should be set on
/// every field where the name alone is ambiguous.
class LlmField {
  /// Customizes a field's generated schema entry.
  const LlmField({this.description, this.optional = false});

  /// Emitted as the field's JSON Schema `description`.
  final String? description;

  /// Marks this field's schema type as nullable. The Dart parameter type
  /// must already be nullable (e.g. `String?`) — `typed_llm_generator`
  /// rejects `optional: true` on a non-nullable field at build time, since
  /// a `null` value could never be assigned to it.
  ///
  /// Every field is always listed in the schema's `required` array
  /// regardless of this flag: OpenAI strict mode requires every property to
  /// be required, expressing optionality through a nullable type rather
  /// than omission. A nullable Dart type (`String?`) already produces a
  /// nullable schema entry without needing this flag — set it only for
  /// explicitness.
  final bool optional;
}
