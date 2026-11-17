"""Generate local reference predictions for Core ML parity tests.

Runs the *deployed* Core ML package (via coremltools, with the exported tokenizer) over Veto's
committed, invented parity texts and writes ModelArtifacts/python_reference.json (gitignored:
probabilities derive from the private model). The Swift tests compare against this, so they check
the Swift runtime (tokenizer, input packing, output handling), not model compression error.

The uncompressed Python model's probability is stored too, for information only; compressed
exports legitimately differ from it (see the export's own quality report).

Usage (from the veto repo's environment):
    uv run --project /path/to/veto python scripts/make-python-reference.py /path/to/veto /path/to/veto-ios
"""
import json
import sys
from pathlib import Path

veto_repo, ios_repo = Path(sys.argv[1]), Path(sys.argv[2])
from veto.export import tokenizer as tokmod
from veto.export.fixtures import load_fixtures
from veto.export.parity import coreml_probabilities, load_mlmodel, python_probabilities

bundle = ios_repo / "ModelArtifacts"
meta = json.loads((bundle / "metadata.json").read_text())
threshold = meta["threshold"]
examples = load_fixtures()
texts = [e["text"] for e in examples]

mlmodel = load_mlmodel(bundle / "veto.mlpackage", "CPU_ONLY")
tokenizer = tokmod.load_tokenizer(bundle / "tokenizer")
deployed = coreml_probabilities(mlmodel, tokenizer, texts, meta["max_sequence_length"])
float_model = python_probabilities(veto_repo / "models" / "veto", texts)

out = {
    "note": "Local reference from the deployed Core ML package via coremltools. Derived from private weights; do not commit.",
    "threshold": threshold,
    "examples": [
        {"category": e["category"], "text": e["text"], "probability": float(p),
         "should_filter": bool(p >= threshold), "float_model_probability": float(f)}
        for e, p, f in zip(examples, deployed, float_model)
    ],
}
dest = bundle / "python_reference.json"
dest.write_text(json.dumps(out, indent=1))
flips = sum((p >= threshold) != (f >= threshold) for p, f in zip(deployed, float_model))
print(f"wrote {len(examples)} examples; threshold {threshold}; decisions differing from the uncompressed model: {flips}")
