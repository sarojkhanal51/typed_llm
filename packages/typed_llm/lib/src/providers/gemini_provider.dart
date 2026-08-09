import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import '../exceptions.dart';
import 'provider.dart';

/// An [LlmProvider] backed by Google's Gemini API, using
/// `generationConfig.responseMimeType: "application/json"` and
/// `responseSchema`.
///
/// Request/response shape verified against
/// https://ai.google.dev/api/generate-content and
/// https://ai.google.dev/gemini-api/docs/structured-output. As of that
/// verification, Gemini documents its schema as "a subset of JSON Schema"
/// that supports `additionalProperties` and nullable `"type": [..., "null"]`
/// arrays natively — different from older, widely-cited docs describing an
/// OpenAPI-only dialect requiring a separate `nullable: true` keyword. This
/// provider currently passes the schema through unchanged via
/// [_sanitizeSchema]; if a real response indicates Gemini rejects some
/// construct, that is the place to add down-conversion.
///
/// ```dart
/// final provider = GeminiProvider(apiKey: apiKey, model: 'gemini-2.0-flash');
/// ```
@immutable
final class GeminiProvider implements LlmProvider {
  /// Creates a Gemini provider. [apiKey] is sent as the `x-goog-api-key`
  /// header (preferred over the `?key=` query parameter, which leaks the
  /// key into URLs/logs). [httpClient] is exposed for testing.
  GeminiProvider({
    required this.apiKey,
    required this.model,
    this.baseUrl = 'https://generativelanguage.googleapis.com/v1beta',
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  /// The Gemini API key, sent as the `x-goog-api-key` header.
  final String apiKey;

  /// The model to request completions from, e.g. `gemini-2.0-flash`.
  final String model;

  /// The API base URL.
  final String baseUrl;

  final http.Client _httpClient;

  @override
  Future<String> generate({
    required String prompt,
    required Map<String, dynamic> schema,
    required String schemaName,
  }) async {
    final response = await _httpClient.post(
      Uri.parse('$baseUrl/models/$model:generateContent'),
      headers: {'x-goog-api-key': apiKey, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': prompt},
            ],
          },
        ],
        'generationConfig': {
          'responseMimeType': 'application/json',
          'responseSchema': _sanitizeSchema(schema)
        },
      }),
    );

    if (response.statusCode != 200) {
      throw ProviderException(
        statusCode: response.statusCode,
        body: response.body,
        retryable: response.statusCode == 429 || response.statusCode >= 500,
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = decoded['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      throw ProviderException(
        statusCode: response.statusCode,
        body:
            'Gemini returned no candidates (the prompt may have been blocked; '
            'see promptFeedback in the raw response): ${response.body}',
        retryable: false,
      );
    }

    final content = (candidates.first as Map<String, dynamic>)['content']
        as Map<String, dynamic>;
    final parts = content['parts'] as List<dynamic>;
    return (parts.first as Map<String, dynamic>)['text'] as String;
  }

  /// Currently the identity function — see the class-level doc comment.
  Map<String, dynamic> _sanitizeSchema(Map<String, dynamic> schema) => schema;
}
