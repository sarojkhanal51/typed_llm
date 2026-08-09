import 'dart:io';

import 'package:typed_llm/typed_llm.dart';

import 'package:typed_llm_example/models.dart';

const _sampleInvoiceText = '''
Acme Corp
Invoice #4471 — Status: OPEN
Due: 2026-09-01

Bill to: Northwind Traders
Ship to: 221B Baker Street, London, NW1 6XE

Items:
  A1-WIDGET  x3  @ \$12.50
  B2-GADGET  x1  @ \$40.00

Total due: \$77.50
''';

Future<void> main() async {
  final apiKey = Platform.environment['OPENAI_API_KEY'];
  if (apiKey == null) {
    stdout.writeln(
      'Set OPENAI_API_KEY to run this example against the real OpenAI API.\n'
      'Skipping the live call — the code below shows the pattern regardless.',
    );
    return;
  }

  // See the "API keys" section of the README before shipping this pattern
  // in a client app: call your own backend proxy instead of embedding a key.
  final extractor = Extractor(
      provider: OpenAiProvider(apiKey: apiKey, model: 'gpt-4o-2024-08-06'));

  try {
    final invoice = await extractor.extract<Invoice>(
      prompt: 'Extract the invoice from this text:\n\n$_sampleInvoiceText',
      schema: InvoiceSchema,
      fromJson: Invoice.fromValidatedJson,
    );
    stdout.writeln('Vendor: ${invoice.vendorName}');
    stdout.writeln('Total: ${invoice.totalAmount} (${invoice.status.name})');
    stdout.writeln('Due: ${invoice.dueDate}');
    for (final item in invoice.items) {
      stdout.writeln('  ${item.sku} x${item.quantity} @ ${item.unitPrice}');
    }

    final address = await extractor.extract<ShippingAddress>(
      prompt:
          'Extract the shipping address from this text:\n\n$_sampleInvoiceText',
      schema: ShippingAddressSchema,
      fromJson: ShippingAddress.fromValidatedJson,
    );
    stdout.writeln(
        'Ship to: ${address.street}, ${address.city} ${address.postalCode}');
  } on TypedLlmException catch (e) {
    switch (e) {
      case SchemaValidationException():
        stderr.writeln(
            'The model could not produce valid output: ${e.errors.join('; ')}');
      case MalformedJsonException():
        stderr.writeln('The model did not return valid JSON: ${e.message}');
      case ProviderException():
        stderr.writeln('OpenAI request failed (${e.statusCode}): ${e.body}');
      case ExtractionTimeoutException():
        stderr.writeln('OpenAI did not respond within ${e.timeout}.');
    }
    exitCode = 1;
  }
}
