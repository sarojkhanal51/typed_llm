import 'package:typed_llm/typed_llm.dart';

part 'models.g.dart';

/// A minimal `@LlmSchema` class for the on-device demo.
@LlmSchema()
class Invoice {
  Invoice({required this.vendorName, required this.totalAmount, required this.dueDate});

  final String vendorName;
  final double totalAmount;
  final DateTime dueDate;
}
