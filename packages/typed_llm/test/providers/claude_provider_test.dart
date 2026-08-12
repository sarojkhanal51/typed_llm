import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:typed_llm/typed_llm.dart';

Map<String, dynamic> _messageBody(Map<String, dynamic> toolInput) => {
      'id': 'msg_1',
      'type': 'message',
      'role': 'assistant',
      'content': [
        {
          'type': 'tool_use',
          'id': 'toolu_1',
          'name': 'Point',
          'input': toolInput
        },
      ],
      'stop_reason': 'tool_use',
    };

void main() {
  const schema = {
    'type': 'object',
    'properties': {
      'x': {'type': 'integer'},
    },
    'required': ['x'],
    'additionalProperties': false,
  };

  group('request shape', () {
    test('sends the exact Claude forced-tool-use request body', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode(_messageBody({'x': 1})), 200);
      });
      final provider = ClaudeProvider(
          apiKey: 'sk-ant-test', model: 'claude-opus-4-6', httpClient: client);

      final result = await provider.generate(
          prompt: 'Extract x', schema: schema, schemaName: 'Point');

      expect(result, '{"x":1}');
      expect(captured, isNotNull);
      expect(captured!.url, Uri.parse('https://api.anthropic.com/v1/messages'));
      expect(captured!.headers['x-api-key'], 'sk-ant-test');
      expect(captured!.headers['anthropic-version'], '2023-06-01');
      expect(jsonDecode(captured!.body), {
        'model': 'claude-opus-4-6',
        'max_tokens': 4096,
        'messages': [
          {'role': 'user', 'content': 'Extract x'},
        ],
        'tools': [
          {
            'name': 'Point',
            'description': 'Extract data matching the Point schema.',
            'input_schema': schema
          },
        ],
        'tool_choice': {'type': 'tool', 'name': 'Point'},
      });
    });

    test('honors a custom maxTokens', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode(_messageBody({'x': 1})), 200);
      });
      final provider = ClaudeProvider(
        apiKey: 'sk-ant-test',
        model: 'claude-opus-4-6',
        maxTokens: 8192,
        httpClient: client,
      );

      await provider.generate(prompt: 'p', schema: schema, schemaName: 'Point');

      expect(jsonDecode(captured!.body)['max_tokens'], 8192);
    });
  });

  group('response parsing', () {
    test('returns the tool_use input re-encoded as JSON text', () async {
      final client = MockClient(
          (_) async => http.Response(jsonEncode(_messageBody({'x': 7})), 200));
      final provider = ClaudeProvider(
          apiKey: 'sk-ant-test', model: 'claude-opus-4-6', httpClient: client);

      final result = await provider.generate(
          prompt: 'p', schema: schema, schemaName: 'Point');

      expect(jsonDecode(result), {'x': 7});
    });

    test('finds the tool_use block even after a leading text block', () async {
      final body = {
        'content': [
          {'type': 'text', 'text': "Sure, I'll extract that."},
          {
            'type': 'tool_use',
            'id': 'toolu_1',
            'name': 'Point',
            'input': {'x': 3}
          },
        ],
        'stop_reason': 'tool_use',
      };
      final client =
          MockClient((_) async => http.Response(jsonEncode(body), 200));
      final provider = ClaudeProvider(
          apiKey: 'sk-ant-test', model: 'claude-opus-4-6', httpClient: client);

      final result = await provider.generate(
          prompt: 'p', schema: schema, schemaName: 'Point');

      expect(jsonDecode(result), {'x': 3});
    });

    test('throws a non-retryable ProviderException on refusal', () async {
      final body = {
        'content': <dynamic>[],
        'stop_reason': 'refusal',
        'stop_details': {
          'type': 'refusal',
          'category': 'policy',
          'explanation': 'cannot help with that'
        },
      };
      final client =
          MockClient((_) async => http.Response(jsonEncode(body), 200));
      final provider = ClaudeProvider(
          apiKey: 'sk-ant-test', model: 'claude-opus-4-6', httpClient: client);

      await expectLater(
        provider.generate(prompt: 'p', schema: schema, schemaName: 'Point'),
        throwsA(isA<ProviderException>()
            .having((e) => e.retryable, 'retryable', isFalse)),
      );
    });

    test(
        'throws a non-retryable ProviderException when no tool_use block is present',
        () async {
      final body = {
        'content': [
          {'type': 'text', 'text': 'no tool call here'},
        ],
        'stop_reason': 'end_turn',
      };
      final client =
          MockClient((_) async => http.Response(jsonEncode(body), 200));
      final provider = ClaudeProvider(
          apiKey: 'sk-ant-test', model: 'claude-opus-4-6', httpClient: client);

      await expectLater(
        provider.generate(prompt: 'p', schema: schema, schemaName: 'Point'),
        throwsA(isA<ProviderException>()
            .having((e) => e.retryable, 'retryable', isFalse)),
      );
    });
  });

  group('error mapping', () {
    test('maps a 429 to a retryable ProviderException honoring retry-after',
        () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'type': 'error',
            'error': {'type': 'rate_limit_error', 'message': 'rate limited'},
          }),
          429,
          headers: {'retry-after': '3'},
        ),
      );
      final provider = ClaudeProvider(
          apiKey: 'sk-ant-test', model: 'claude-opus-4-6', httpClient: client);

      await expectLater(
        provider.generate(prompt: 'p', schema: schema, schemaName: 'Point'),
        throwsA(
          isA<ProviderException>()
              .having((e) => e.retryable, 'retryable', isTrue)
              .having((e) => e.retryAfter, 'retryAfter',
                  const Duration(seconds: 3)),
        ),
      );
    });

    test('maps a 529 (overloaded) to a retryable ProviderException', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'type': 'error',
            'error': {'type': 'overloaded_error', 'message': 'overloaded'},
          }),
          529,
        ),
      );
      final provider = ClaudeProvider(
          apiKey: 'sk-ant-test', model: 'claude-opus-4-6', httpClient: client);

      await expectLater(
        provider.generate(prompt: 'p', schema: schema, schemaName: 'Point'),
        throwsA(isA<ProviderException>()
            .having((e) => e.retryable, 'retryable', isTrue)),
      );
    });

    test('maps a 401 to a non-retryable ProviderException', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'type': 'error',
            'error': {
              'type': 'authentication_error',
              'message': 'invalid api key'
            },
          }),
          401,
        ),
      );
      final provider = ClaudeProvider(
          apiKey: 'sk-ant-bad', model: 'claude-opus-4-6', httpClient: client);

      await expectLater(
        provider.generate(prompt: 'p', schema: schema, schemaName: 'Point'),
        throwsA(isA<ProviderException>()
            .having((e) => e.retryable, 'retryable', isFalse)),
      );
    });
  });

  test('constructs with a real http client when none is injected', () {
    // The httpClient parameter is a test seam; omitting it must still yield a
    // usable provider. No request is made here, so no network is touched.
    expect(ClaudeProvider(apiKey: 'k', model: 'claude-sonnet-5'),
        isA<LlmProvider>());
  });
}
