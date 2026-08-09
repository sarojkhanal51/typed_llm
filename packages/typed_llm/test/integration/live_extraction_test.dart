// Hits real provider APIs with a trivial schema. Skipped by default; each
// group runs only when its provider's API key environment variable is set.
// For release verification, e.g.:
//   OPENAI_API_KEY=sk-... dart test test/integration/live_extraction_test.dart
import 'dart:io';

import 'package:test/test.dart';
import 'package:typed_llm/typed_llm.dart';

final class _CapitalFact {
  _CapitalFact({required this.country, required this.capital});
  final String country;
  final String capital;
}

_CapitalFact _capitalFactFromJson(Map<String, dynamic> json) => _CapitalFact(
    country: json['country'] as String, capital: json['capital'] as String);

final _capitalFactSchema = const JsonSchema.object(
  properties: {
    'country': JsonSchema.string(description: 'The country name'),
    'capital': JsonSchema.string(description: "The country's capital city"),
  },
  required: ['country', 'capital'],
).toMap();

const _prompt =
    'What is the capital of France? Respond with the country and its capital.';

Future<void> _expectParisFact(Extractor extractor) async {
  final fact = await extractor.extract<_CapitalFact>(
    prompt: _prompt,
    schema: _capitalFactSchema,
    fromJson: _capitalFactFromJson,
  );

  expect(fact.country.toLowerCase(), contains('france'));
  expect(fact.capital.toLowerCase(), contains('paris'));
}

void main() {
  final openAiKey = Platform.environment['OPENAI_API_KEY'];
  test(
    'OpenAI: extracts a trivial fact from a real completion',
    () => _expectParisFact(Extractor(
        provider: OpenAiProvider(
            apiKey: openAiKey ?? '', model: 'gpt-4o-2024-08-06'))),
    skip: openAiKey == null ? 'Set OPENAI_API_KEY to run this test' : false,
  );

  final geminiKey = Platform.environment['GEMINI_API_KEY'];
  test(
    'Gemini: extracts a trivial fact from a real completion',
    () => _expectParisFact(Extractor(
        provider: GeminiProvider(
            apiKey: geminiKey ?? '', model: 'gemini-2.0-flash'))),
    skip: geminiKey == null ? 'Set GEMINI_API_KEY to run this test' : false,
  );

  final anthropicKey = Platform.environment['ANTHROPIC_API_KEY'];
  test(
    'Claude: extracts a trivial fact from a real completion',
    () => _expectParisFact(Extractor(
        provider: ClaudeProvider(
            apiKey: anthropicKey ?? '', model: 'claude-opus-4-6'))),
    skip:
        anthropicKey == null ? 'Set ANTHROPIC_API_KEY to run this test' : false,
  );
}
