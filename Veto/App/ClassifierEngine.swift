import Foundation
import Observation
import VetoCore

/// Owns the shared `VetoClassifier` for the SwiftUI app and records local-only timings.
@MainActor @Observable
final class ClassifierEngine {
    enum State { case idle, loading, ready, failed(String) }

    private(set) var state: State = .idle
    private(set) var metadata: VetoMetadata?
    private(set) var loadMilliseconds: Double?
    private(set) var lastPrediction: VetoPrediction?
    private(set) var lastTimings: VetoTimings?
    private(set) var firstInferenceMilliseconds: Double?
    private(set) var errorMessage: String?
    /// Process footprint in MB (the figure iOS enforces extension limits on), measured in this app.
    private(set) var footprintBeforeLoadMB: Double?
    private(set) var footprintAfterLoadMB: Double?
    private(set) var footprintAfterFirstClassifyMB: Double?
    private(set) var computeUnits: MLComputeUnitsOption = ClassifierEngine.storedComputeUnits
    private var classifier: VetoClassifier?

    static let computeUnitsKey = "veto.debug.computeUnits"
    static var storedComputeUnits: MLComputeUnitsOption {
        UserDefaults.standard.string(forKey: computeUnitsKey).flatMap(MLComputeUnitsOption.init(rawValue:)) ?? .all
    }

    /// Takes effect on the next launch, so each measurement starts from a fresh process.
    static func storeComputeUnits(_ option: MLComputeUnitsOption) {
        UserDefaults.standard.set(option.rawValue, forKey: computeUnitsKey)
    }

    func loadIfNeeded() async {
        guard case .idle = state else { return }
        state = .loading
        let clock = ContinuousClock()
        let start = clock.now
        footprintBeforeLoadMB = MemoryFootprint.currentMegabytes()
        let units = computeUnits
        do {
            let loaded = try await Task.detached(priority: .userInitiated) { try VetoClassifier.load(computeUnits: units) }.value
            footprintAfterLoadMB = MemoryFootprint.currentMegabytes()
            let elapsed = clock.now - start
            loadMilliseconds = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
            classifier = loaded
            metadata = loaded.metadata
            state = .ready
        } catch {
            state = .failed(Self.describe(error))
        }
    }

    func classify(_ text: String) async {
        guard let classifier else { return }
        errorMessage = nil
        do {
            let (prediction, timings) = try await classifier.classifyTimed(text: text)
            if firstInferenceMilliseconds == nil {
                firstInferenceMilliseconds = timings.totalMilliseconds
                footprintAfterFirstClassifyMB = MemoryFootprint.currentMegabytes()
            }
            lastPrediction = prediction
            lastTimings = timings
        } catch {
            lastPrediction = nil
            errorMessage = Self.describe(error)
        }
    }

    private static func describe(_ error: Error) -> String {
        if case VetoClassifierError.resourceMissing(let name) = error {
            return "\(name) is missing from the build. Import your Veto export with scripts/import-veto-model.sh and rebuild."
        }
        return String(describing: error)
    }
}
