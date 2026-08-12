/// Type-safe, validated, structured output from LLM providers — no
/// `dart:mirrors`, no runtime reflection.
///
/// Annotate a class with [LlmSchema], run `build_runner`, and pass the
/// generated `$<Class>` constant to [Extractor.extract]:
///
/// ```dart
/// final extractor = Extractor(provider: OpenAiProvider(apiKey: apiKey));
/// final invoice = await extractor.extract($Invoice, prompt: '...');
/// ```
///
/// This library provides the [LlmSchema]/[LlmField] annotations the
/// `typed_llm_generator` build_runner generator consumes, the [LlmType]
/// schema/factory pair it emits, the provider-agnostic [JsonSchema] model and
/// [SchemaValidator], the [Extractor] itself, and the OpenAI, Gemini, Claude,
/// and OpenAI-compatible providers.
library;

export 'src/annotations.dart';
export 'src/exceptions.dart';
export 'src/extractor.dart';
export 'src/llm_type.dart';
export 'src/providers/claude_provider.dart';
export 'src/providers/gemini_provider.dart';
export 'src/providers/openai_compatible_provider.dart';
export 'src/providers/openai_provider.dart';
export 'src/providers/provider.dart';
export 'src/schema/json_schema.dart';
export 'src/schema/validator.dart';
