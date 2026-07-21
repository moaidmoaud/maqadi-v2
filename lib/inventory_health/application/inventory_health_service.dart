import '../domain/inventory_health_failure.dart';
import '../domain/inventory_health_result.dart';
import '../domain/inventory_policy.dart';
import '../engine/inventory_health_engine.dart';
import 'inventory_health_input_reader.dart';
import 'inventory_policy_resolver.dart';

typedef InventoryHealthClock = DateTime Function();

class InventoryHealthService {
  InventoryHealthService({
    required InventoryHealthInputReader inputReader,
    InventoryPolicyResolver policyResolver = const InventoryPolicyResolver(),
    InventoryHealthEngine engine = const InventoryHealthEngine(),
    InventoryHealthClock? clock,
  })  : _inputReader = inputReader,
        _policyResolver = policyResolver,
        _engine = engine,
        _clock = clock ?? DateTime.now;

  final InventoryHealthInputReader _inputReader;
  final InventoryPolicyResolver _policyResolver;
  final InventoryHealthEngine _engine;
  final InventoryHealthClock _clock;

  Future<InventoryHealthEvaluation> evaluateInventory() async {
    final InventoryHealthInputBatch input;
    try {
      input = await _inputReader.read();
    } catch (_) {
      return const InventoryHealthEvaluationFailure(
        InventoryHealthFailure(
          code: InventoryHealthFailureCode.inputUnavailable,
          message: 'Inventory health data could not be loaded.',
        ),
      );
    }

    late final Map<String, InventoryPolicy> policies;
    try {
      policies = _policyResolver.index(input.policies);
    } on DuplicateInventoryPolicyException catch (_) {
      return const InventoryHealthEvaluationFailure(
        InventoryHealthFailure(
          code: InventoryHealthFailureCode.duplicatePolicy,
          message: 'Inventory contains duplicate health policies.',
        ),
      );
    } catch (_) {
      return const InventoryHealthEvaluationFailure(
        InventoryHealthFailure(
          code: InventoryHealthFailureCode.invalidInputBatch,
          message: 'Inventory health input is invalid.',
        ),
      );
    }

    final productIds = <String>{};
    for (final snapshot in input.snapshots) {
      if (!productIds.add(snapshot.productId)) {
        return const InventoryHealthEvaluationFailure(
          InventoryHealthFailure(
            code: InventoryHealthFailureCode.duplicateProductId,
            message: 'Inventory contains duplicate product identifiers.',
          ),
        );
      }
    }

    try {
      final timestamp = _clock();
      final results = <InventoryHealthResult>[
        for (final snapshot in input.snapshots)
          _engine.evaluate(
            snapshot: snapshot,
            policy: policies[snapshot.productId],
            timestamp: timestamp,
          ),
      ]..sort(_compareResults);
      return InventoryHealthEvaluationSuccess(List.unmodifiable(results));
    } catch (_) {
      return const InventoryHealthEvaluationFailure(
        InventoryHealthFailure(
          code: InventoryHealthFailureCode.evaluationFailed,
          message: 'Inventory health could not be evaluated.',
        ),
      );
    }
  }

  static int _compareResults(
    InventoryHealthResult left,
    InventoryHealthResult right,
  ) {
    final severity = _severity(left.status).compareTo(_severity(right.status));
    if (severity != 0) return severity;
    final name = left.productName.toLowerCase().compareTo(
          right.productName.toLowerCase(),
        );
    return name != 0 ? name : left.productId.compareTo(right.productId);
  }

  static int _severity(InventoryHealthStatus status) => switch (status) {
        InventoryHealthStatus.outOfStock => 0,
        InventoryHealthStatus.lowStock => 1,
        InventoryHealthStatus.unknown => 2,
        InventoryHealthStatus.healthy => 3,
      };
}
