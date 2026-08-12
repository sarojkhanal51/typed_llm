import 'dart:convert';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';
import 'package:typed_llm_generator/builder.dart';

const _typedLlmAssets = {
  'typed_llm|lib/typed_llm.dart': '''
export 'src/annotations.dart';
''',
  'typed_llm|lib/src/annotations.dart': '''
class LlmSchema {
  const LlmSchema();
}

class LlmField {
  const LlmField({this.description, this.optional = false});
  final String? description;
  final bool optional;
}

class LlmType<T> {
  const LlmType({
    required this.name,
    required this.schema,
    required this.fromJson,
  });
  final String name;
  final Map<String, dynamic> schema;
  final T Function(Map<String, dynamic> json) fromJson;
}
''',
};

/// `dart_style` reformats generated output, so exact-whitespace matching is
/// brittle. This strips all whitespace, and any trailing comma before a
/// closing delimiter, before checking containment — so assertions only care
/// about token content/order and survive a formatter upgrade changing its
/// line-splitting or trailing-comma style.
Matcher _generatedContains(List<String> expectedSnippets) {
  String normalize(String value) => value
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp(r',(?=[}\])])'), '');

  return predicate<List<int>>((bytes) {
    final actual = normalize(utf8.decode(bytes));
    return expectedSnippets.every(
      (snippet) => actual.contains(normalize(snippet)),
    );
  }, 'contains (whitespace-stripped) every expected snippet');
}

Future<void> _expectGenerated(
  String sourceDartFile,
  String sourceContent,
  String outputPartFile,
  List<String> expectedSnippets,
) async {
  await testBuilder(
    llmSchemaBuilder(BuilderOptions.empty),
    {..._typedLlmAssets, 'a|$sourceDartFile': sourceContent},
    outputs: {'a|$outputPartFile': _generatedContains(expectedSnippets)},
  );
}

/// Asserts that building [sourceContent] fails with a message matching
/// [messageMatcher], and emits nothing.
///
/// `testBuilder` does not rethrow a generator's
/// [InvalidGenerationSourceError]; it reports it as a `SEVERE` log record and
/// completes normally, having written no outputs. So the assertion is on the
/// logs, with `outputs: {}` pinning down that generation really was abandoned
/// rather than merely warned about.
Future<void> _expectBuildError(
  String sourceDartFile,
  String sourceContent,
  Matcher messageMatcher,
) async {
  final logs = <LogRecord>[];
  await testBuilder(
    llmSchemaBuilder(BuilderOptions.empty),
    {..._typedLlmAssets, 'a|$sourceDartFile': sourceContent},
    outputs: {},
    onLog: logs.add,
  );

  final severe = logs
      .where((record) => record.level >= Level.SEVERE)
      .map((record) => record.message)
      .toList();
  expect(severe, hasLength(1), reason: 'expected exactly one build failure');
  expect(severe.single, messageMatcher);
}

void main() {
  group('primitives', () {
    test('generates a schema and factory for every primitive type', () async {
      await _expectGenerated(
        'lib/primitives.dart',
        '''
import 'package:typed_llm/typed_llm.dart';

@LlmSchema()
class Primitives {
  final String name;
  final int count;
  final double price;
  final num quantity;
  final bool active;
  Primitives({
    required this.name,
    required this.count,
    required this.price,
    required this.quantity,
    required this.active,
  });
}
''',
        'lib/primitives.llm_schema.g.part',
        [
          "const LlmType<Primitives> \$Primitives = LlmType<Primitives>(",
          "name: 'Primitives'",
          'schema: PrimitivesSchema',
          'fromJson: _\$PrimitivesFromValidatedJson',
          "const Map<String, dynamic> PrimitivesSchema = {'type': 'object', 'properties': {",
          "'name': {'type': 'string'}",
          "'count': {'type': 'integer'}",
          "'price': {'type': 'number'}",
          "'quantity': {'type': 'number'}",
          "'active': {'type': 'boolean'}",
          "'required': ['name', 'count', 'price', 'quantity', 'active']",
          "'additionalProperties': false",
          'Primitives _\$PrimitivesFromValidatedJson(Map<String, dynamic> json)',
          "name: json['name'] as String",
          "count: (json['count'] as num).toInt()",
          "price: (json['price'] as num).toDouble()",
          "quantity: json['quantity'] as num",
          "active: json['active'] as bool",
        ],
      );
    });
  });

  group('DateTime', () {
    test('is emitted as a date-time formatted string', () async {
      await _expectGenerated(
        'lib/event.dart',
        '''
import 'package:typed_llm/typed_llm.dart';

@LlmSchema()
class Event {
  final DateTime startsAt;
  Event({required this.startsAt});
}
''',
        'lib/event.llm_schema.g.part',
        [
          "'startsAt': {'type': 'string', 'format': 'date-time'}",
          "startsAt: DateTime.parse(json['startsAt'] as String)",
        ],
      );
    });
  });

  group('enum', () {
    test('is emitted as a string enum with a byName factory call', () async {
      await _expectGenerated(
        'lib/ticket.dart',
        '''
import 'package:typed_llm/typed_llm.dart';

enum Status { open, closed }

@LlmSchema()
class Ticket {
  final Status status;
  Ticket({required this.status});
}
''',
        'lib/ticket.llm_schema.g.part',
        [
          "'status': {'type': 'string', 'enum': ['open', 'closed']}",
          "status: Status.values.byName(json['status'] as String)",
        ],
      );
    });
  });

  group('nullable fields', () {
    test(
      'a nullable field is optional and its type is a nullable array',
      () async {
        await _expectGenerated(
          'lib/note.dart',
          '''
import 'package:typed_llm/typed_llm.dart';

@LlmSchema()
class Note {
  final String? body;
  Note({this.body});
}
''',
          'lib/note.llm_schema.g.part',
          [
            "'body': {'type': ['string', 'null']}",
            "'required': ['body']",
            "body: json['body'] as String?",
          ],
        );
      },
    );

    test(
      '@LlmField(optional: true) on a non-nullable field is a build error',
      () async {
        await _expectBuildError(
          'lib/bad_note.dart',
          '''
import 'package:typed_llm/typed_llm.dart';

@LlmSchema()
class BadNote {
  final String body;
  BadNote({@LlmField(optional: true) required this.body});
}
''',
          allOf([
            contains('BadNote'),
            contains('optional: true'),
            contains('non-nullable'),
          ]),
        );
      },
    );
  });

  group('List<T>', () {
    test(
      'a list of a supported primitive is emitted as an array schema',
      () async {
        await _expectGenerated(
          'lib/tags.dart',
          '''
import 'package:typed_llm/typed_llm.dart';

@LlmSchema()
class Tags {
  final List<String> values;
  Tags({required this.values});
}
''',
          'lib/tags.llm_schema.g.part',
          [
            "'values': {'type': 'array', 'items': {'type': 'string'}}",
            "values: (json['values'] as List<dynamic>).map((e) => e as String).toList()",
          ],
        );
      },
    );
  });

  group('nested @LlmSchema classes', () {
    test(
      'a nested class is inlined into both the schema and the factory',
      () async {
        await _expectGenerated(
          'lib/invoice.dart',
          '''
import 'package:typed_llm/typed_llm.dart';

@LlmSchema()
class LineItem {
  final String sku;
  final int quantity;
  LineItem({required this.sku, required this.quantity});
}

@LlmSchema()
class Invoice {
  final String vendorName;
  final List<LineItem> items;
  Invoice({required this.vendorName, required this.items});
}
''',
          'lib/invoice.llm_schema.g.part',
          [
            "'items': {'type': 'array', 'items': "
                "{'type': 'object', 'properties': {'sku': {'type': 'string'}, "
                "'quantity': {'type': 'integer'}}, 'required': ['sku', 'quantity'], "
                "'additionalProperties': false}}",
            "items: (json['items'] as List<dynamic>).map((e) => "
                "LineItem(sku: (e as Map<String, dynamic>)['sku'] as String, "
                "quantity: ((e as Map<String, dynamic>)['quantity'] as num).toInt())).toList()",
            'LineItem _\$LineItemFromValidatedJson(Map<String, dynamic> json)',
            'Invoice _\$InvoiceFromValidatedJson(Map<String, dynamic> json)',
          ],
        );
      },
    );

    test('three levels of nesting resolve correctly', () async {
      await _expectGenerated(
        'lib/deep.dart',
        '''
import 'package:typed_llm/typed_llm.dart';

@LlmSchema()
class Leaf {
  final String value;
  Leaf({required this.value});
}

@LlmSchema()
class Branch {
  final Leaf leaf;
  Branch({required this.leaf});
}

@LlmSchema()
class Root {
  final Branch branch;
  Root({required this.branch});
}
''',
        'lib/deep.llm_schema.g.part',
        [
          "'branch': {'type': 'object', 'properties': {'leaf': {'type': 'object', "
              "'properties': {'value': {'type': 'string'}}, 'required': ['value'], "
              "'additionalProperties': false}}, 'required': ['leaf'], "
              "'additionalProperties': false}",
          "branch: Branch(leaf: Leaf(value: ((json['branch'] as Map<String, dynamic>)['leaf'] "
              "as Map<String, dynamic>)['value'] as String))",
        ],
      );
    });
  });

  group('@LlmField(description:)', () {
    test('sets the schema description', () async {
      await _expectGenerated(
        'lib/vendor.dart',
        '''
import 'package:typed_llm/typed_llm.dart';

@LlmSchema()
class Vendor {
  final String name;
  Vendor({@LlmField(description: 'Legal vendor name') required this.name});
}
''',
        'lib/vendor.llm_schema.g.part',
        ["'name': {'type': 'string', 'description': 'Legal vendor name'}"],
      );
    });
  });

  group('freezed-shaped classes', () {
    test(
      'reads parameters from a redirecting const factory constructor',
      () async {
        await _expectGenerated(
          'lib/money.dart',
          '''
import 'package:typed_llm/typed_llm.dart';

@LlmSchema()
abstract class Money {
  const factory Money({required String currency, required double amount}) = _Money;
}

class _Money implements Money {
  const _Money({required this.currency, required this.amount});
  @override
  final String currency;
  @override
  final double amount;
}
''',
          'lib/money.llm_schema.g.part',
          [
            "'currency': {'type': 'string'}",
            "'amount': {'type': 'number'}",
            'Money _\$MoneyFromValidatedJson(Map<String, dynamic> json)',
            "return Money(currency: json['currency'] as String, amount: (json['amount'] as num).toDouble());",
          ],
        );
      },
    );
  });

  group('unsupported types', () {
    test(
      'an unsupported field type produces an actionable build error',
      () async {
        await _expectBuildError(
          'lib/bad_field.dart',
          '''
import 'package:typed_llm/typed_llm.dart';

@LlmSchema()
class BadField {
  final Duration timeout;
  BadField({required this.timeout});
}
''',
          allOf([
            contains('timeout'),
            contains('BadField'),
            contains('unsupported type'),
          ]),
        );
      },
    );

    test(
      'a positional constructor parameter produces an actionable build error',
      () async {
        await _expectBuildError('lib/bad_ctor.dart', '''
import 'package:typed_llm/typed_llm.dart';

@LlmSchema()
class BadCtor {
  final String name;
  BadCtor(this.name);
}
''', allOf([contains('positional'), contains('BadCtor')]));
      },
    );
  });
}
