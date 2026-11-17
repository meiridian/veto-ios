import Foundation
import VetoCore
import os

/// Logs the extension's memory footprint (numbers only) while the model loads, so a kill by iOS's
/// 24 MB limit still leaves the last readings in Console. Diagnostic; not needed for filtering.
final class FootprintSampler: @unchecked Sendable {
    private let log: Logger
    private let stopped = OSAllocatedUnfairLock(initialState: false)

    init(log: Logger) { self.log = log }

    func start() {
        let initial = MemoryFootprint.currentMegabytes() ?? -1
        log.notice("footprint at start: \(initial, format: .fixed(precision: 1), privacy: .public) MB")
        Thread.detachNewThread { [self] in
            var reported = initial
            while !stopped.withLock({ $0 }) {
                if let now = MemoryFootprint.currentMegabytes(), now >= reported + 1 {
                    reported = now
                    log.notice("footprint rising: \(now, format: .fixed(precision: 1), privacy: .public) MB")
                }
                usleep(2_000)
            }
        }
    }

    func stop() {
        stopped.withLock { $0 = true }
        let final = MemoryFootprint.currentMegabytes() ?? -1
        log.notice("footprint after load: \(final, format: .fixed(precision: 1), privacy: .public) MB")
    }
}
