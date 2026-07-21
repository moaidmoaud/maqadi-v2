import '../domain/inventory_policy.dart';

class DuplicateInventoryPolicyException implements Exception {
  const DuplicateInventoryPolicyException(this.productId);

  final String productId;
}

class InventoryPolicyResolver {
  const InventoryPolicyResolver();

  Map<String, InventoryPolicy> index(
    Iterable<InventoryPolicy> policies,
  ) {
    final indexed = <String, InventoryPolicy>{};
    for (final policy in policies) {
      if (indexed.containsKey(policy.productId)) {
        throw DuplicateInventoryPolicyException(policy.productId);
      }
      indexed[policy.productId] = policy;
    }
    return indexed;
  }
}
