## 0.1.0

Initial release.

- `JsonSchema` model and `SchemaValidator` — a provider-agnostic JSON Schema
  representation and a validator with detailed, path-qualified errors.
- `@LlmSchema()` / `@LlmField(description:, optional:)` annotations, consumed
  by the `typed_llm_generator` build_runner generator.
- `Extractor` / `ExtractorConfig` — validation-retry-with-feedback and
  HTTP-retry-with-backoff on top of any `LlmProvider`.
- `TypedLlmException` hierarchy: `SchemaValidationException`,
  `ProviderException`, `MalformedJsonException`, `ExtractionTimeoutException`.
- Providers: `OpenAiProvider` (Structured Outputs strict mode),
  `GeminiProvider` (`responseSchema`), `ClaudeProvider` (forced tool use),
  and `OpenAiCompatibleProvider` (Ollama/Groq/vLLM/etc., with a
  `supportsStrictSchema` flag falling back to JSON mode + a schema-in-prompt
  instruction).
