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

  group('strict schema mode', () {
    test(
        'sends the same json_schema request shape as OpenAI when supportsStrictSchema is true',
        () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode(_completionBody('{"x": 1}')), 200);
      });
      final provider = OpenAiCompatibleProvider(
        baseUrl: 'http://localhost:11434/v1',
        model: 'llama3.1',
        httpClient: client,
      );

      final result = await provider.generate(
          prompt: 'Extract x', schema: schema, schemaName: 'Point');

      expect(result, '{"x": 1}');
      expect(captured!.url,
          Uri.parse('http://localhost:11434/v1/chat/completions'));
      expect(captured!.headers.containsKey('Authorization'), isFalse);
      expect(jsonDecode(captured!.body), {
        'model': 'llama3.1',
        'messages': [
          {'role': 'user', 'content': 'Extract x'},
        ],
        'response_format': {
          'type': 'json_schema',
          'json_schema': {'name': 'Point', 'schema': schema, 'strict': true},
        },
      });
    });

    test('sends an Authorization header when apiKey is set', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode(_completionBody('{"x": 1}')), 200);
      });
      final provider = OpenAiCompatibleProvider(
        baseUrl: 'https://api.groq.com/openai/v1',
        model: 'llama-3.3-70b',
        apiKey: 'gsk-test',
        httpClient: client,
      );

      await provider.generate(prompt: 'p', schema: schema, schemaName: 'Point');

      expect(captured!.headers['Authorization'], 'Bearer gsk-test');
    });
  });

  group('JSON-mode fallback', () {
    test(
        'embeds the schema in a system prompt and uses json_object mode when supportsStrictSchema is false',
        () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode(_completionBody('{"x": 1}')), 200);
      });
      final provider = OpenAiCompatibleProvider(
        baseUrl: 'http://localhost:11434/v1',
        model: 'llama3.1',
        supportsStrictSchema: false,
        httpClient: client,
      );

      await provider.generate(
          prompt: 'Extract x', schema: schema, schemaName: 'Point');

      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['response_format'], {'type': 'json_object'});
      final messages = body['messages'] as List<dynamic>;
      expect(messages, hasLength(2));
      expect(messages[0], {
        'role': 'system',
        'content': contains(jsonEncode(schema)),
      });
      expect(messages[1], {'role': 'user', 'content': 'Extract x'});
    });
  });

  group('error mapping', () {
    test('maps a refusal to a non-retryable ProviderException', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': null,
                  'refusal': 'cannot help with that'
                },
              },
            ],
          }),
          200,
        ),
      );
      final provider = OpenAiCompatibleProvider(
          baseUrl: 'http://localhost:11434/v1',
          model: 'llama3.1',
          httpClient: client);

      await expectLater(
        provider.generate(prompt: 'p', schema: schema, schemaName: 'Point'),
        throwsA(isA<ProviderException>()
            .having((e) => e.retryable, 'retryable', isFalse)),
      );
    });

    test('maps a 429 to a retryable ProviderException honoring retry-after',
        () async {
      final client = MockClient((_) async =>
          http.Response('rate limited', 429, headers: {'retry-after': '2'}));
      final provider = OpenAiCompatibleProvider(
          baseUrl: 'http://localhost:11434/v1',
          model: 'llama3.1',
          httpClient: client);

      await expectLater(
        provider.generate(prompt: 'p', schema: schema, schemaName: 'Point'),
        throwsA(
          isA<ProviderException>()
              .having((e) => e.retryable, 'retryable', isTrue)
              .having((e) => e.retryAfter, 'retryAfter',
                  const Duration(seconds: 2)),
        ),
      );
    });
  });

  test('constructs with a real http client when none is injected', () {
    // The httpClient parameter is a test seam; omitting it must still yield a
    // usable provider. No request is made here, so no network is touched.
    expect(
        OpenAiCompatibleProvider(
            baseUrl: 'http://localhost:11434/v1', model: 'llama3.1'),
        isA<LlmProvider>());
  });
}
