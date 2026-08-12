# typed_llm_generator example

This package is a `build_runner` code generator — you never call it from Dart
code, so this example shows the input it consumes and the output it produces.
For a runnable app, see
[`packages/example`](https://github.com/sarojkhanal51/typed_llm/tree/develop/packages/example)
in the repository, which wires this generator up against a real provider.

## 1. Depend on it

```yaml
dependencies:
  typed_llm: ^0.2.0

dev_dependencies:
  build_runner: ^2.4.0
  typed_llm_generator: ^0.2.0
```

Code generation requires Dart 3.9 or newer. The `typed_llm` runtime package
itself supports Dart 3.4+.

## 2. Annotate a class

Add the `part` directive and annotate. That's the whole input — no factory or
`fromJson` boilerplate to write:

```dart
// lib/invoice.dart
import 'package:typed_llm/typed_llm.dart';

part 'invoice.g.dart';

@LlmSchema()
class Invoice {
  Invoice({
    @LlmField(description: 'The legal name of the vendor issuing the invoice')
    required this.vendorName,
    required this.totalAmount,
    required this.dueDate,
  });

  final String vendorName;
  final double totalAmount;
  final DateTime dueDate;
}
```

`@LlmField(description:)` is optional, but the model sees those descriptions
in the schema — they measurably improve extraction accuracy on ambiguous
field names.

## 3. Generate

```sh
dart run build_runner build
```

## 4. What you get

Three top-level members in `lib/invoice.g.dart`:

```dart
/// The [LlmType] for [Invoice] — pass this to `Extractor.extract`.
const LlmType<Invoice> $Invoice = LlmType<Invoice>(
  name: 'Invoice',
  schema: InvoiceSchema,
  fromJson: _$InvoiceFromValidatedJson,
);

/// The raw JSON Schema describing [Invoice].
const Map<String, dynamic> InvoiceSchema = {
  'type': 'object',
  'properties': {
    'vendorName': {
      'type': 'string',
      'description': 'The legal name of the vendor issuing the invoice',
    },
    'totalAmount': {'type': 'number'},
    'dueDate': {'type': 'string', 'format': 'date-time'},
  },
  'required': ['vendorName', 'totalAmount', 'dueDate'],
  'additionalProperties': false,
};

Invoice _$InvoiceFromValidatedJson(Map<String, dynamic> json) {
  return Invoice(
    vendorName: json['vendorName'] as String,
    totalAmount: (json['totalAmount'] as num).toDouble(),
    dueDate: DateTime.parse(json['dueDate'] as String),
  );
}
```

## 5. Use it

`$Invoice` carries the schema and the parser together, so `extract` infers the
return type and a mismatched pair cannot be expressed:

```dart
final invoice = await extractor.extract($Invoice, prompt: 'Extract the ...');
```

`InvoiceSchema` remains available if you want to send or inspect the raw JSON
Schema yourself.

## Supported field types

`String`, `int`, `double`, `num`, `bool`, `DateTime` (ISO-8601 `date-time`
string), enums (string `enum`), nullable fields, `List<T>` of any supported
type, and other `@LlmSchema()` classes — nested classes are resolved
recursively and inlined into both the schema and the parser.
[freezed](https://pub.dev/packages/freezed) classes work too: the generator
reads constructor parameters from the redirecting `const factory` the same way
it reads a plain generative constructor.

Anything else is a build-time error naming the offending field and type,
rather than a silently missing property in the schema.
