import '../../receipt_line_builder/domain/receipt_line.dart';
import '../application/candidate_generation_service.dart';

class MappedReceiptLineTextResolver implements ReceiptLineProductTextResolver {
  MappedReceiptLineTextResolver(Map<String, String> elementTextById)
      : _elementTextById = Map.unmodifiable(elementTextById);

  final Map<String, String> _elementTextById;

  @override
  Future<String?> resolve(ReceiptLine line) async {
    final productElementId = line.productElementId;
    return productElementId == null ? null : _elementTextById[productElementId];
  }
}
