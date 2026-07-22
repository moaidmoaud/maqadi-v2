# Receipt Calibration and Benchmark Framework

## Purpose

Sprint RC-1 makes Receipt Understanding and Receipt Line Builder measurable and centrally calibratable. It introduces internal read-only tooling only: no production decision, persistence, repository access, receipt validation, matching, purchase, inventory, or shopping behavior is added.

The dependency flow is:

```text
Manual benchmark ground truth + provider-independent OCR fixture
                              ↓
                  ReceiptBenchmarkRunner
                    ↙                 ↘
        ReceiptUnderstanding      ReceiptLineBuilder
                    ↘                 ↙
             immutable comparisons and metrics
                              ↓
                    read-only report/debug UI
```

The runner invokes Receipt Understanding once and Receipt Line Builder once. Comparators consume their immutable results. Benchmark code has no production writes, clocks, repositories, settings, or cloud dependencies.

## Architecture decisions

- **ADR-040 — Calibration changes parameters, never architecture.** Calibration values enter the existing line engine through backward-compatible constructor injection.
- **ADR-041 — A calibration change must improve the benchmark without changing architecture.** Policy edits are code-reviewed changes, not runtime settings.
- **ADR-042 — Improvements are benchmark verified.** The committed baseline and all existing tests are rerun before accepting a default change.
- **ADR-043 — Ground truth is manually verified.** Expected output is declared independently and is never generated from actual engine output.
- **ADR-044 — Each phase leaves cleaner data.** Reports expose element, line, role, completeness, and unassigned mismatches for the next stage.
- **ADR-045 — Production changes preserve or improve benchmarks.** A changed default is rejected if any approved case regresses without an explicitly reviewed fixture correction.

## Calibration policy

`ReceiptCalibrationPolicy` is immutable, not persisted, and contains only tolerances already used by the Phase 8.1 grouping algorithm:

| Field | Default | Meaning |
| --- | ---: | --- |
| `rowVerticalDistanceTolerance` | `0.75` | Maximum median-height-normalized vertical distance for row grouping. |
| `rowMinimumOverlapRatio` | `0.30` | Minimum vertical overlap that independently permits row grouping. |
| `columnGapTolerance` | `8.00` | Maximum median-height-normalized horizontal gap within a column. |

These defaults preserve Phase 8.1 behavior. There is no global mutable policy, settings lookup, runtime slider, or experimental persistence.

## Fixture and ground-truth policy

`benchmark/DAN-0001/benchmark.json` combines one canonical provider-independent fixture definition with its manual ground truth. Every OCR block has a stable `fixtureKey`. Actual elements are mapped to keys by exact recognized text and bounding-box signature, including deterministic occurrence order for duplicate signatures. Expected lines use their stable product key as identity, or their first populated structural role for orphan lines; matching never relies on list index or runtime-generated element IDs.

Ground truth declares expected element types, line role references, completeness, and unassigned elements. It remains separate from actual output even when the current engine disagrees. `ocrTextVerified` is false for the committed proxy, so OCR accuracy is explicitly unavailable.

### DAN-0001 privacy status

The existing Danube source receipt is private and is not committed. The committed data is a synthetic, redacted proxy used only to exercise and baseline the framework. Its manual ground truth applies only to that proxy and must not be presented as accuracy for the original receipt.

For local manual calibration, place an appropriately protected image at `benchmark/DAN-0001/private/receipt.jpg`. The entire `private` directory is ignored. Export only provider-independent blocks, redact sensitive content, assign stable keys, and have a human reviewer declare expected structure without copying engine output. The fixture README contains the reproducible procedure. Product verification photos remain local references and are not training data.

## Comparison and metric formulas

- `understandingAccuracy = correctlyClassifiedExpectedElements / expectedElementCount`.
- `lineGroupingPrecision = correctlyGroupedLines / actualLineCount`.
- `lineGroupingRecall = correctlyGroupedLines / expectedLineCount`.
- `lineGroupingF1 = 2 × precision × recall / (precision + recall)`.
- Empty expected and actual sets produce `1.0`; a non-empty numerator against an empty comparison denominator produces `0.0`; F1 is `0.0` when precision plus recall is zero.
- Element reports include expected/actual counts, correct, misclassified, missing, unexpected, per-type counts, and unknown count.
- Line reports include expected/actual/correct counts, missing and unexpected lines, role and completeness mismatches, completeness distributions, and expected-versus-actual unassigned elements.

OCR accuracy is calculated only when independently verified OCR text exists. RC-1 therefore returns `null` and displays **Unavailable** for DAN-0001.

## Manual-correction estimate

The estimate starts with one correction per distinct misclassified, missing, or unexpected element key. It then adds one for each missing line creation, unexpected line removal, role reassignment, completeness repair, or unassigned correction only when none of that issue's element keys was already counted. Counted keys are retained across categories to avoid charging twice for one underlying error.

This is a deterministic structural estimate, not observed user telemetry or an effort-duration prediction.

## Debug and calibration workflow

1. Load `DAN-0001` and run the committed synthetic benchmark.
2. Review the baseline metrics, detailed mismatches, and expected/actual/mismatch overlays.
3. Inspect engine-provided anchor, role, normalized distance, overlap, row/column, rule, confidence-factor, rejected-candidate, reason, and completeness evidence.
4. Change policy defaults in code only when justified.
5. Rerun the benchmark and full test suite.
6. Accept the change only if every approved fixture improves or remains stable and architecture contracts remain unchanged.

The UI does not reconstruct grouping evidence and provides no editing or production mutation actions.

## Current synthetic baseline

For `DAN-0001` fixture version `synthetic-proxy-v1`:

- Understanding: 8 of 9 expected elements correct (`88.9%`); `price-b` is currently classified as `Total` rather than `Price`.
- Lines: 1 correct of 2 expected, 3 actual; precision `33.3%`, recall `50.0%`, F1 `40.0%`.
- Unassigned: 3 actual; the receipt total is expected to be unassigned but is currently emitted as an extra orphan line.
- Manual corrections estimate: 2.
- OCR accuracy: unavailable.

The mismatch is intentionally retained as measurable baseline evidence. Ground truth is not weakened to make current output appear correct.

## Adding future receipts

For `PAN-0001`, `OTH-0001`, or another receipt:

1. Create `benchmark/<ID>/README.md` and one canonical redacted/synthetic fixture definition.
2. Use unique stable fixture keys and provider-independent OCR blocks.
3. Declare element, line, role, completeness, and unassigned ground truth through independent human review.
4. Mark whether OCR text itself was independently verified.
5. Add parser, baseline, mismatch, determinism, and report tests.
6. Record privacy status and local placement steps; never commit unredacted payment, loyalty, contact, personal tax, or location identifiers by default.
7. Require every calibration proposal to preserve or improve all approved fixtures.

## Known limitations

- One synthetic proxy cannot demonstrate merchant, language, layout, camera, or OCR-provider generalization.
- The private DAN-0001 image has not been executed by automated tests and has no committed verified OCR ground truth.
- Exact text-and-geometry mapping assumes a stable provider-independent fixture; revised OCR requires a reviewed fixture version.
- Manual-correction count approximates structural edits and cannot measure actual reviewer effort.
- Calibration currently covers only the three geometric tolerances already present in Phase 8.1; future architecture-approved tolerances should be added only when the existing engine genuinely uses them.
