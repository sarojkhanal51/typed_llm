import 'package:test/test.dart';
import 'package:typed_llm/typed_llm.dart';

/// These exceptions are the package's user-facing failure surface — the string
/// a developer sees in a crash report is often all they get. Pinning the
/// messages keeps a refactor from quietly degrading them.
void main() {
  group('SchemaValidationException', () {
    test('toString lists every error and the retry count', () {
      const exception = SchemaValidationException(
        rawOutput: '{"totalAmount": "1250.00"}',
        errors: [
          ValidationError(
            path: '/totalAmount',
            message: 'Expected number but got String',
            kind: ValidationErrorKind.typeMismatch,
          ),
          ValidationError(
            path: '/dueDate',
            message: 'Missing required property "dueDate"',
            kind: ValidationErrorKind.missingRequiredProperty,
          ),
        ],
        retryCount: 2,
      );

      final text = exception.toString();
      expect(text, contains('/totalAmount: Expected number but got String'));
      expect(text, contains('/dueDate: Missing required property "dueDate"'));
      expect(text, contains('after 2 retries'));
    });

    test('toString says "retry" for a single retry, not "retries"', () {
      const exception = SchemaValidationException(
        rawOutput: '{}',
        errors: [
          ValidationError(
            path: '',
            message: 'boom',
            kind: ValidationErrorKind.typeMismatch,
          ),
        ],
        retryCount: 1,
      );

      expect(exception.toString(), contains('after 1 retry'));
      expect(exception.toString(), isNot(contains('retries')));
    });

    test('retains the raw output for diagnostics', () {
      const raw = '{"vendorName": 42}';
      const exception = SchemaValidationException(
        rawOutput: raw,
        errors: <ValidationError>[],
        retryCount: 0,
      );

      expect(exception.rawOutput, raw);
      expect(exception, isA<TypedLlmException>());
    });
  });

  group('ProviderException', () {
    test('toString includes the status code, retryability and body', () {
      const exception = ProviderException(
        statusCode: 429,
        body: '{"error":"rate limit"}',
        retryable: true,
      );

      final text = exception.toString();
      expect(text, contains('429'));
      expect(text, contains('retryable: true'));
      expect(text, contains('rate limit'));
    });

    test('carries Retry-After when the provider sent one', () {
      const exception = ProviderException(
        statusCode: 429,
        body: '',
        retryable: true,
        retryAfter: Duration(seconds: 30),
      );

      expect(exception.retryAfter, const Duration(seconds: 30));
    });

    test('a client error is reported as not retryable', () {
      const exception = ProviderException(
        statusCode: 401,
        body: 'invalid api key',
        retryable: false,
      );

      expect(exception.toString(), contains('retryable: false'));
      expect(exception.retryAfter, isNull);
    });
  });

  group('MalformedJsonException', () {
    test('toString explains why the output could not be parsed', () {
      const exception = MalformedJsonException(
        rawOutput: 'Here is your invoice: {',
        message: 'Unexpected end of input',
      );

      expect(
        exception.toString(),
        contains('MalformedJsonException: Unexpected end of input'),
      );
      expect(exception.rawOutput, 'Here is your invoice: {');
    });
  });

  group('ExtractionTimeoutException', () {
    test('toString names the timeout that was exceeded', () {
      const exception = ExtractionTimeoutException(
        timeout: Duration(seconds: 60),
      );

      expect(exception.toString(), contains('no response within'));
      expect(exception.toString(), contains('0:01:00'));
      expect(exception.timeout, const Duration(seconds: 60));
    });
  });

  test('every exception is a TypedLlmException', () {
    const exceptions = <TypedLlmException>[
      SchemaValidationException(
        rawOutput: '',
        errors: <ValidationError>[],
        retryCount: 0,
      ),
      ProviderException(statusCode: 500, body: '', retryable: true),
      MalformedJsonException(rawOutput: '', message: ''),
      ExtractionTimeoutException(timeout: Duration.zero),
    ];

    // The hierarchy is sealed, so an exhaustive switch is the contract the
    // README documents for callers. If a case is ever added without updating
    // that documentation, this stops compiling.
    for (final exception in exceptions) {
      final label = switch (exception) {
        SchemaValidationException() => 'schema',
        ProviderException() => 'provider',
        MalformedJsonException() => 'json',
        ExtractionTimeoutException() => 'timeout',
      };
      expect(label, isNotEmpty);
    }
  });
}
