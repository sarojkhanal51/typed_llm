## 0.1.3

Documentation only — no functional or API changes.

### Fixed

- The CI badge in the README pointed at a `REPLACE_WITH_ORG` placeholder
  instead of the real repository, so it rendered broken on pub.dev.

### Changed

- The setup snippet now shows the current `typed_llm` version, and states
  the SDK split: `typed_llm` runs on Dart 3.4+, while `typed_llm_generator`
  needs Dart 3.9+ as a dev-time dependency.

### Note

`typed_llm_generator` is published as of this release. Earlier versions of
this README instructed adding it as a dev dependency while it was not yet on
pub.dev, which made the documented setup unresolvable.

## 0.1.2

- Add a "How it works" workflow diagram to the README (build-time codegen
  vs. runtime extraction, including the validation-retry loop).

## 0.1.1

- Shorten the package `description` to fit pub.dev's 60–180 character
  scoring guideline (no functional changes).

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
