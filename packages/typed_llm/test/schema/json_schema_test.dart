import 'package:test/test.dart';
import 'package:typed_llm/typed_llm.dart';

void main() {
  group('JsonSchema.toMap', () {
    test('string schema with format and enum', () {
      const schema = JsonSchema.string(
        description: 'Invoice status',
        format: 'date-time',
        enumValues: ['open', 'paid'],
      );

      expect(schema.toMap(), {
        'type': 'string',
        'description': 'Invoice status',
        'format': 'date-time',
        'enum': ['open', 'paid'],
      });
    });

    test('string schema omits absent keys', () {
      const schema = JsonSchema.string();

      expect(schema.toMap(), {'type': 'string'});
    });

    test('number, integer, and boolean schemas', () {
      expect(const JsonSchema.number().toMap(), {'type': 'number'});
      expect(const JsonSchema.integer().toMap(), {'type': 'integer'});
      expect(const JsonSchema.boolean().toMap(), {'type': 'boolean'});
    });

    test('nullable schema emits a type array', () {
      const schema = JsonSchema.string(nullable: true);

      expect(schema.toMap(), {
        'type': ['string', 'null'],
      });
    });

    test('array schema nests its items schema', () {
      const schema = JsonSchema.array(items: JsonSchema.integer());

      expect(schema.toMap(), {
        'type': 'array',
        'items': {'type': 'integer'},
      });
    });

    test(
        'object schema nests properties and required, defaults additionalProperties to false',
        () {
      const schema = JsonSchema.object(
        properties: {
          'vendorName': JsonSchema.string(),
          'totalAmount': JsonSchema.number(),
        },
        required: ['vendorName', 'totalAmount'],
      );

      expect(schema.toMap(), {
        'type': 'object',
        'properties': {
          'vendorName': {'type': 'string'},
          'totalAmount': {'type': 'number'},
        },
        'required': ['vendorName', 'totalAmount'],
        'additionalProperties': false,
      });
    });

    test('nesting three levels deep', () {
      const schema = JsonSchema.object(
        properties: {
          'invoice': JsonSchema.object(
            properties: {
              'items': JsonSchema.array(
                items: JsonSchema.object(
                  properties: {'sku': JsonSchema.string()},
                  required: ['sku'],
                ),
              ),
            },
            required: ['items'],
          ),
        },
        required: ['invoice'],
      );

      expect(schema.toMap(), {
        'type': 'object',
        'properties': {
          'invoice': {
            'type': 'object',
            'properties': {
              'items': {
                'type': 'array',
                'items': {
                  'type': 'object',
                  'properties': {
                    'sku': {'type': 'string'},
                  },
                  'required': ['sku'],
                  'additionalProperties': false,
                },
              },
            },
            'required': ['items'],
            'additionalProperties': false,
          },
        },
        'required': ['invoice'],
        'additionalProperties': false,
      });
    });

    test('additionalProperties can be set to true', () {
      const schema = JsonSchema.object(
        properties: {},
        required: [],
        additionalProperties: true,
      );

      expect(schema.toMap()['additionalProperties'], isTrue);
    });
  });
}
