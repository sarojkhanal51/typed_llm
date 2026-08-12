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
  typed_llm: ^0.1.3

dev_dependencies:
  build_runner: ^2.4.0
  typed_llm_generator: ^0.1.0
```

Code generation requires Dart 3.9 or newer. The `typed_llm` runtime package
itself still supports Dart 3.4+ — only this dev-time generator needs the
newer SDK.

```sh
dart run build_runner build
```

See the [`typed_llm` README](https://pub.dev/packages/typed_llm) for the
annotations this generator consumes, what it supports (primitives, `DateTime`,
enums, `List<T>`, nested `@LlmSchema` classes, freezed classes), and a full
usage example.

## License

MIT — see [LICENSE](LICENSE).
