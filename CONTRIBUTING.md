# Contributing to typed_llm

This repository is a monorepo of independent Dart packages sharing no build
tool beyond plain `dart pub get` — there's no melos or workspace file. Each
package under `packages/` is self-contained; a `dependency_overrides: {path:
...}` entry in `typed_llm_generator`'s and `example`'s `pubspec.yaml`s points
them at the sibling `typed_llm` on disk instead of a published version.

## Layout

```
packages/
  typed_llm/            # the runtime library (what gets imported by users)
  typed_llm_generator/  # the build_runner code generator (dev dependency)
  example/               # a runnable example app exercising both
analysis_options.yaml    # shared lint config, included by each package
.github/workflows/ci.yaml
```

## Working on a package

```sh
cd packages/typed_llm       # or typed_llm_generator, or example
dart pub get
dart analyze
dart test                    # example/ has no test suite; it's runnable instead
dart format .
```

Every phase of this package's development requires `dart analyze` to report
zero issues and `dart test` to be fully green before moving on — CI enforces
the same via `.github/workflows/ci.yaml`, which also runs
`dart format --output=none --set-exit-if-changed .`.

If you change `typed_llm`'s public API, run `dart pub get` again from
`typed_llm_generator` and `example` so their path-overridden dependency picks
up the change, then re-run their tests too.

## Code style

- `package:lints/recommended.yaml` plus `public_member_api_docs`,
  `prefer_final_locals`, and `unawaited_futures` (see the root
  `analysis_options.yaml`) — every public member needs a dartdoc comment.
- No `dart:mirrors`, no runtime reflection anywhere in `typed_llm`'s main
  library — schema generation happens entirely at build time.
- Before adding a new dependency to `typed_llm` or `typed_llm_generator`,
  check whether it's already justified by the package's stated minimal-
  dependency policy; if not, explain why it's needed in the PR description.
- Before writing code against an external HTTP API (a new provider, or a
  change to an existing one's request/response shape), verify the exact
  shape against that provider's current documentation and cite the source —
  don't code it from memory.

## Generated files

`*.g.dart` and `*.freezed.dart` are gitignored and excluded from analysis.
Regenerate them with:

```sh
dart run build_runner build --delete-conflicting-outputs
```

## Tests

- `typed_llm`: schema/validator unit tests, extractor tests against a
  scripted fake `LlmProvider`, and provider tests against
  `package:http/testing.dart`'s `MockClient` asserting the exact request
  body per provider.
- `typed_llm_generator`: golden tests via `package:build_test`'s
  `testBuilder`, comparing generated output against expected snippets
  (whitespace-normalized, since `dart_style` reformats generator output).
- `typed_llm/test/integration/live_extraction_test.dart`: hits real provider
  APIs with a trivial schema, for release verification. Skipped by default;
  each provider's test runs only when its key env var is set:

  ```sh
  OPENAI_API_KEY=sk-... dart test test/integration/live_extraction_test.dart
  GEMINI_API_KEY=... dart test test/integration/live_extraction_test.dart
  ANTHROPIC_API_KEY=sk-ant-... dart test test/integration/live_extraction_test.dart
  ```

  Never commit a real key, and prefer running this from your own shell
  rather than pasting a key into a chat/agent session.

## License

By contributing, you agree your contributions are licensed under this
repository's [MIT license](LICENSE).
