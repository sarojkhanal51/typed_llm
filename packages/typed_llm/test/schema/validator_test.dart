import 'package:test/test.dart';
import 'package:typed_llm/typed_llm.dart';

void main() {
  const validator = SchemaValidator();

  final invoiceSchema = const JsonSchema.object(
    properties: {
      'vendorName': JsonSchema.string(),
      'totalAmount': JsonSchema.number(),
      'dueDate': JsonSchema.string(format: 'date-time'),
      'status': JsonSchema.string(enumValues: ['open', 'paid']),
      'note': JsonSchema.string(nullable: true),
      'items': JsonSchema.array(
        items: JsonSchema.object(
          properties: {
            'sku': JsonSchema.string(),
            'quantity': JsonSchema.integer(),
          },
          required: ['sku', 'quantity'],
        ),
      ),
    },
    required: ['vendorName', 'totalAmount', 'dueDate', 'status', 'items'],
  ).toMap();

  Map<String, dynamic> validInvoice() => {
        'vendorName': 'Acme Corp',
        'totalAmount': 42.5,
        'dueDate': '2026-09-01T00:00:00Z',
        'status': 'open',
        'note': null,
        'items': [
          {'sku': 'A1', 'quantity': 3},
          {'sku': 'B2', 'quantity': 1},
        ],
      };

  group('valid payloads', () {
    test('a fully valid nested payload passes with no errors', () {
      final result = validator.validate(invoiceSchema, validInvoice());

      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('a whole-number double satisfies an integer schema', () {
      final result = validator.validate(
        const JsonSchema.integer().toMap(),
        3.0,
      );

      expect(result.isValid, isTrue);
    });
  });

  group('type mismatch', () {
    test('wrong primitive type is reported', () {
      final payload = validInvoice()..['totalAmount'] = 'not a number';

      final result = validator.validate(invoiceSchema, payload);

      expect(result.isValid, isFalse);
      expect(
        result.errors,
        contains(
          isA<ValidationError>()
              .having((e) => e.path, 'path', '/totalAmount')
              .having((e) => e.kind, 'kind', ValidationErrorKind.typeMismatch),
        ),
      );
    });

    test('a fractional double fails an integer schema', () {
      final result = validator.validate(
        const JsonSchema.integer().toMap(),
        3.5,
      );

      expect(result.isValid, isFalse);
      expect(result.errors.single.kind, ValidationErrorKind.typeMismatch);
    });

    test('null is rejected by a non-nullable schema', () {
      final result =
          validator.validate(const JsonSchema.string().toMap(), null);

      expect(result.isValid, isFalse);
      expect(result.errors.single.kind, ValidationErrorKind.typeMismatch);
    });

    test('null is accepted by a nullable schema', () {
      final result = validator.validate(
        const JsonSchema.string(nullable: true).toMap(),
        null,
      );

      expect(result.isValid, isTrue);
    });

    test('an error deep inside an array reports an indexed path', () {
      final payload = validInvoice();
      (payload['items'] as List)[1] = {'sku': 'B2', 'quantity': 'three'};

      final result = validator.validate(invoiceSchema, payload);

      expect(
        result.errors,
        contains(
          isA<ValidationError>()
              .having((e) => e.path, 'path', '/items/1/quantity'),
        ),
      );
    });
  });

  group('missing required property', () {
    test('a missing required field is reported by name', () {
      final payload = validInvoice()..remove('vendorName');

      final result = validator.validate(invoiceSchema, payload);

      expect(
        result.errors,
        contains(
          isA<ValidationError>()
              .having((e) => e.path, 'path', '/vendorName')
              .having(
                (e) => e.kind,
                'kind',
                ValidationErrorKind.missingRequiredProperty,
              ),
        ),
      );
    });
  });

  group('unknown enum value', () {
    test('a value outside the enum is reported', () {
      final payload = validInvoice()..['status'] = 'cancelled';

      final result = validator.validate(invoiceSchema, payload);

      expect(
        result.errors,
        contains(
          isA<ValidationError>()
              .having((e) => e.path, 'path', '/status')
              .having(
                (e) => e.kind,
                'kind',
                ValidationErrorKind.unknownEnumValue,
              ),
        ),
      );
    });
  });

  group('bad date format', () {
    test('a non-ISO-8601 string fails the date-time format check', () {
      final payload = validInvoice()..['dueDate'] = 'not a date';

      final result = validator.validate(invoiceSchema, payload);

      expect(
        result.errors,
        contains(
          isA<ValidationError>()
              .having((e) => e.path, 'path', '/dueDate')
              .having((e) => e.kind, 'kind', ValidationErrorKind.invalidFormat),
        ),
      );
    });
  });

  group('additional properties', () {
    test('an unknown key is reported when additionalProperties is false', () {
      final payload = validInvoice()..['unexpectedField'] = 'surprise';

      final result = validator.validate(invoiceSchema, payload);

      expect(
        result.errors,
        contains(
          isA<ValidationError>()
              .having((e) => e.path, 'path', '/unexpectedField')
              .having(
                (e) => e.kind,
                'kind',
                ValidationErrorKind.additionalPropertyNotAllowed,
              ),
        ),
      );
    });

    test('an unknown key is allowed when additionalProperties is true', () {
      final schema = const JsonSchema.object(
        properties: {},
        required: [],
        additionalProperties: true,
      ).toMap();

      final result = validator.validate(schema, {'anything': 1});

      expect(result.isValid, isTrue);
    });
  });

  test('ValidationError.toString includes the path and message', () {
    const error = ValidationError(
      path: '/foo',
      message: 'boom',
      kind: ValidationErrorKind.typeMismatch,
    );

    expect(error.toString(), '/foo: boom');
  });
}
