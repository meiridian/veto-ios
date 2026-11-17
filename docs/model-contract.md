# Model contract (consumed from Veto `dist/coreml`)

Verified against the actual export (v1, 4-bit palettized, 2026-11-17):

| item | value |
|---|---|
| inputs | `input_ids`, `attention_mask`: int32 `[1, 256]` |
| output | `political_solicitation_probability`: float16 `[1]`, sigmoid probability |
| threshold | `metadata.json` → `threshold` (0.677… for the compressed export; always read it from the metadata); `should_filter = p >= threshold` |
| tokenizer | BERT WordPiece, MiniLM vocab (30,522), lowercase, accents stripped, PAD 0 / UNK 100 / CLS 101 / SEP 102 |
| size | about 11 MB mlpackage (4-bit palettized; the earlier FP16 export was 45.2 MB), min target iOS 17 |
| memory | The Message Filter extension is killed above **24 MB** (measured on an iPhone 14). The model must stay well under that; the FP16 export did not fit. |

Veto exports `parity_fixtures.json` (texts only) and golden token IDs, but **no reference probabilities**.
`scripts/make-python-reference.py` produces them locally by running the *deployed* Core ML package through
coremltools with the exported tokenizer, so the Swift tests verify the Swift runtime exactly (tolerance 0.01) rather
than compression error. It also records the uncompressed model's scores for information only: a compressed export
legitimately differs from them (the export's own quality report lists the deltas and the gates it passed). The file
derives from private weights and stays local.
