import Foundation

/// A bounded ring of recent samples, held in memory and never written to disk.
///
/// The window exists only for `SustainedCpuRule`, which needs to see a
/// long-lived process stay hot across consecutive readings. Everything else is
/// answered from the kernel's own counters at the moment of the check.
///
/// Both dimensions are capped: at most `maximumSamples` readings, each already
/// reduced to the processes that could plausibly matter. Nothing here grows
/// without bound, and nothing survives a restart — which costs almost nothing,
/// because `LifetimeCpuRule` works from the first reading with no warm-up at
/// all.
public final class InMemorySampleStore: SampleStore, @unchecked Sendable {
    private let lock = NSLock()
    private let maximumSamples: Int
    private let compactor: SampleCompactor
    private var samples: [Sample] = []

    public init(maximumSamples: Int = 120, compactor: SampleCompactor = SampleCompactor()) {
        self.maximumSamples = maximumSamples
        self.compactor = compactor
    }

    public func append(_ sample: Sample) throws {
        lock.lock()
        defer { lock.unlock() }

        samples.append(compactor.compact(sample))
        if samples.count > maximumSamples {
            samples.removeFirst(samples.count - maximumSamples)
        }
    }

    public func history(within window: TimeInterval) throws -> SampleHistory {
        lock.lock()
        defer { lock.unlock() }
        return SampleHistory(samples: samples).trimmed(to: window)
    }

    /// Rule thresholds this store's compaction would render undetectable.
    public func blindSpots(against rules: [any AnomalyRule]) -> [String] {
        compactor.blindSpots(against: rules)
    }

    /// Rough resident size of the retained window, for display only.
    public var approximateBytes: Int {
        lock.lock()
        defer { lock.unlock() }
        let processCount = samples.reduce(0) { $0 + $1.processes.count }
        return samples.count * MemoryLayout<Sample>.stride
            + processCount * MemoryLayout<ProcessSnapshot>.stride
    }
}
