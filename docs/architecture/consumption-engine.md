# Consumption Engine

Phase 7.1 implements RFC-002 and ADR-021 through ADR-025. Consumption is
derived, read-only state. The engine answers one question: **How has this
product been consumed over time?**

## RFC-002: Consumption history

The feature transforms the existing inventory movement history into immutable,
provider-independent quantity-change events. It reports only observed history.
It does not forecast depletion, recommend purchases, update shopping lists, or
issue notifications.

The supported patterns are deliberately descriptive:

- `noHistory`
- `noObservedConsumption`
- `adjustmentOnly`
- `consumptionObserved`
- `consumptionWithOtherChanges`

These patterns describe recorded events and are not predictive analytics.

## ADR-021: Consumption is event-derived

The already-loaded `InventoryService` is the sole source. Its movement log is
the authoritative record of signed inventory changes. Purchase workflows
already record their stock effects as inventory movements, so Phase 7.1 does
not read `PurchaseRepository` and does not duplicate purchase events.

`InventoryServiceConsumptionReader` captures current product snapshots once and
groups movements in one scan. It never reloads `SharedPreferences`.

## ADR-022: No future depletion prediction

The engine does not calculate consumption rates, days remaining, run-out dates,
or forecasts. Observation start and end describe only the recorded period.

## ADR-023: No purchase recommendations

The feature has no dependency on shopping lists, low-stock policy,
notifications, or Inventory Health. Results never create or remove shopping
items and never recommend quantities.

## ADR-024: Timeline-compatible quantity events

`ConsumptionEvent` contains an event ID, product ID, timestamp, previous and
current quantity, signed delta, typed reason, typed source, unit, and optional
source reference. This is sufficient for a future Inventory Timeline without
introducing that abstraction in this phase.

Movement types are normalized centrally:

- consumption movements are counted as observed consumption;
- purchases and additions are replenishment;
- manual and batch adjustments remain separate reductions or additions;
- batch deletion and purchase reversal are not consumption;
- unknown movement types remain visible but are never silently classified as
  consumption;
- zero-delta metadata movements are omitted from quantity history.

Previous and current quantities are reconstructed in one reverse pass anchored
at current stock. Duplicate timestamps preserve recorded sequence. Missing or
out-of-order timestamps, duplicate event IDs, incompatible units, and
impossible reconstructed quantities produce explicit failures rather than
invented history.

## ADR-025: Profiles are derived and never persisted

`ConsumptionProfile`, `ConsumptionResult`, and `ConsumptionExplanation` are
created on demand. They have no repository, schema, migration, or permanent
cache. Identical snapshots and events produce identical results.

Every successful result contains an engine-generated explanation with its
pattern, reason code, event counts, observation period, and summary. The UI
displays this explanation and does not reconstruct it.

## Architecture

```text
Consumption Screen
        |
        v
ConsumptionService
        |
        +--> ConsumptionInputReader
        |          |
        |          v
        |    loaded InventoryService
        |
        v
ConsumptionEngine
        |
        v
ConsumptionEventBuilder
        |
        v
ConsumptionResult + ConsumptionExplanation
```

The reader is the only consumption component that imports `InventoryService`.
The engine and event builder are synchronous and contain no Flutter,
repository, or service imports. Presentation depends only on the service and
consumption domain outcomes.

## Performance and consistency

The reader performs one product snapshot capture and one movement scan. The
service invokes the engine once per product, and the builder processes each
product event once. Total evaluation is O(products + movements), with no
repeated repository calls and no unnecessary sorting.

The presentation uses a refresh generation token so an older asynchronous read
cannot overwrite newer results. Changing the selected product uses the already
evaluated batch and performs no additional read.

## Data limitations

- Initial stock created before movement tracking appears as an inferred starting
  balance.
- Existing product deletion removes that product's movement history.
- Purchase movement timestamps represent the inventory operation time, which
  may differ from the purchase date.
- Legacy deserialization replaces an absent movement timestamp before the
  consumption reader can observe that absence.
- Unit changes are not converted; incompatible histories fail explicitly.

## Intentionally deferred

Prediction, days remaining, consumption-rate analytics, shopping
recommendations, alerts, notifications, price intelligence, AI, cloud sync,
Inventory Timeline, persistence redesign, and inventory editing remain outside
Phase 7.1.
