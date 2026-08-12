import 'package:test/test.dart';
import 'package:typed_llm/typed_llm.dart';

/// The annotations carry no behaviour, but their defaults are part of the
/// public contract the generator reads — `optional` defaulting to anything
/// other than `false` would silently change generated schemas.
void main() {
  group('LlmSchema', () {
    test('is const-constructible so it can annotate a class', () {
      const annotation = LlmSchema();
      expect(annotation, isA<LlmSchema>());
    });
  });

  group('LlmField', () {
    test('defaults to no description and not optional', () {
      const field = LlmField();
      expect(field.description, isNull);
      expect(field.optional, isFalse);
    });

    test('stores the description the generator emits into the schema', () {
      const field = LlmField(
        description: 'The legal name of the vendor issuing the invoice',
      );
      expect(
        field.description,
        'The legal name of the vendor issuing the invoice',
      );
      expect(field.optional, isFalse);
    });

    test('optional can be set explicitly', () {
      const field = LlmField(description: 'A purchase order', optional: true);
      expect(field.optional, isTrue);
      expect(field.description, 'A purchase order');
    });
  });

  group('LlmType', () {
    test('binds a schema to the factory that consumes it', () {
      const schema = <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'value': <String, dynamic>{'type': 'string'},
        },
        'required': <String>['value'],
        'additionalProperties': false,
      };
      final type = LlmType<String>(
        name: 'Wrapper',
        schema: schema,
        fromJson: (json) => json['value'] as String,
      );

      expect(type.name, 'Wrapper');
      expect(type.schema, same(schema));
      expect(type.fromJson(<String, dynamic>{'value': 'hello'}), 'hello');
    });
  });
}
