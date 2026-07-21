# Low Stock Detection Engine

Phase 7.2 implements RFC-003 and the decisions recorded by ADR-026 and
ADR-027. Low-stock prediction is derived, read-only state. The engine answers
one question: **Is this product likely to become low in stock soon?**

## RFC-003: Low-stock prediction

The feature consumes only the immutable results produced by Inventory Health
and Consumption. It returns exactly one of three predictions:

- `Normal`
- `Monitor`
- `LowSoon`

`BuyNow`, `BuyLater`, shopping decisions, notifications, AI, analytics, and
inventory mutations are outside Phase 7.2.

The policy is fixed for this phase:

- prediction horizon: 14 days;
- minimum observation period: 7 days;
- minimum actual consumption events: 2.

There is no confidence score and no user-configurable prediction policy.

## Authoritative decision order

Before prediction, the engine validates product identity, unit, quantities,
threshold, finite numeric values, observation chronology, and consistency of
the two upstream Results. Product-specific invalid input produces a
product-specific failure.

For valid input, the engine evaluates rules in this order:

1. `Unknown` health becomes `Monitor` with
   `insufficientHealthEvidence`.
2. `OutOfStock` becomes `LowSoon` with `alreadyOutOfStock`.
3. `LowStock` becomes `LowSoon` with `alreadyLowStock`.
4. Healthy stock with no actual consumption events becomes `Monitor`.
5. A zero or unavailable observation duration becomes `Monitor`.
6. Fewer than 7 observation days becomes `Monitor`.
7. Fewer than 2 actual consumption events becomes `Monitor`.
8. Otherwise, daily consumption is total observed consumption divided by the
   observation duration in days.
9. A non-positive daily rate becomes `Normal`.
10. Projected quantity is current quantity minus daily consumption multiplied
    by 14 days.
11. A projection below or equal to the low-stock threshold becomes `LowSoon`;
    a projection above it becomes `Normal`.

Floating-point equality uses one centralized relative epsilon. Equality counts
as `LowSoon`. Negative observation chronology is invalid input rather than an
observation-duration monitor state.

Only the Consumption Result aggregates are evidence: total consumed,
consumption event count, observation period, consumption pattern, and current
quantity. Purchase, addition, adjustment, and batch-removal movements are not
reclassified as consumption. The low-stock feature does not inspect raw
movement history or `ConsumptionEvent` collections.

## ADR-026: Prediction engines consume Results

`LowStockInput` contains exactly an `InventoryHealthResult` and a
`ConsumptionResult`. It has no repository, `InventoryService`,
`PurchaseRepository`, `SharedPreferences`, receipt, or raw movement dependency.

`LowStockService` evaluates each upstream service once, indexes their Results by
product ID, and joins them in O(products). It calls the engine once for every
safe pair. A complete upstream failure or unsafe duplicate identifier fails the
batch. Missing pairs, invalid product inputs, and isolated engine exceptions
remain product-specific failures so valid products are preserved.

```text
InventoryHealthResult ----+
                          +--> LowStockInput --> LowStockEngine
ConsumptionResult --------+                         |
                                                    v
                                  LowStockResult + Explanation
```

## ADR-027: Prediction belongs only to prediction engines

The synchronous `LowStockEngine` owns rate calculation, projection, comparison,
reason selection, and explanation generation. It has no Flutter, repository,
service, clock, persistence, cache, or write dependency. It never calls
`DateTime.now()`. Identical upstream Results produce identical outputs.

Every successful result includes a structured `LowStockExplanation` containing:

- prediction;
- reason code;
- Health state;
- Consumption pattern;
- evidence, including quantity, threshold, aggregate consumption, event count,
  observation duration, daily rate, fixed horizon, and projected quantity;
- optional human-readable summary.

The presentation displays the explanation and never calculates or reconstructs
it.

## Application and presentation flow

```text
Low Stock Outlook Screen
          |
          v
LowStockService
    |             |
    v             v
Health Service  Consumption Service
    |             |
    +---- Results-+
          |
          v
   LowStockEngine
          |
          v
LowStockEvaluation
```

The screen is read-only and supports loading, results, empty, error, refresh,
prediction filtering, engine explanations, per-product failures, and navigation
to the existing product screen. It contains no stock calculations or edit
controls.

## Integrity and performance

All outputs are derived and are never persisted or cached. The service performs
one upstream Health batch evaluation and one upstream Consumption batch
evaluation. Joining uses indexed product identifiers; the engine receives each
pair once and performs constant work. Overall Phase 7.2 evaluation is
O(products), excluding work already owned by the upstream engines.

The feature performs no inventory, purchase, product, price-history, shopping,
notification, dashboard, receipt, or repository writes. It introduces no data
model migration and does not change existing saved data.

## Intentionally deferred

Shopping recommendations, `BuyNow` and `BuyLater`, notifications, prediction
history, persistence, configurable policy, confidence scores, AI, cloud,
analytics, dashboard redesign, consumption prediction beyond the fixed rule,
and inventory editing remain outside Phase 7.2.
