# DAN-0001 benchmark fixture

`DAN-0001` identifies the existing private Danube receipt used for manual calibration. The original image is **not committed** because no approved repository policy or redacted source asset is available.

The committed `benchmark.json` contains a deliberately synthetic, redacted proxy. Its ground truth was manually declared for that synthetic fixture only. It must not be reported as accuracy for the original private receipt.

## Private manual placement

1. Create `benchmark/DAN-0001/private/` locally.
2. Place the private image at `benchmark/DAN-0001/private/receipt.jpg`.
3. Keep the directory untracked; `.gitignore` excludes it.
4. Remove or redact payment details, loyalty identifiers, phone numbers, personal tax identifiers, addresses tied to a person, and other sensitive content before sharing any derived fixture.
5. Run the existing OCR platform locally and export a provider-independent block fixture with stable fixture keys.
6. Have a human reviewer declare element types, line composition, completeness, and unassigned keys without copying engine output.
7. Store an approved redacted fixture and its manual ground truth as a new fixture version only after privacy review.

Product verification photos remain local manual references. They are not training data and must not be committed as benchmark inputs.
