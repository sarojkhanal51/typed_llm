import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_llm/typed_llm.dart';

final class _Point {
  const _Point(this.x, this.y);
  final int x;
  final int y;

  @override
  bool operator ==(Object other) =>
      other is _Point && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

_Point _pointFromJson(Map<String, dynamic> json) =>
    _Point(json['x'] as int, json['y'] as int);

final _pointSchema = const JsonSchema.object(
  properties: {'x': JsonSchema.integer(), 'y': JsonSchema.integer()},
  required: ['x', 'y'],
).toMap();

final class _ScriptedProvider implements LlmProvider {
  _ScriptedProvider(this._actions);
  final List<FutureOr<String> Function()> _actions;
  final List<String> prompts = [];
  var _index = 0;

  @override
  Future<String> generate({
    required String prompt,
    required Map<String, dynamic> schema,
    required String schemaName,
  }) async {
    prompts.add(prompt);
    final action = _actions[_index];
    _index++;
    return action();
  }
}

Future<_Point> _run(Extractor extractor) => extractor.extract<_Point>(
      prompt: 'Extract the point.',
      schema: _pointSchema,
      fromJson: _pointFromJson,
    );

void main() {
  group('successful extraction', () {
    test('returns the parsed object on the first attempt', () async {
      final provider = _ScriptedProvider([() => '{"x": 1, "y": 2}']);
      final extractor = Extractor(provider: provider);

      final result = await _run(extractor);

      expect(result, const _Point(1, 2));
      expect(provider.prompts, ['Extract the point.']);
    });
  });

  group('validation retry', () {
    test('retries once with feedback on a schema violation, then succeeds',
        () async {
      final provider =
          _ScriptedProvider([() => '{"x": 1}', () => '{"x": 1, "y": 2}']);
      final extractor = Extractor(provider: provider);

      final result = await _run(extractor);

      expect(result, const _Point(1, 2));
      expect(provider.prompts, hasLength(2));
      expect(provider.prompts[1],
          contains('Your previous output failed validation'));
      expect(provider.prompts[1], contains('Missing required property "y"'));
    });

    test('throws SchemaValidationException after exhausting validation retries',
        () async {
      final provider = _ScriptedProvider([() => '{"x": 1}', () => '{"x": 1}']);
      final extractor = Extractor(provider: provider);

      await expectLater(
        _run(extractor),
        throwsA(
          isA<SchemaValidationException>()
              .having((e) => e.retryCount, 'retryCount', 1)
              .having((e) => e.errors, 'errors', isNotEmpty),
        ),
      );
      expect(provider.prompts, hasLength(2));
    });

    test('retries on malformed JSON, then succeeds', () async {
      final provider =
          _ScriptedProvider([() => 'not json', () => '{"x": 1, "y": 2}']);
      final extractor = Extractor(provider: provider);

      final result = await _run(extractor);

      expect(result, const _Point(1, 2));
      expect(provider.prompts[1], contains('not valid JSON'));
    });

    test(
        'throws MalformedJsonException immediately when maxValidationRetries is 0',
        () async {
      final provider = _ScriptedProvider([() => 'not json']);
      final extractor = Extractor(
          provider: provider,
          config: const ExtractorConfig(maxValidationRetries: 0));

      await expectLater(
          _run(extractor), throwsA(isA<MalformedJsonException>()));
      expect(provider.prompts, hasLength(1));
    });
  });

  group('HTTP retry', () {
    test('retries a retryable ProviderException, then succeeds', () async {
      var calls = 0;
      final provider = _ScriptedProvider([
        () {
          calls++;
          throw const ProviderException(
            statusCode: 429,
            body: 'rate limited',
            retryable: true,
            retryAfter: Duration(milliseconds: 1),
          );
        },
        () {
          calls++;
          return '{"x": 1, "y": 2}';
        },
      ]);
      final extractor = Extractor(provider: provider);

      final result = await _run(extractor);

      expect(result, const _Point(1, 2));
      expect(calls, 2);
    });

    test('does not retry a non-retryable ProviderException', () async {
      final provider = _ScriptedProvider([
        () => throw const ProviderException(
            statusCode: 401, body: 'unauthorized', retryable: false),
      ]);
      final extractor = Extractor(provider: provider);

      await expectLater(
        _run(extractor),
        throwsA(isA<ProviderException>()
            .having((e) => e.statusCode, 'statusCode', 401)),
      );
    });

    test('gives up after maxHttpAttempts retryable failures', () async {
      var calls = 0;
      final provider = _ScriptedProvider(
        List.generate(
          5,
          (_) => () {
            calls++;
            throw const ProviderException(
              statusCode: 503,
              body: 'unavailable',
              retryable: true,
              retryAfter: Duration(milliseconds: 1),
            );
          },
        ),
      );
      final extractor = Extractor(
          provider: provider,
          config: const ExtractorConfig(maxHttpAttempts: 3));

      await expectLater(_run(extractor), throwsA(isA<ProviderException>()));
      expect(calls, 3);
    });
  });

  group('timeout', () {
    test('throws ExtractionTimeoutException when the provider is too slow',
        () async {
      final provider = _ScriptedProvider([
        () async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          return '{"x": 1, "y": 2}';
        },
      ]);
      final extractor = Extractor(
        provider: provider,
        config: const ExtractorConfig(timeout: Duration(milliseconds: 5)),
      );

      await expectLater(
          _run(extractor), throwsA(isA<ExtractionTimeoutException>()));
    });
  });
}
