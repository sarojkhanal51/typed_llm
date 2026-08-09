# typed_llm

Type-safe, validated, structured output from LLM providers for Dart —
no `dart:mirrors`, no runtime reflection.

This repository is a monorepo of independent Dart packages. **Start with
[`packages/typed_llm/README.md`](packages/typed_llm/README.md)** — that's
the actual package documentation (hero example, setup, provider matrix,
error handling, API key security, comparisons).

| Package | Purpose |
| --- | --- |
| [`packages/typed_llm`](packages/typed_llm) | The runtime library: annotations, schema model/validator, extractor, providers (OpenAI, Gemini, Claude, OpenAI-compatible). |
| [`packages/typed_llm_generator`](packages/typed_llm_generator) | The `build_runner` code generator (a dev dependency of your app, not `typed_llm` itself). |
| [`packages/example`](packages/example) | A runnable example app: annotated models (including a freezed class), the generator, and extraction. |

See [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow, and
[LICENSE](LICENSE) (MIT).
