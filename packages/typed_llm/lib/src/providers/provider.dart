import '../exceptions.dart';

/// A backend capable of generating text constrained to a JSON Schema.
///
/// Implementations translate a prompt/schema/schemaName into a
/// provider-specific request (e.g. OpenAI's `response_format: json_schema`,
/// Gemini's `responseSchema`, or Claude's forced tool use), send it, and
/// return the raw text the model produced — the `Extractor` class handles
/// decoding, validation, and retries on top of that text.
abstract interface class LlmProvider {
  /// Requests a structured-output completion for [prompt], constrained to
  /// [schema]. [schemaName] identifies the schema (e.g. the target class
  /// name) for providers that require one, such as OpenAI.
  ///
  /// Throws a [ProviderException] on a failed HTTP call and an
  /// [ExtractionTimeoutException] if the provider does not respond within
  /// the caller's timeout.
  Future<String> generate({
    required String prompt,
    required Map<String, dynamic> schema,
    required String schemaName,
  });
}
