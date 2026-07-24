class HomeDashboardData {
  const HomeDashboardData({
    required this.totalProducts,
    required this.pendingShoppingProducts,
    required this.lowStockProducts,
    required this.monthlySavings,
    required this.lastReceipt,
  });

  final int totalProducts;
  final int pendingShoppingProducts;
  final int lowStockProducts;
  final double? monthlySavings;
  final HomeDashboardReceipt? lastReceipt;
}

class HomeDashboardReceipt {
  const HomeDashboardReceipt({
    required this.store,
    required this.date,
    required this.productCount,
  });

  final String store;
  final DateTime date;
  final int productCount;
}
