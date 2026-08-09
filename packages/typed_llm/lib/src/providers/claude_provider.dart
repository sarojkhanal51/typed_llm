import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import '../exceptions.dart';
import 'provider.dart';

/// An [LlmProvider] backed by Anthropic's Claude Messages API, using forced
/// tool use: a single tool whose `input_schema` is the target schema, with
/// `tool_choice` forcing that exact tool.
///
/// Request/response shape verified against
/// https://platform.claude.com/docs/en/api/messages,
/// https://platform.claude.com/docs/en/agents-and-tools/tool-use/implement-tool-use,
/// and https://platform.claude.com/docs/en/api/errors.
///
/// ```dart
/// final provider = ClaudeProvider(apiKey: apiKey, model: 'claude-opus-4-6');
/// ```
@immutable
final class ClaudeProvider implements LlmProvider {
  /// Creates a Claude provider. [apiKey] is sent as the `x-api-key` header.
  /// [maxTokens] is required by the Messages API — raise it for schemas
  /// with many or large fields. [httpClient] is exposed for testing.
  ClaudeProvider({
    required this.apiKey,
    required this.model,
    this.maxTokens = 4096,
    this.baseUrl = 'https://api.anthropic.com/v1',
    this.anthropicVersion = '2023-06-01',
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  /// The Anthropic API key, sent as the `x-api-key` header.
  final String apiKey;

  /// The model to request completions from, e.g. `claude-opus-4-6`.
  final String model;

  /// The `max_tokens` request field, required by the Messages API.
  final int maxTokens;

  /// The API base URL.
  final String baseUrl;

  /// The `anthropic-version` request header.
  final String anthropicVersion;

  final http.Client _httpClient;

  @override
  Future<String> generate({
    required String prompt,
    required Map<String, dynamic> schema,
    required String schemaName,
  }) async {
    final response = await _httpClient.post(
      Uri.parse('$baseUrl/messages'),
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': anthropicVersion,
        'Content-Type': 'application/json'
      },
      body: jsonEncode({
        'model': model,
        'max_tokens': maxTokens,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        'tools': [
          {
            'name': schemaName,
            'description': 'Extract data matching the $schemaName schema.',
            'input_schema': schema
          },
        ],
        'tool_choice': {'type': 'tool', 'name': schemaName},
      }),
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
    if (decoded['stop_reason'] == 'refusal') {
      throw ProviderException(
        statusCode: response.statusCode,
        body: jsonEncode(decoded['stop_details']),
        retryable: false,
      );
    }

    return jsonEncode(_findToolInput(decoded, response.body));
  }

  Object? _findToolInput(Map<String, dynamic> decoded, String rawBody) {
    final content = decoded['content'] as List<dynamic>;
    for (final block in content) {
      final map = block as Map<String, dynamic>;
      if (map['type'] == 'tool_use') {
        return map['input'];
      }
    }
    throw ProviderException(
        statusCode: 200,
        body: 'No tool_use content block in response: $rawBody',
        retryable: false);
  }

  Duration? _retryAfter(http.Response response) {
    final header = response.headers['retry-after'];
    final seconds = header == null ? null : int.tryParse(header);
    return seconds == null ? null : Duration(seconds: seconds);
  }
}
