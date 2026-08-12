## 0.2.1

No functional changes.

- Add an `example/` walking through the generator's input and its generated
  output. pub.dev scored this package 150/160 without one — "Package has an
  example" was the only deduction; every other section was already full
  marks.
- Add a library-level dartdoc to `builder.dart`.

## 0.2.0

Requires `typed_llm` ^0.2.0.

### Added

- Every `@LlmSchema()` class now also generates `$<Class>`, a
  `const LlmType<Class>` binding `<Class>Schema` to
  `_$<Class>FromValidatedJson`. This is what you pass to
  `Extractor.extract`, and it is what makes the call type-safe — see
  `typed_llm`'s 0.2.0 changelog for the mismatch it rules out.

### Changed

- `<Class>Schema` and the generated members now carry dartdoc, so they no
  longer trip `public_member_api_docs` in projects that lint generated code.

Existing output is otherwise unchanged: `<Class>Schema` and
`_$<Class>FromValidatedJson` keep their names and shapes, so a
`fromValidatedJson` wrapper you already wrote still compiles. It is now
redundant, though — `$<Class>` points at the factory directly.

## 0.1.0

Initial release.

- Requires Dart 3.9 or newer, and builds on the analyzer 2.0 element model
  (`analyzer >=9.0.0 <15.0.0`, `source_gen ^4`, `build ^4`). The analyzer
  range is deliberately wide so this generator co-resolves with whatever
  other codegen packages — `freezed`, `json_serializable` — pin in the same
  app. Verified against analyzer 10.2.0 and 12.1.0, including a resolve
  alongside `freezed` 3.x.

- `LlmSchemaGenerator` (`build.yaml` key `llm_schema`): turns an
  `@LlmSchema()`-annotated class into a `<Class>Schema` JSON Schema constant
  and a `_$<Class>FromValidatedJson` factory function.
- Supports primitives (`String`, `int`, `double`, `num`, `bool`), `DateTime`
  (as an ISO-8601 `date-time` string), enums (as a string `enum`), nullable
  fields, `List<T>`, and nested `@LlmSchema` classes — all resolved
  recursively and inlined into both the schema and the factory.
- Works on freezed classes: reads constructor parameters from a redirecting
  `const factory` constructor the same way it reads a plain generative one.
- Clear, actionable build-time errors for unsupported field types, positional
  constructor parameters, and `@LlmField(optional: true)` on a non-nullable
  field.
