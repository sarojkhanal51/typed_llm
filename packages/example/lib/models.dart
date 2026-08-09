import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:typed_llm/typed_llm.dart';

part 'models.freezed.dart';
part 'models.g.dart';

/// A plain (non-freezed) `@LlmSchema` class with a nested class, an enum,
/// a `DateTime`, and a `List<T>` — exercising every type the generator
/// supports.
@LlmSchema()
class Invoice {
  Invoice({
    @LlmField(description: 'The legal name of the vendor issuing the invoice')
    required this.vendorName,
    required this.totalAmount,
    required this.dueDate,
    required this.status,
    required this.items,
  });

  /// Reads the schema and factory `typed_llm_generator` emitted for
  /// [Invoice] into `models.g.dart`.
  factory Invoice.fromValidatedJson(Map<String, dynamic> json) =>
      _$InvoiceFromValidatedJson(json);

  final String vendorName;
  final double totalAmount;
  final DateTime dueDate;
  final InvoiceStatus status;
  final List<LineItem> items;
}

/// Nested inside [Invoice.items] — the generator inlines this schema and
/// its extraction logic directly into `InvoiceSchema`/
/// `_$InvoiceFromValidatedJson`.
@LlmSchema()
class LineItem {
  LineItem(
      {required this.sku, required this.quantity, required this.unitPrice});

  /// Reads the schema and factory `typed_llm_generator` emitted for
  /// [LineItem] into `models.g.dart`.
  factory LineItem.fromValidatedJson(Map<String, dynamic> json) =>
      _$LineItemFromValidatedJson(json);

  final String sku;
  final int quantity;
  final double unitPrice;
}

/// A plain Dart enum — the generator emits this as a JSON Schema string
/// `enum`.
enum InvoiceStatus { open, paid, overdue }

/// A [freezed](https://pub.dev/packages/freezed) class also annotated with
/// `@LlmSchema` — demonstrates that the generator reads constructor
/// parameters from freezed's redirecting `const factory` constructor, not
/// just plain generative constructors.
@freezed
@LlmSchema()
class ShippingAddress with _$ShippingAddress {
  /// Reads the schema and factory `typed_llm_generator` emitted for
  /// [ShippingAddress] into `models.g.dart`.
  factory ShippingAddress.fromValidatedJson(Map<String, dynamic> json) =>
      _$ShippingAddressFromValidatedJson(json);

  const factory ShippingAddress(
      {required String street,
      required String city,
      required String postalCode}) = _ShippingAddress;
}
