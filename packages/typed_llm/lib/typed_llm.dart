/// Type-safe, validated, structured output from LLM providers.
///
/// This is Phase 4 of the package: the provider-agnostic [JsonSchema] model,
/// [SchemaValidator], the [LlmSchema]/[LlmField] annotations consumed by the
/// `typed_llm_generator` build_runner generator, the [Extractor], and the
/// OpenAI, Gemini, Claude, and OpenAI-compatible providers. The example app,
/// README, and dartdoc pass land in the final phase.
library;

export 'src/annotations.dart';
export 'src/exceptions.dart';
export 'src/extractor.dart';
export 'src/providers/claude_provider.dart';
export 'src/providers/gemini_provider.dart';
export 'src/providers/openai_compatible_provider.dart';
export 'src/providers/openai_provider.dart';
export 'src/providers/provider.dart';
export 'src/schema/json_schema.dart';
export 'src/schema/validator.dart';
