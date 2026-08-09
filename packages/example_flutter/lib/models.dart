import 'package:typed_llm/typed_llm.dart';

part 'models.g.dart';

/// A minimal `@LlmSchema` class for the on-device demo.
@LlmSchema()
class Invoice {
  Invoice({required this.vendorName, required this.totalAmount, required this.dueDate});

  factory Invoice.fromValidatedJson(Map<String, dynamic> json) => _$InvoiceFromValidatedJson(json);

  final String vendorName;
  final double totalAmount;
  final DateTime dueDate;
}
