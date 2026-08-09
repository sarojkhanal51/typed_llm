import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'openai_compatible_provider.dart';
import 'provider.dart';

/// An [LlmProvider] backed by OpenAI's Chat Completions API, using
/// Structured Outputs (`response_format: {type: "json_schema", ...,
/// strict: true}`).
///
/// Request/response shape verified against
/// https://platform.openai.com/docs/guides/structured-outputs and
/// https://platform.openai.com/docs/api-reference/chat/create. A thin,
/// pinned wrapper around [OpenAiCompatibleProvider] with strict schema
/// support always on.
///
/// ```dart
/// final provider = OpenAiProvider(apiKey: apiKey, model: 'gpt-4o-2024-08-06');
/// final extractor = Extractor(provider: provider);
/// ```
///
/// Shipping an API key inside a client app (mobile/web/desktop) is
/// insecure — anyone can extract it from the compiled binary or network
/// traffic. Prefer calling your own thin backend proxy that holds the key
/// server-side and forwards requests to OpenAI; see the package README for
/// both patterns.
@immutable
final class OpenAiProvider implements LlmProvider {
  /// Creates an OpenAI provider.
  ///
  /// [apiKey] is sent as a `Bearer` token. [model] must support Structured
  /// Outputs strict mode — check OpenAI's current model list, as this
  /// support is model-specific and changes over time. [httpClient] is
  /// exposed for testing — pass a `package:http/testing.dart` `MockClient`
  /// to avoid real network calls.
  OpenAiProvider(
      {required this.apiKey,
      required this.model,
      this.baseUrl = 'https://api.openai.com/v1',
      http.Client? httpClient})
      : _delegate = OpenAiCompatibleProvider(
          baseUrl: baseUrl,
          model: model,
          apiKey: apiKey,
          httpClient: httpClient,
        );

  /// The OpenAI API key, sent as `Authorization: Bearer <apiKey>`.
  final String apiKey;

  /// The model to request completions from. Must support Structured
  /// Outputs strict mode.
  final String model;

  /// The API base URL. Overridable for OpenAI-compatible proxies that
  /// mirror this exact request/response shape.
  final String baseUrl;

  final OpenAiCompatibleProvider _delegate;

  @override
  Future<String> generate(
          {required String prompt,
          required Map<String, dynamic> schema,
          required String schemaName}) =>
      _delegate.generate(
          prompt: prompt, schema: schema, schemaName: schemaName);
}
