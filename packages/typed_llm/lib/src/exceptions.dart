import 'package:meta/meta.dart';

import 'schema/validator.dart';

/// The base type for every exception `typed_llm` throws.
///
/// ```dart
/// try {
///   final invoice = await extractor.extract<Invoice>(...);
/// } on TypedLlmException catch (e) {
///   switch (e) {
///     case SchemaValidationException():
///       // the model's final attempt still failed validation
///     case MalformedJsonException():
///       // the model's final attempt still wasn't valid JSON
///     case ProviderException():
///       // the HTTP call to the provider failed
///     case ExtractionTimeoutException():
///       // the provider didn't respond in time
///   }
/// }
/// ```
@immutable
sealed class TypedLlmException implements Exception {
  const TypedLlmException();
}

/// Thrown when the model's final attempt produced valid JSON that still
/// fails schema validation, after [retryCount] validation retries.
@immutable
final class SchemaValidationException extends TypedLlmException {
  /// Creates a schema validation exception.
  const SchemaValidationException({
    required this.rawOutput,
    required this.errors,
    required this.retryCount,
  });

  /// The raw text the model returned.
  final String rawOutput;

  /// Every schema violation found in the final attempt.
  final List<ValidationError> errors;

  /// How many validation retries were attempted before giving up.
  final int retryCount;

  @override
  String toString() => 'SchemaValidationException: ${errors.join('; ')} '
      '(after $retryCount ${retryCount == 1 ? 'retry' : 'retries'})';
}

/// Thrown when a provider's HTTP call fails.
@immutable
final class ProviderException extends TypedLlmException {
  /// Creates a provider exception.
  const ProviderException({
    required this.statusCode,
    required this.body,
    required this.retryable,
    this.retryAfter,
  });

  /// The HTTP status code returned by the provider.
  final int statusCode;

  /// The raw response body returned by the provider, for diagnostics.
  final String body;

  /// Whether this failure is safe to retry (e.g. `429`/`5xx`), as opposed to
  /// a client error (e.g. `401`/`400`) that will fail again identically.
  final bool retryable;

  /// The provider's `Retry-After` value, if it sent one.
  final Duration? retryAfter;

  @override
  String toString() =>
      'ProviderException($statusCode, retryable: $retryable): $body';
}

/// Thrown when the model's final attempt did not produce syntactically
/// valid JSON, after the configured number of validation retries.
@immutable
final class MalformedJsonException extends TypedLlmException {
  /// Creates a malformed-JSON exception.
  const MalformedJsonException(
      {required this.rawOutput, required this.message});

  /// The raw text the model returned.
  final String rawOutput;

  /// A description of why [rawOutput] could not be parsed as JSON.
  final String message;

  @override
  String toString() => 'MalformedJsonException: $message';
}

/// Thrown when a provider does not respond within
/// [ExtractorConfig.timeout].
@immutable
final class ExtractionTimeoutException extends TypedLlmException {
  /// Creates an extraction timeout exception.
  const ExtractionTimeoutException({required this.timeout});

  /// The configured timeout that was exceeded.
  final Duration timeout;

  @override
  String toString() =>
      'ExtractionTimeoutException: no response within $timeout';
}
