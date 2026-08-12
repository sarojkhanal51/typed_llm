# typed_llm example

A runnable example demonstrating the full `typed_llm` workflow:

- `lib/models.dart` — `Invoice` (nested `LineItem`, an enum, a `DateTime`,
  a `List<T>`, and an `@LlmField(description:)`) and `ShippingAddress` (a
  [freezed](https://pub.dev/packages/freezed) class also annotated with
  `@LlmSchema()`, showing the generator reads freezed's redirecting
  `const factory` constructor).
- `bin/main.dart` — builds an `Extractor` with `OpenAiProvider` and extracts
  both types from a sample invoice text.

## Running it

```sh
dart pub get
dart run build_runner build
OPENAI_API_KEY=sk-... dart run bin/main.dart
```

Without `OPENAI_API_KEY` set, `dart run bin/main.dart` prints a message and
exits without making a network call — the source is still worth reading for
the pattern.

`lib/models.g.dart` and `lib/models.freezed.dart` are generated and not
committed to version control (see the repository's `.gitignore`); regenerate
them with the `build_runner` command above whenever you clone this repo or
change `lib/models.dart`.

This package is a development example (`publish_to: none`), not a published
package — see [`../typed_llm`](../typed_llm) for the library itself.
