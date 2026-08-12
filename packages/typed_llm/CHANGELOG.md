## 0.2.1

Test-only release: no API, behaviour, or dependency changes. Nothing in
`lib/` differs from 0.2.0, so upgrading is optional.

- Line coverage 93.7% -> 100%, via tests for paths that had none:
  - Every `TypedLlmException` `toString()`, including the singular/plural
    branch in `SchemaValidationException` ("after 1 retry" vs "after 2
    retries"). These strings are often all a developer sees in a crash
    report, so they are now pinned.
  - A model returning a top-level JSON *array* or scalar instead of an
    object. Models routinely wrap a single result in `[...]`; this now has a
    regression test asserting it surfaces as `MalformedJsonException`, and
    that the retry prompt tells the model an object was expected.
  - `LlmField`'s defaults, which the generator reads when emitting schemas.
  - Constructing a provider without the `httpClient` test seam.

## 0.2.0

**Breaking:** `Extractor.extract` now takes a single generated `LlmType<T>`
instead of separate `schema:` and `fromJson:` arguments.

### Why

The old signature let the schema and the factory disagree. Nothing tied
`schema:`, `fromJson:`, and `T` together, so this compiled and validated
cleanly, then failed at construction with a raw `TypeError` — not the
`TypedLlmException` this package promises:

```dart
await extractor.extract<Invoice>(
  prompt: '...',
  schema: ReceiptSchema,                  // wrong schema
  fromJson: Invoice.fromValidatedJson,
);
```

Binding both into one `LlmType<T>` makes that unrepresentable, and lets `T`
be inferred rather than written out.

### Migrating

The generator now emits `$<Class>` for every `@LlmSchema()` class:

```dart
// before
final invoice = await extractor.extract<Invoice>(
  prompt: '...',
  schema: InvoiceSchema,
  fromJson: Invoice.fromValidatedJson,
);

// after
final invoice = await extractor.extract($Invoice, prompt: '...');
```

The hand-written `fromValidatedJson` wrapper is no longer needed — `$Invoice`
references the generated factory directly. Delete it; keeping it is harmless.
Requires `typed_llm_generator` 0.2.0, and a `build_runner` re-run.

### Added

- `LlmType<T>` — binds a JSON Schema to the factory that rebuilds `T`, plus
  the schema `name` sent to providers that need one. The generator emits a
  `const` instance per annotated class; construct one by hand for
  hand-written schemas (see `example/main.dart`).

### Changed

- The provider-facing schema name now comes from `LlmType.name` (the Dart
  class's name, captured at build time) rather than from `'$T'` at runtime.
- `InvoiceSchema` is still generated, unchanged, for callers that want the
  raw JSON Schema map.

### Fixed

- The library-level dartdoc described the package as "Phase 4" and referred
  to work "landing in the final phase" — internal development language that
  was published to pub.dev.

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
