import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:typed_llm/typed_llm.dart';

Map<String, dynamic> _completionBody(String content) => {
      'choices': [
        {
          'message': {'content': content, 'refusal': null},
        },
      ],
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
    test('sends the exact OpenAI structured-outputs request body', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode(_completionBody('{"x": 1}')), 200);
      });
      final provider = OpenAiProvider(
          apiKey: 'sk-test', model: 'gpt-4o-2024-08-06', httpClient: client);

      final result = await provider.generate(
          prompt: 'Extract x', schema: schema, schemaName: 'Point');

      expect(result, '{"x": 1}');
      expect(captured, isNotNull);
      expect(captured!.url,
          Uri.parse('https://api.openai.com/v1/chat/completions'));
      expect(captured!.headers['Authorization'], 'Bearer sk-test');
      expect(captured!.headers['Content-Type'], contains('application/json'));
      expect(jsonDecode(captured!.body), {
        'model': 'gpt-4o-2024-08-06',
        'messages': [
          {'role': 'user', 'content': 'Extract x'},
        ],
        'response_format': {
          'type': 'json_schema',
          'json_schema': {'name': 'Point', 'schema': schema, 'strict': true},
        },
      });
    });

    test('honors a custom baseUrl for OpenAI-compatible proxies', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode(_completionBody('{"x": 1}')), 200);
      });
      final provider = OpenAiProvider(
        apiKey: 'sk-test',
        model: 'gpt-4o-2024-08-06',
        baseUrl: 'https://proxy.example.com/v1',
        httpClient: client,
      );

      await provider.generate(prompt: 'p', schema: schema, schemaName: 'Point');

      expect(captured!.url,
          Uri.parse('https://proxy.example.com/v1/chat/completions'));
    });
  });

  group('response parsing', () {
    test('returns the message content on a 200', () async {
      final client = MockClient((_) async =>
          http.Response(jsonEncode(_completionBody('{"x": 42}')), 200));
      final provider = OpenAiProvider(
          apiKey: 'sk-test', model: 'gpt-4o-2024-08-06', httpClient: client);

      final result = await provider.generate(
          prompt: 'p', schema: schema, schemaName: 'Point');

      expect(result, '{"x": 42}');
    });

    test('throws a non-retryable ProviderException on a refusal', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': null,
                  'refusal': 'I cannot help with that.'
                },
              },
            ],
          }),
          200,
        ),
      );
      final provider = OpenAiProvider(
          apiKey: 'sk-test', model: 'gpt-4o-2024-08-06', httpClient: client);

      await expectLater(
        provider.generate(prompt: 'p', schema: schema, schemaName: 'Point'),
        throwsA(
          isA<ProviderException>()
              .having((e) => e.retryable, 'retryable', isFalse)
              .having((e) => e.body, 'body', 'I cannot help with that.'),
        ),
      );
    });
  });

  group('error mapping', () {
    test('maps a 429 to a retryable ProviderException honoring Retry-After',
        () async {
      final client = MockClient(
        (_) async => http.Response('{"error": "rate limited"}', 429,
            headers: {'retry-after': '7'}),
      );
      final provider = OpenAiProvider(
          apiKey: 'sk-test', model: 'gpt-4o-2024-08-06', httpClient: client);

      await expectLater(
        provider.generate(prompt: 'p', schema: schema, schemaName: 'Point'),
        throwsA(
          isA<ProviderException>()
              .having((e) => e.statusCode, 'statusCode', 429)
              .having((e) => e.retryable, 'retryable', isTrue)
              .having((e) => e.retryAfter, 'retryAfter',
                  const Duration(seconds: 7)),
        ),
      );
    });

    test('maps a 401 to a non-retryable ProviderException', () async {
      final client = MockClient(
          (_) async => http.Response('{"error": "invalid api key"}', 401));
      final provider = OpenAiProvider(
          apiKey: 'sk-bad', model: 'gpt-4o-2024-08-06', httpClient: client);

      await expectLater(
        provider.generate(prompt: 'p', schema: schema, schemaName: 'Point'),
        throwsA(
          isA<ProviderException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.retryable, 'retryable', isFalse),
        ),
      );
    });

    test('maps a 503 to a retryable ProviderException', () async {
      final client = MockClient(
          (_) async => http.Response('{"error": "unavailable"}', 503));
      final provider = OpenAiProvider(
          apiKey: 'sk-test', model: 'gpt-4o-2024-08-06', httpClient: client);

      await expectLater(
        provider.generate(prompt: 'p', schema: schema, schemaName: 'Point'),
        throwsA(isA<ProviderException>()
            .having((e) => e.retryable, 'retryable', isTrue)),
      );
    });
  });
}
