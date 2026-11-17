import IdentityLookup
import VetoCore
import os

/// Classifies messages iOS hands to the filter. Fails open: any problem leaves the message alone.
final class MessageFilterExtension: ILMessageFilterExtension {
    private static let log = Logger(subsystem: "veto", category: "extension")

    /// Loaded once per extension process. `nil` (load failure) means every message is allowed.
    /// Logs the error type only, never message content.
    private static let classifier: VetoClassifier? = {
        let sampler = FootprintSampler(log: log)
        sampler.start()
        defer { sampler.stop() }
        do { return try VetoClassifier.load(computeUnits: .cpuOnly) }
        catch {
            log.error("model load failed; allowing all messages: \(String(describing: type(of: error)), privacy: .public)")
            return nil
        }
    }()
}

extension MessageFilterExtension: ILMessageFilterQueryHandling {
    func handle(_ queryRequest: ILMessageFilterQueryRequest,
                context: ILMessageFilterExtensionContext,
                completion: @escaping (ILMessageFilterQueryResponse) -> Void) {
        let response = ILMessageFilterQueryResponse()
        response.action = .none
        if let body = queryRequest.messageBody, !body.isEmpty,
           let classifier = Self.classifier, classifier.shouldFilter(body) {
            response.action = .junk
        }
        // Outcome only: no text, sender or probability.
        Self.log.notice("handled a message: action=\(response.action == .junk ? "junk" : "none", privacy: .public)")
        completion(response)
    }
}
