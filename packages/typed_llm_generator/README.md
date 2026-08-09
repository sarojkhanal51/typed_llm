# typed_llm_generator

[![pub package](https://img.shields.io/pub/v/typed_llm_generator.svg)](https://pub.dev/packages/typed_llm_generator)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

The `build_runner` code generator for
[`typed_llm`](https://pub.dev/packages/typed_llm) — turns
`@LlmSchema()`-annotated classes into JSON Schema constants and
validated-JSON factory functions.

This is a dev dependency; you don't import it in application code:

```yaml
dependencies:
  typed_llm: ^0.1.0

dev_dependencies:
  build_runner: ^2.4.0
  typed_llm_generator: ^0.1.0
```

```sh
dart run build_runner build --delete-conflicting-outputs
```

See the [`typed_llm` README](https://pub.dev/packages/typed_llm) for the
annotations this generator consumes, what it supports (primitives, `DateTime`,
enums, `List<T>`, nested `@LlmSchema` classes, freezed classes), and a full
usage example.

## License

MIT — see [LICENSE](LICENSE).
