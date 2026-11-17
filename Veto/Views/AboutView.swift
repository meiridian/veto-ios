import SwiftUI
import VetoCore

struct AboutView: View {
    @Environment(ClassifierEngine.self) private var engine
    @State private var selectedUnits = ClassifierEngine.storedComputeUnits

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What Veto does") {
                    Text("Veto detects unsolicited political outreach in text messages. Eligible incoming messages are classified entirely on this device and, if they cross Veto's threshold, are sent to the Junk list by iOS.")
                }
                Section("Privacy") {
                    Label("On-device classification", systemImage: "iphone")
                    Label("No analytics, no network calls, no message logging", systemImage: "lock.shield")
                }
                Section("Versions") {
                    LabeledContent("Veto iOS", value: appVersion)
                    LabeledContent("Veto Model", value: engine.metadata?.modelVersion ?? "unavailable")
                    LabeledContent("Base Model", value: engine.metadata?.baseModel.split(separator: "/").last.map(String.init) ?? "unavailable")
                    if let threshold = engine.metadata?.threshold {
                        LabeledContent("Threshold", value: threshold.formatted(.number.precision(.fractionLength(4))))
                    }
                }
                Section("Development") {
                    if let load = engine.loadMilliseconds {
                        LabeledContent("Model load", value: String(format: "%.0f ms", load))
                    }
                    if let first = engine.firstInferenceMilliseconds {
                        LabeledContent("First classification", value: String(format: "%.1f ms", first))
                    }
                    if let mb = engine.footprintBeforeLoadMB { LabeledContent("Memory before load", value: String(format: "%.1f MB", mb)) }
                    if let mb = engine.footprintAfterLoadMB { LabeledContent("Memory after load", value: String(format: "%.1f MB", mb)) }
                    if let mb = engine.footprintAfterFirstClassifyMB { LabeledContent("Memory after classify", value: String(format: "%.1f MB", mb)) }
                    Picker("Compute units", selection: $selectedUnits) {
                        ForEach(MLComputeUnitsOption.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .onChange(of: selectedUnits) { _, new in ClassifierEngine.storeComputeUnits(new) }
                    Text("Running now with \(engine.computeUnits.rawValue). Changing compute units applies after you force-quit and reopen the app. iOS ends the filter extension above 24 MB. Measurements stay on this device.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Enable the filter") {
                    Text("Settings › Messages › Unknown & Spam › Text Message Filter › Veto. Then turn on Filter Unknown Senders if you want filtering applied.")
                        .font(.footnote)
                }
            }
            .navigationTitle("About")
        }
    }
}
