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
