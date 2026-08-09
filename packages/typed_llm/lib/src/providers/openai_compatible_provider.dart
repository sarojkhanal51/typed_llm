import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import '../exceptions.dart';
import 'provider.dart';

/// An [LlmProvider] for any server that mirrors OpenAI's Chat Completions
/// API shape — Ollama, Groq, vLLM, LM Studio, and similar.
///
/// Some of these servers support OpenAI's strict `json_schema` structured
/// outputs; many only support plain JSON mode
/// (`response_format: {"type": "json_object"}`). Set [supportsStrictSchema]
/// based on what your server documents — this package does not feature-
/// detect it by sniffing errors, since that's fragile. When `false`, the
/// schema is embedded in a system-prompt instruction instead, which is a
/// strictly weaker guarantee: the model is not mechanically constrained to
/// it, so expect `SchemaValidationException` more often and lean on the
/// extractor's validation-retry-with-feedback loop.
///
/// `OpenAiProvider` is a thin, pinned convenience wrapper around this class
/// for `api.openai.com` itself.
@immutable
final class OpenAiCompatibleProvider implements LlmProvider {
  /// Creates a provider for an OpenAI-compatible server at [baseUrl].
  /// [apiKey] is omitted (no `Authorization` header sent) for local servers
  /// that don't require one. [httpClient] is exposed for testing.
  OpenAiCompatibleProvider({
    required this.baseUrl,
    required this.model,
    this.apiKey,
    this.supportsStrictSchema = true,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  /// The server's base URL, e.g. `http://localhost:11434/v1` for Ollama.
  final String baseUrl;

  /// The model to request completions from.
  final String model;

  /// Sent as `Authorization: Bearer <apiKey>` when non-null.
  final String? apiKey;

  /// Whether the server supports OpenAI's strict `json_schema` structured
  /// outputs. When `false`, falls back to JSON mode with the schema
  /// embedded in a system prompt instead.
  final bool supportsStrictSchema;

  final http.Client _httpClient;

  @override
  Future<String> generate({
    required String prompt,
    required Map<String, dynamic> schema,
    required String schemaName,
  }) async {
    final response = await _httpClient.post(
      Uri.parse('$baseUrl/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        if (apiKey != null) 'Authorization': 'Bearer $apiKey'
      },
      body: jsonEncode(_requestBody(prompt, schema, schemaName)),
    );

    if (response.statusCode != 200) {
      throw ProviderException(
        statusCode: response.statusCode,
        body: response.body,
        retryable: response.statusCode == 429 || response.statusCode >= 500,
        retryAfter: _retryAfter(response),
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'] as List<dynamic>;
    final message = (choices.first as Map<String, dynamic>)['message']
        as Map<String, dynamic>;

    final refusal = message['refusal'] as String?;
    if (refusal != null) {
      throw ProviderException(
          statusCode: response.statusCode, body: refusal, retryable: false);
    }

    return message['content'] as String;
  }

  Map<String, dynamic> _requestBody(
      String prompt, Map<String, dynamic> schema, String schemaName) {
    if (supportsStrictSchema) {
      return {
        'model': model,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        'response_format': {
          'type': 'json_schema',
          'json_schema': {'name': schemaName, 'schema': schema, 'strict': true},
        },
      };
    }
    return {
      'model': model,
      'messages': [
        {
          'role': 'system',
          'content':
              'Respond with a single JSON object matching this JSON Schema '
                  'exactly, with no other text:\n\n${jsonEncode(schema)}',
        },
        {'role': 'user', 'content': prompt},
      ],
      'response_format': {'type': 'json_object'},
    };
  }

  Duration? _retryAfter(http.Response response) {
    final header = response.headers['retry-after'];
    final seconds = header == null ? null : int.tryParse(header);
    return seconds == null ? null : Duration(seconds: seconds);
  }
}
