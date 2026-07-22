# Receipt Line Builder

## Status and decisions

Phase 8.1 implements RFC-006 and the approved Receipt Line Builder decisions:

- ADR-033: the builder groups receipt structure, never business meaning.
- ADR-034: incomplete receipt lines are valid intermediate results.
- ADR-035 and ADR-039: spatial relationships outweigh textual similarity.
- ADR-037: receipt lines reference receipt elements and never duplicate them.
- ADR-038: the builder groups structure, not correctness.

The engine answers only: **Which Receipt Elements belong to the same receipt line?**

## Dependency flow

```text
ReceiptUnderstandingResult.elements
  -> ReceiptLineBuilderService
  -> ReceiptLineBuilderEngine
  -> immutable ReceiptLineResult
```

The engine consumes only provider-independent `ReceiptElement` domain objects. It has no dependency on Flutter, OCR providers, ML Kit, repositories, persistence, product matching, purchases, inventory, shopping, analytics, AI, or cloud services.

## Reference-only domain

`ReceiptLine` contains only:

- deterministic line ID;
- nullable product reference;
- nullable price, quantity, discount, tax, and line-total references;
- completeness;
- immutable engine evidence.

It never copies element text, type, confidence, bounding boxes, or classification evidence.

`ReceiptLineResult` contains immutable collections of lines, unassigned element references, and product-specific failures. An `UnassignedReceiptElement` contains only an element ID, reason code, and grouping evidence.

## Completeness

- `Complete`: product and price.
- `Partial`: product without price, including product with quantity or other attached roles but no price.
- `Orphan`: one unattached price, quantity, discount, tax, or line-total reference.

These states describe structural completeness only. They do not validate product identity, quantity, monetary value, tax, discount, or arithmetic correctness.

## Input partitioning

Product, price, quantity, discount, tax, and total elements with valid geometry are eligible for spatial grouping.

Header, footer, metadata, store-name, and unknown elements never become lines. They are returned through `unassignedElements` with structural-exclusion evidence.

Elements without usable geometry are never spatially grouped and are returned as unassigned with `geometryUnavailable`. Invalid non-null geometry also produces a product-specific failure.

## Geometry normalization

The engine calculates the median positive height of bounded eligible elements. All row distance, horizontal distance, vertical overlap, and column-gap decisions are normalized against that median. No fixed pixel tolerance is used.

The approved grouping sequence is fixed:

1. canonical spatial ordering;
2. rows;
3. columns within rows;
4. product anchors;
5. quantities;
6. prices;
7. line-scoped totals;
8. discounts;
9. taxes;
10. orphan generation.

Canonical ordering and spatial organization are O(n log n). Row construction is a forward sweep. Role candidates use ordered spatial lookup rather than an all-pairs candidate matrix.

## Spatial grouping

Rows are admitted using normalized vertical-centre distance and vertical overlap. Columns are established only after row membership, using normalized horizontal gaps. Product anchors and role candidates must share an admitted row and column.

Nearest-anchor selection uses normalized vertical and horizontal distance, overlap, column evidence, canonical order, and stable element IDs. When multiple candidates compete for one role, the closer candidate is retained and rejected candidates remain available as independent orphan lines.

The engine does not inspect product names or use textual similarity to create relationships. Mixed Arabic and English content is therefore handled through geometry without language-specific business assumptions.

## Receipt totals

A total may populate `lineTotalElementId` only when it shares an established row and column with a product anchor. A receipt-level total on its own summary row can never populate a product line. It becomes a line-total-only orphan instead.

This is a structural decision only; the builder never calculates or verifies the total.

## Evidence and deterministic identity

Every line includes immutable evidence containing:

- anchor element reference;
- attached element references;
- normalized vertical and horizontal distances;
- overlap metrics;
- row and column evidence;
- applied grouping rule;
- rejected candidate IDs and reasons;
- explanatory confidence factors without a confidence score;
- engine-generated summary.

Line IDs use unsigned 64-bit FNV-1a over completeness and the ordered role-to-element-ID mapping. No random value, UUID, clock, or runtime `hashCode` is used. Identical inputs produce identical line assignments, ordering, IDs, evidence, and rejection decisions.

## Service boundary

`ReceiptLineBuilderService` validates unique non-empty IDs and geometry, invokes the engine exactly once for valid input, and verifies:

- every output reference exists;
- role references match their structural element types;
- elements without geometry are not grouped;
- no element occupies conflicting roles;
- completeness and anchor evidence are consistent;
- evidence references are valid;
- every input element is accounted for by a line or unassigned result;
- invalid geometry is safely isolated and reported.

Unsafe duplicate IDs fail the batch because reference integrity cannot be guaranteed. Unexpected implementation exceptions are converted to `ReceiptLineFailure`.

## Presentation

The read-only debug screen exposes loading, results, empty, error, and retry states. It shows source elements, receipt lines, completeness filtering, grouping overlays, selected-element highlighting, unassigned elements, geometry-unavailable evidence, metrics, and rejected candidates.

Presentation resolves references for display but never reconstructs grouping, completeness, metrics, or evidence. It offers no editing or business action.

## Data integrity and performance

- Everything is derived in memory and never persisted.
- Inputs and Phase 8.0 models are not mutated.
- Result collections and evidence collections are immutable.
- Geometry is sorted canonically and grouped without repository access.
- There is no quadratic all-pairs candidate matrix.
- No OCR, matching, inventory, purchase, or shopping behavior changes.

## Intentionally deferred

Receipt-item construction, product matching, business validation, financial correctness, product identity, purchase creation, inventory changes, shopping changes, AI/LLM processing, cloud processing, persistence, and manual line editing remain outside Phase 8.1.
