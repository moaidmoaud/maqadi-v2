# Inventory Health Engine

Phase 7.0 implements RFC-001 and the decisions recorded by ADR-018,
ADR-019, and ADR-020. Inventory health is derived, read-only state. It is
never stored and it does not trigger inventory or shopping actions.

## RFC-001: Inventory health

The engine answers one question: **What is the current health state?** It
supports exactly four states:

- `Unknown`
- `Healthy`
- `LowStock`
- `OutOfStock`

Expiry, attention, archived, prediction, consumption, and shopping
recommendations are outside this phase.

The decision order is authoritative:

1. An invalid snapshot is `Unknown`.
2. A quantity of zero is `OutOfStock`.
3. A missing or invalid policy is `Unknown`.
4. A quantity at or below the low-stock threshold is `LowStock`.
5. Every other valid item is `Healthy`.

A negative or non-finite quantity is an invalid snapshot. A policy threshold
must be finite and non-negative. Units must match after trimming and
case-folding; Phase 7.0 performs no unit conversion.

## ADR-018: Derived, non-persistent health

Health results and explanations are immutable values derived on demand. The
feature has no repository and performs no create, update, or delete operation.
It has no cache. Re-evaluating identical snapshots and policies with the same
injected timestamp produces the same result.

## ADR-019: Pure decision engine and explicit explanations

`InventoryHealthEngine` is synchronous, stateless, and independent of Flutter,
repositories, and services. It receives one snapshot, one optional policy, and
an evaluation timestamp. It returns one result whose explanation includes:

- status
- reason code
- quantity
- threshold, when valid and available
- unit
- timestamp
- optional human-readable summary

The UI displays this explanation and never reconstructs the decision.

## ADR-020: One loaded-inventory read

`InventoryServiceHealthReader` adapts the already-loaded `InventoryService`.
It captures immutable scalar snapshots and policies in one pass and never
reloads `SharedPreferences`. `InventoryHealthService` indexes policies once,
captures one timestamp for the batch, invokes the engine exactly once per
snapshot, maps failures to domain values, and sorts results by urgency and then
product name. The resulting evaluation is O(n), apart from the final result
ordering.

## Dependency flow

```text
Inventory Health Screen
        |
        v
InventoryHealthService
        |
        +--> InventoryHealthInputReader
        |          |
        |          v
        |    loaded InventoryService
        |
        +--> InventoryPolicyResolver
        |
        v
InventoryHealthEngine
        |
        v
InventoryHealthResult + InventoryHealthExplanation
```

The engine has no infrastructure dependency. The reader is the only health
component that knows about `InventoryService`. Presentation knows only the
service and domain outcomes. Repository interfaces and persisted schemas remain
unchanged.

## Presentation behavior

The Inventory Health screen supports loading, results, empty, and error states;
pull-to-refresh and an explicit refresh action; four-state filtering; the
engine-provided explanation; and navigation to the existing product batch
screen. It is read-only. A refresh generation token prevents an older
asynchronous result from replacing a newer one.

## Integrity and failure behavior

Reader errors, duplicate product identifiers, duplicate policies, invalid
input batches, and unexpected evaluation failures become explicit
`InventoryHealthFailure` values. Provider or repository exceptions are not
shown by the UI. Invalid data for an individual product produces an `Unknown`
result with a reason code rather than a write or repair attempt.

## Intentionally deferred

The engine does not persist health, cache results, convert units, evaluate
expiry, predict demand, measure consumption, create shopping recommendations,
or edit inventory. Those capabilities require separate future decisions and
must not change this four-state contract implicitly.
