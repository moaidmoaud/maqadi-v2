import 'inventory_models.dart';

enum StockStatus { lowStock, normalStock, outOfStock }

class StockInfo {
  const StockInfo({
    required this.item,
    required this.status,
    required this.currentQuantity,
    required this.minimumQuantity,
  });

  final PantryItem item;
  final StockStatus status;
  final double currentQuantity;
  final double minimumQuantity;
}
