# Shopping Recommendation Engine

Phase 7.3 implements RFC-004 and the decisions recorded by ADR-028 and
ADR-029. Shopping recommendations are deterministic, derived, and read-only.
The engine answers one question: **Should this product be recommended for
purchase now?**

## RFC-004: Recommendation policy

The feature returns exactly one of four business decisions:

- `Ignore`
- `Watch`
- `BuySoon`
- `BuyNow`

The approved policy is complete and authoritative:

| Low Stock prediction | Health state | Recommendation | Reason code |
| --- | --- | --- | --- |
| `LowSoon` | `OutOfStock` | `BuyNow` | `alreadyOutOfStock` |
| `LowSoon` | `LowStock` | `BuySoon` | `alreadyLowStock` |
| `LowSoon` | `Healthy` | `BuySoon` | `projectedLowSoon` |
| `Monitor` | `Healthy` | `Watch` | `monitoringRecommended` |
| `Monitor` | valid `Unknown` | `Watch` | `insufficientHealthEvidence` |
| `Normal` | `Healthy` | `Ignore` | `healthyNoAction` |

Unsupported combinations produce product-specific failures. There is no
fallback recommendation. A valid `Unknown` state is one caused by insufficient
policy evidence. An `Unknown` state caused by invalid underlying data is a
product failure.

## ADR-028: Recommendation engines consume predictions

`ShoppingRecommendationInput` contains exactly:

- `InventoryHealthResult`
- `ConsumptionResult`
- `LowStockResult`

`LowStockResult` is the authoritative prediction. The recommendation engine
does not calculate daily consumption, consumption rates, thresholds,
prediction horizons, projected quantities, future stock state, confidence,
recommended quantities, or new timing. It validates that the supplied Results
are internally and mutually consistent without recreating the prediction.

The dependency precedence is:

1. `LowStockResult`
2. `InventoryHealthResult`
3. `ConsumptionResult`

The Low Stock prediction selects the authoritative prediction category. Health
selects the approved business action within that category. Consumption supplies
only its existing pattern, summary, total observed consumption, and event count
as explanation evidence. Changing valid Consumption context cannot promote or
demote a recommendation.

## ADR-029: Recommendation is a business decision

Only `ShoppingRecommendationEngine` applies the RFC-004 mapping. The engine is
synchronous, stateless, deterministic, and independent of Flutter, services,
repositories, persistence, clocks, notifications, shopping lists, purchases,
receipts, AI, analytics, and cloud systems.

Every successful result contains an engine-generated
`ShoppingRecommendationExplanation` with:

- recommendation;
- reason code;
- Health state;
- Consumption pattern and upstream summary;
- authoritative Low Stock prediction;
- structured evidence containing current quantity, unit, observed consumption,
  and consumption event count;
- optional human-readable summary.

The UI displays this explanation and never reconstructs the recommendation.

## Service orchestration

```text
InventoryHealthService ----+     one evaluation
                           |
ConsumptionService --------+     one evaluation
          |                |
          +------ Results--+
                    |
                    v
      LowStockService.evaluateFromResults
                    |             one evaluation
                    v
             LowStockResult
                    |
Health Result ------+
Consumption Result--+
                    |
                    v
      ShoppingRecommendationService
                    |
                    v
      ShoppingRecommendationEngine
                    |
                    v
      Result + structured explanation
```

`LowStockService.evaluateFromResults` is an additive, synchronous orchestration
entry point over already-produced batch Results. The original
`LowStockService.evaluateInventory()` contract remains unchanged and delegates
to the same result-processing path after obtaining its own upstream batches.

`ShoppingRecommendationService` evaluates Health and Consumption once, asks
Low Stock to evaluate those same Results once, indexes all three successful
batches, and invokes the recommendation engine once per safe product triple.
The join is O(products). Unsafe duplicate identifiers or complete upstream
failures fail the batch. Missing pairs, malformed Results, upstream item
failures, and isolated engine exceptions remain product-specific failures so
unrelated valid recommendations are retained.

## Validation boundaries

The engine validates:

- matching, non-empty product identifiers;
- compatible normalized units;
- finite and non-negative quantities;
- current-quantity agreement using one centralized relative epsilon;
- valid aggregate Consumption evidence;
- Health status and reason consistency;
- Low Stock prediction, reason, Health state, and explanation consistency;
- approved Health and prediction combinations.

These checks protect the business decision boundary. They do not repair,
persist, mutate, or reinterpret upstream Results.

## Presentation

The Shopping Recommendations screen supports loading, results, empty, error,
retry, refresh, filtering by all four decisions, engine explanations,
product-specific failure display, and navigation to the existing product
screen. It is read-only and contains no buttons that modify inventory, shopping
lists, purchases, or notifications. A refresh generation token prevents stale
asynchronous results from replacing newer results.

## Data integrity and performance

Recommendations and explanations are never persisted or cached. The feature
performs no repository or schema operation and introduces no migration. It does
not mutate Inventory Health, Consumption, Low Stock, inventory, purchases,
shopping lists, or notifications.

The recommendation-specific work is O(products): three batch indexes, one join,
and one constant-time engine evaluation per valid product. There are no
repository calls inside the engine and no repeated upstream evaluations.

## Intentionally deferred

Shopping-list automation, inventory changes, purchase creation, notifications,
recommended quantities, more detailed timing, price comparison, store
selection, persistence, recommendation history, confidence scoring, AI,
analytics, dashboard redesign, cloud integration, and new prediction rules
remain outside Phase 7.3.
