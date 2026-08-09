import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';

import 'exceptions.dart';
import 'providers/provider.dart';
import 'schema/validator.dart';

/// Tuning knobs for [Extractor].
@immutable
final class ExtractorConfig {
  /// Creates an extractor configuration.
  const ExtractorConfig({
    this.maxValidationRetries = 1,
    this.maxHttpAttempts = 3,
    this.timeout = const Duration(seconds: 60),
  });

  /// How many times to re-prompt (with validation feedback appended) after
  /// malformed JSON or a schema violation, before giving up. `1` (the
  /// default) means one retry after the first failure.
  final int maxValidationRetries;

  /// The total number of attempts (including the first) for a single
  /// provider call before giving up on a retryable HTTP failure (`429` or
  /// `5xx`), with exponential backoff between attempts.
  final int maxHttpAttempts;

  /// How long to wait for a single provider call before throwing
  /// [ExtractionTimeoutException].
  final Duration timeout;
}

/// Extracts a typed, schema-validated object of type `T` from an LLM
/// provider's structured output.
///
/// ```dart
/// final extractor = Extractor(provider: OpenAiProvider(apiKey: apiKey));
/// final invoice = await extractor.extract<Invoice>(
///   prompt: 'Extract the invoice from this text: ...',
///   schema: InvoiceSchema,
///   fromJson: Invoice.fromValidatedJson,
/// );
/// ```
///
/// On malformed JSON or a schema violation, retries once by default with
/// the validation errors appended to the prompt (configurable via
/// [ExtractorConfig.maxValidationRetries]). On a retryable HTTP failure
/// (`429`/`5xx`), retries with exponential backoff, honoring the
/// provider's `Retry-After` value when present.
final class Extractor {
  /// Creates an extractor backed by [provider].
  Extractor({
    required LlmProvider provider,
    SchemaValidator validator = const SchemaValidator(),
    ExtractorConfig config = const ExtractorConfig(),
  })  : _provider = provider,
        _validator = validator,
        _config = config;

  final LlmProvider _provider;
  final SchemaValidator _validator;
  final ExtractorConfig _config;

  /// Extracts a `T` matching [schema] from [prompt], using [fromJson] to
  /// build `T` from the validated JSON object.
  ///
  /// [fromJson] is typically a class's generated-and-wrapped constructor,
  /// e.g. `Invoice.fromValidatedJson`, which itself calls
  /// `_$InvoiceFromValidatedJson`.
  Future<T> extract<T>({
    required String prompt,
    required Map<String, dynamic> schema,
    required T Function(Map<String, dynamic> json) fromJson,
  }) async {
    final schemaName = '$T';
    var currentPrompt = prompt;

    for (var attempt = 0;; attempt++) {
      final raw =
          await _generateWithHttpRetry(currentPrompt, schema, schemaName);
      final outcome = _decodeAndValidate(raw, schema, _validator);
      if (outcome.data != null) {
        return fromJson(outcome.data!);
      }
      final failure = outcome.failure!;
      if (attempt >= _config.maxValidationRetries) {
        throw failure.toException(raw, attempt);
      }
      currentPrompt = '$prompt\n\nYour previous output failed validation: '
          '${failure.feedback}. Return corrected JSON only.';
    }
  }

  Future<String> _generateWithHttpRetry(
    String currentPrompt,
    Map<String, dynamic> schema,
    String schemaName,
  ) async {
    for (var attempt = 0;; attempt++) {
      try {
        return await _provider
            .generate(
                prompt: currentPrompt, schema: schema, schemaName: schemaName)
            .timeout(_config.timeout,
                onTimeout: () =>
                    throw ExtractionTimeoutException(timeout: _config.timeout));
      } on ProviderException catch (e) {
        if (!e.retryable || attempt >= _config.maxHttpAttempts - 1) {
          rethrow;
        }
        await Future<void>.delayed(
            e.retryAfter ?? Duration(milliseconds: 500 * (1 << attempt)));
      }
    }
  }
}

/// A retryable failure from decoding or validating a provider's raw output:
/// the [feedback] to append to the retry prompt, and how to build the
/// terminal exception if retries are exhausted.
@immutable
final class _ValidationFailure {
  const _ValidationFailure({required this.feedback, required this.toException});

  final String feedback;
  final TypedLlmException Function(String rawOutput, int retryCount)
      toException;
}

({Map<String, dynamic>? data, _ValidationFailure? failure}) _decodeAndValidate(
  String raw,
  Map<String, dynamic> schema,
  SchemaValidator validator,
) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException catch (e) {
    return (
      data: null,
      failure: _ValidationFailure(
        feedback: 'the output was not valid JSON (${e.message})',
        toException: (raw, _) =>
            MalformedJsonException(rawOutput: raw, message: e.message),
      ),
    );
  }

  if (decoded is! Map<String, dynamic>) {
    final message = 'expected a JSON object but got ${decoded.runtimeType}';
    return (
      data: null,
      failure: _ValidationFailure(
        feedback: message,
        toException: (raw, _) =>
            MalformedJsonException(rawOutput: raw, message: message),
      ),
    );
  }

  final result = validator.validate(schema, decoded);
  if (!result.isValid) {
    final feedback = result.errors.join('; ');
    return (
      data: null,
      failure: _ValidationFailure(
        feedback: feedback,
        toException: (raw, retryCount) => SchemaValidationException(
            rawOutput: raw, errors: result.errors, retryCount: retryCount),
      ),
    );
  }

  return (data: decoded, failure: null);
}
