import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:typed_llm/typed_llm.dart';

Map<String, dynamic> _generateContentBody(String text) => {
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': text},
            ],
          },
        },
      ],
    };

void main() {
  const schema = {
    'type': 'object',
    'properties': {
      'x': {
        'type': ['integer', 'null'],
      },
    },
    'required': ['x'],
    'additionalProperties': false,
  };

  group('request shape', () {
    test('sends the exact Gemini generateContent request body', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode(_generateContentBody('{"x": 1}')), 200);
      });
      final provider = GeminiProvider(
          apiKey: 'gm-test', model: 'gemini-2.0-flash', httpClient: client);

      final result = await provider.generate(
          prompt: 'Extract x', schema: schema, schemaName: 'Point');

      expect(result, '{"x": 1}');
      expect(captured, isNotNull);
      expect(
        captured!.url,
        Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent'),
      );
      expect(captured!.headers['x-goog-api-key'], 'gm-test');
      expect(jsonDecode(captured!.body), {
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': 'Extract x'},
            ],
          },
        ],
        'generationConfig': {
          'responseMimeType': 'application/json',
          'responseSchema': schema
        },
      });
    });
  });

  group('response parsing', () {
    test('returns the first candidate\'s text on a 200', () async {
      final client = MockClient((_) async =>
          http.Response(jsonEncode(_generateContentBody('{"x": 42}')), 200));
      final provider = GeminiProvider(
          apiKey: 'gm-test', model: 'gemini-2.0-flash', httpClient: client);

      final result = await provider.generate(
          prompt: 'p', schema: schema, schemaName: 'Point');

      expect(result, '{"x": 42}');
    });

    test(
        'throws a non-retryable ProviderException when there are no candidates',
        () async {
      final client = MockClient((_) async =>
          http.Response(jsonEncode({'candidates': <dynamic>[]}), 200));
      final provider = GeminiProvider(
          apiKey: 'gm-test', model: 'gemini-2.0-flash', httpClient: client);

      await expectLater(
        provider.generate(prompt: 'p', schema: schema, schemaName: 'Point'),
        throwsA(isA<ProviderException>()
            .having((e) => e.retryable, 'retryable', isFalse)),
      );
    });
  });

  group('error mapping', () {
    test('maps a 429 to a retryable ProviderException', () async {
      final client = MockClient(
        (_) async => http.Response(
            jsonEncode({
              'error': {'code': 429, 'message': 'rate limited'}
            }),
            429),
      );
      final provider = GeminiProvider(
          apiKey: 'gm-test', model: 'gemini-2.0-flash', httpClient: client);

      await expectLater(
        provider.generate(prompt: 'p', schema: schema, schemaName: 'Point'),
        throwsA(
          isA<ProviderException>()
              .having((e) => e.statusCode, 'statusCode', 429)
              .having((e) => e.retryable, 'retryable', isTrue),
        ),
      );
    });

    test('maps a 400 to a non-retryable ProviderException', () async {
      final client = MockClient(
        (_) async => http.Response(
            jsonEncode({
              'error': {'code': 400, 'message': 'bad request'}
            }),
            400),
      );
      final provider = GeminiProvider(
          apiKey: 'gm-test', model: 'gemini-2.0-flash', httpClient: client);

      await expectLater(
        provider.generate(prompt: 'p', schema: schema, schemaName: 'Point'),
        throwsA(isA<ProviderException>()
            .having((e) => e.retryable, 'retryable', isFalse)),
      );
    });

    test('maps a 503 to a retryable ProviderException', () async {
      final client = MockClient(
        (_) async => http.Response(
            jsonEncode({
              'error': {'code': 503, 'message': 'unavailable'}
            }),
            503),
      );
      final provider = GeminiProvider(
          apiKey: 'gm-test', model: 'gemini-2.0-flash', httpClient: client);

      await expectLater(
        provider.generate(prompt: 'p', schema: schema, schemaName: 'Point'),
        throwsA(isA<ProviderException>()
            .having((e) => e.retryable, 'retryable', isTrue)),
      );
    });
  });

  test('constructs with a real http client when none is injected', () {
    // The httpClient parameter is a test seam; omitting it must still yield a
    // usable provider. No request is made here, so no network is touched.
    expect(GeminiProvider(apiKey: 'k', model: 'gemini-2.0-flash'),
        isA<LlmProvider>());
  });
}
