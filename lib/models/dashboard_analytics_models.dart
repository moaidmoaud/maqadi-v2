import 'inventory_models.dart';

class DashboardSummary {
  const DashboardSummary({
    required this.totalProducts,
    required this.totalBatches,
    required this.totalQuantity,
    required this.lowStock,
    required this.outOfStock,
    required this.expiringSoon,
    required this.expired,
    required this.shoppingListItems,
  });

  final int totalProducts;
  final int totalBatches;
  final double totalQuantity;
  final int lowStock;
  final int outOfStock;
  final int expiringSoon;
  final int expired;
  final int shoppingListItems;
}

class ProductAnalyticsInsight {
  const ProductAnalyticsInsight({
    required this.item,
    required this.quantity,
    required this.addedAt,
    required this.updatedAt,
  });

  final PantryItem item;
  final double quantity;
  final DateTime? addedAt;
  final DateTime? updatedAt;
}

class AnalyticsDistribution {
  const AnalyticsDistribution({required this.label, required this.value});

  final String label;
  final int value;
}

class DashboardAnalytics {
  const DashboardAnalytics({
    required this.summary,
    required this.topProducts,
    required this.lowestStockProducts,
    required this.recentlyUpdatedProducts,
    required this.recentlyAddedProducts,
    required this.stockStatusDistribution,
    required this.expiryStatusDistribution,
    required this.categoryDistribution,
  });

  final DashboardSummary summary;
  final List<ProductAnalyticsInsight> topProducts;
  final List<ProductAnalyticsInsight> lowestStockProducts;
  final List<ProductAnalyticsInsight> recentlyUpdatedProducts;
  final List<ProductAnalyticsInsight> recentlyAddedProducts;
  final List<AnalyticsDistribution> stockStatusDistribution;
  final List<AnalyticsDistribution> expiryStatusDistribution;
  final List<AnalyticsDistribution> categoryDistribution;
}

class DashboardSearchResult {
  const DashboardSearchResult({
    required this.item,
    required this.matchedFields,
    required this.matchedBarcodes,
    required this.matchedBatchIds,
  });

  final PantryItem item;
  final List<String> matchedFields;
  final List<String> matchedBarcodes;
  final List<String> matchedBatchIds;
}
