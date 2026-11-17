# Latency report

Measured 2026-10-30 with Veto model v1 (MiniLM encoder + logistic regression, FP16 Core ML, input length fixed at
256 tokens). Xcode 26.3, simulator runtime iOS 26.3.

**Bottom line:** the only real-device latency numbers come from one iPhone 14, in the app, from a single Debug-build
run of the original 43 MB FP16 model. The decisive finding is about **memory inside the Message Filter Extension**
(section 1): that model exceeded the extension's 24 MB limit and was killed. A compressed ~11 MB export was imported
afterward; its fit and extension latency are not yet confirmed on a device. Simulator numbers describe the
development Mac, not any iPhone, and were measured with the FP16 model except where noted.

## 1. Real device: the extension memory limit

Observed on an iPhone 14 (iOS 27.0.1) in Console.app while a text arrived, with the 43 MB FP16 model:

```
memorystatus: VetoMessageFilter exceeded mem limit: ActiveHard 24 MB (fatal)
Process VetoMessageFilter killed by jetsam reason per-process-limit
```

The extension died about 0.3 s after starting (while mapping the model), returned no answer, and the message stayed in
Unknown Senders (fail-open). The model has to be compressed. The Veto export now offers 4-bit palettization (about
11 MB; the export's Mac measurement showed about 5 MB peak footprint growth with CPU-only compute, which is a proxy,
not an iPhone result). Re-measuring on the device is the next step.

## 1b. Real device: iPhone 14, in the app (FP16 model)

Read from the app's Test and About screens on one iPhone 14 (iOS 27.0.1), Debug build run from Xcode, one
classification after a cold launch.

| Metric | Value |
|---|---|
| Model load | 1,512 ms |
| Tokenize | 3.98 ms |
| Inference (first call) | 793 ms |
| First classification, total | 797 ms |

How to read this:
- The first call includes one-time Core ML setup, so it overstates what a typical message costs. Warm latency on the
  phone has **not** been measured.
- Debug builds are unoptimized, which likely inflates the tokenizer time (the Python tokenizer takes about 0.15 ms).
  The Release-build simulator run in section 3 suggests build configuration barely affects inference.
- This is app-process timing. iOS may give an extension different resources and stricter limits.

## 2. Reference: Veto's Mac benchmark (Python side)

From the export's own benchmark (Apple M2 Pro, macOS 15.6.1, 200 runs after 20 warm-up runs, medians):

| Stage | Compute units | Median | p95 |
|---|---|---|---|
| Tokenization | n/a | 0.147 ms | 0.191 ms |
| Core ML inference | All (CPU/GPU/Neural Engine) | 2.24 ms | 2.56 ms |
| Core ML inference | CPU only | 5.61 ms | 6.32 ms |
| Tokenize + inference | All | 2.43 ms | 2.82 ms |
| Tokenize + inference | CPU only | 5.81 ms | 6.57 ms |

This shows what the model can do with hardware acceleration on a fast Mac. It says nothing about an iPhone.

## 3. iOS Simulator (development Mac)

Warm latency of the same classification path (30 runs after one warm-up; median and 95th percentile), from
`ModelParityTests.testWarmInferenceLatencyIsReported`. Core ML parity with Python was checked in the same runs.

| Simulated device | Configuration | Warm median | p95 | Python parity (70 fixtures) |
|---|---|---|---|---|
| iPhone 14 | Debug | 48.2 ms | 55.8 ms | max diff 0.0037, 0 decision disagreements |
| iPhone 17 | Debug | 47.1 ms | 50.5 ms | max diff 0.0037, 0 decision disagreements |
| iPhone 17 Pro | Debug | 47.0 ms | 49.1 ms | max diff 0.0037, 0 decision disagreements |
| iPhone 17 Pro | Release | 45.6 ms | 48.1 ms | max diff 0.0037, 0 decision disagreements |

How to read this:
- **A simulator does not emulate the iPhone's chip.** It runs the model on the Mac, so the differences between rows are
  noise. Use these rows to confirm the model runs and matches Python on each device configuration, not to compare
  phones.
- The ~47 ms is far above the 2–6 ms of section 2, so the simulator evidently does not use the Neural Engine or GPU the
  way a native run does. Treat it as a no-accelerator worst case.
- Debug vs Release differs by about 3%, so inference time is dominated by Core ML, not Swift code.
- iPhone 18 Pro could not be tested: no such simulator exists in Xcode 26.3.

## 4. What is not measured yet

| Missing | Why it matters |
|---|---|
| Warm latency on a real iPhone | The first-call figure is mostly one-time setup. |
| Release build on a real iPhone | Debug builds are not representative. |
| Latency and model load inside the Message Filter Extension | iOS limits extension time as well as memory. A slow extension can be killed, and then messages pass through unfiltered. |
| Peak memory of the compressed model in the extension | The FP16 model was killed at 24 MB. The ~11 MB model's footprint on a device is not yet confirmed. |
| Latency of the compressed model | Section 3's simulator numbers are for FP16; 4-bit weights can change speed. |
| Other iPhones | Only an iPhone 14 has been tried. Older devices without a fast Neural Engine may be much slower. |

If the compressed model still doesn't fit or is too slow, further reductions (more aggressive compression, a pruned
vocabulary, a smaller encoder) belong in the `veto` export pipeline, not in this repository.

## 5. Reproduce

Simulator latency (needs your own model imported; see [getting-started-xcode.md](getting-started-xcode.md)):

```bash
xcodegen generate
xcodebuild test -project Veto.xcodeproj -scheme Veto \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:VetoTests/ModelParityTests
```

Look for the `VETO_LATENCY` line in the output. For a Release configuration add
`-configuration Release ENABLE_TESTABILITY=YES`.

Real device: run the app from Xcode on your iPhone, classify a message, and read the timings on the Test tab; model load
and first-classification times are on the About tab. Use Instruments (Time Profiler, Allocations) attached to the
`VetoMessageFilter` process for extension measurements, or watch Console.app filtered by `veto` for the extension's
decision lines and any `exceeded mem limit` kill ([device-testing.md](device-testing.md)).
