# Contributing to typed_llm

This repository is a monorepo of independent Dart packages sharing no build
tool beyond plain `dart pub get` — there's no melos or workspace file. Each
package under `packages/` is self-contained, and each points at the sibling
`typed_llm` on disk instead of a published version:

- `typed_llm_generator` does this in a gitignored `pubspec_overrides.yaml`.
  It must **not** move back into `pubspec.yaml`: a `dependency_overrides`
  block there is flagged by `dart pub publish` and ships in the archive,
  whereas `pubspec_overrides.yaml` is local-only. Recreate it after a fresh
  clone:

  ```yaml
  # packages/typed_llm_generator/pubspec_overrides.yaml
  dependency_overrides:
    typed_llm:
      path: ../typed_llm
  ```

- `example` and `example_flutter` are `publish_to: none`, so they keep a
  plain `dependency_overrides` block in their own `pubspec.yaml`.

## SDK requirements

`typed_llm` targets Dart 3.4+ and depends only on `http` and `meta`.
`typed_llm_generator` requires Dart 3.9+, because it is built on the
analyzer 2.0 element model. Keep the two floors separate — raising
`typed_llm`'s floor to match the generator's would be a breaking change for
runtime consumers who never run code generation.

The generator's `analyzer` constraint is deliberately wide
(`>=9.0.0 <15.0.0`). A generator has to co-resolve with whatever other
codegen packages — `freezed`, `json_serializable` — the user's app pins, and
a narrow range silently makes this package unusable alongside them. Before
narrowing it, resolve a scratch app that depends on both this generator and
current `freezed`.

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

CI (`.github/workflows/ci.yaml`) covers `typed_llm` and `typed_llm_generator`
only. The example apps are not in the matrix, so after any generator change
regenerate both by hand and confirm they still analyze — that is the only
end-to-end check that the builder actually runs.

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
dart run build_runner build
```

(`--delete-conflicting-outputs` was removed in current `build_runner`
versions, which now warn that the flag is ignored.)

## Tests

- `typed_llm`: schema/validator unit tests, extractor tests against a
  scripted fake `LlmProvider`, and provider tests against
  `package:http/testing.dart`'s `MockClient` asserting the exact request
  body per provider.
- `typed_llm_generator`: golden tests via `package:build_test`'s
  `testBuilder`, comparing generated output against expected snippets.
  Snippets are normalized — all whitespace stripped, plus any trailing comma
  before a closing delimiter — so a `dart_style` upgrade that changes line
  splitting or trailing-comma style doesn't break the suite. Assert on token
  content, never on exact formatting. Note that `testBuilder` does *not*
  rethrow a generator's `InvalidGenerationSourceError`; it reports it as a
  `SEVERE` log record, so error-path tests assert on `onLog` records with
  `outputs: {}`.
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
