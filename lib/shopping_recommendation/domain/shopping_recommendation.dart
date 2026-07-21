enum ShoppingRecommendationState { ignore, watch, buySoon, buyNow }

class ShoppingRecommendation {
  const ShoppingRecommendation({
    required this.state,
    required this.currentQuantity,
    required this.unit,
    required this.totalObservedConsumption,
    required this.consumptionEventCount,
  });

  final ShoppingRecommendationState state;
  final double currentQuantity;
  final String unit;
  final double totalObservedConsumption;
  final int consumptionEventCount;
}
