import '../../models/dashboard_analytics_models.dart';
import '../../models/purchase_models.dart';
import '../domain/home_dashboard_data.dart';

abstract interface class HomeDashboardProvider {
  Future<HomeDashboardData> load();
}

abstract interface class MonthlySavingsProvider {
  Future<double?> loadMonthlySavings();
}

class PlaceholderMonthlySavingsProvider implements MonthlySavingsProvider {
  const PlaceholderMonthlySavingsProvider();

  @override
  Future<double?> loadMonthlySavings() async => null;
}

typedef DashboardAnalyticsReader = DashboardAnalytics Function();
typedef PurchaseHistoryReader = Future<List<PurchaseListEntry>> Function();

class ExistingServicesHomeDashboardProvider implements HomeDashboardProvider {
  const ExistingServicesHomeDashboardProvider({
    required this.readAnalytics,
    required this.readPurchaseHistory,
    this.monthlySavingsProvider = const PlaceholderMonthlySavingsProvider(),
  });

  final DashboardAnalyticsReader readAnalytics;
  final PurchaseHistoryReader readPurchaseHistory;
  final MonthlySavingsProvider monthlySavingsProvider;

  @override
  Future<HomeDashboardData> load() async {
    final analytics = readAnalytics();
    final purchases = await readPurchaseHistory();
    final savings = await monthlySavingsProvider.loadMonthlySavings();
    final lastPurchase = purchases.isEmpty ? null : purchases.first;

    return HomeDashboardData(
      totalProducts: analytics.summary.totalProducts,
      pendingShoppingProducts: analytics.summary.shoppingListItems,
      lowStockProducts: analytics.summary.lowStock,
      monthlySavings: savings,
      lastReceipt: lastPurchase == null
          ? null
          : HomeDashboardReceipt(
              store: lastPurchase.storeName,
              date: lastPurchase.purchase.purchaseDate,
              productCount: lastPurchase.itemCount,
            ),
    );
  }
}
