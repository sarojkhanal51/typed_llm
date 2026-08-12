import 'package:meta/meta.dart';

/// Everything `typed_llm` needs in order to extract a `T`: the JSON Schema to
/// send the model, and the factory that turns validated JSON back into a `T`.
///
/// `typed_llm_generator` emits one of these per `@LlmSchema()` class, named
/// `$<Class>`, so you pass a single value rather than keeping a schema and a
/// factory paired by hand:
///
/// ```dart
/// final invoice = await extractor.extract($Invoice, prompt: '...');
/// ```
///
/// Binding the schema and the factory into one `LlmType<T>` is what makes
/// [Extractor.extract] type-safe. When they were separate arguments, nothing
/// stopped you from passing one class's schema alongside another class's
/// factory: it compiled, it validated, and then it failed with a raw
/// `TypeError` at construction time. Here the two travel together and `T` is
/// inferred from them, so a mismatch cannot be expressed.
@immutable
final class LlmType<T> {
  /// Creates a schema/factory pair for [T].
  ///
  /// You normally do not call this — `typed_llm_generator` emits a `const`
  /// `$<Class>` for every `@LlmSchema()` class. Construct one by hand only
  /// when you are wiring up a type the generator does not produce, such as in
  /// a test or for a hand-written schema.
  const LlmType({
    required this.name,
    required this.schema,
    required this.fromJson,
  });

  /// The schema's name, sent to providers that require one (OpenAI names the
  /// `json_schema`; Claude names the forced tool). Generated as the Dart
  /// class's name.
  final String name;

  /// The JSON Schema describing [T], as a plain map — the same shape
  /// `JsonSchema.toMap()` returns.
  final Map<String, dynamic> schema;

  /// Builds a [T] from JSON that has already been validated against [schema].
  ///
  /// This is not responsible for validation: [Extractor] only calls it once
  /// the payload has passed [SchemaValidator], so it can cast fields
  /// directly.
  final T Function(Map<String, dynamic> json) fromJson;
}
