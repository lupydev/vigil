import Foundation

/// A complete reading of the machine at one instant.
public struct Sample: Equatable, Sendable, Codable {
    public let timestamp: Date
    public let processes: [ProcessSnapshot]
    public let resources: ResourceSnapshot

    public init(timestamp: Date, processes: [ProcessSnapshot], resources: ResourceSnapshot) {
        self.timestamp = timestamp
        self.processes = processes
        self.resources = resources
    }
}

/// One process observed at one moment.
public struct ProcessObservation: Equatable, Sendable {
    public let timestamp: Date
    public let snapshot: ProcessSnapshot

    public init(timestamp: Date, snapshot: ProcessSnapshot) {
        self.timestamp = timestamp
        self.snapshot = snapshot
    }
}

/// An ordered window of samples, oldest first.
///
/// This is what separates "busy" from "stuck". A single sample cannot tell the
/// difference; a window can.
public struct SampleHistory: Equatable, Sendable {
    public let samples: [Sample]

    public init(samples: [Sample]) {
        self.samples = samples.sorted { $0.timestamp < $1.timestamp }
    }

    public var latest: Sample? { samples.last }
    public var oldest: Sample? { samples.first }

    public var isEmpty: Bool { samples.isEmpty }

    /// Wall-clock time covered by the window.
    public var span: TimeInterval {
        guard let oldest, let latest else { return 0 }
        return latest.timestamp.timeIntervalSince(oldest.timestamp)
    }

    /// Every observation of one process, oldest first.
    public func observations(of identity: ProcessIdentity) -> [ProcessObservation] {
        samples.compactMap { sample in
            sample.processes
                .first { $0.identity == identity }
                .map { ProcessObservation(timestamp: sample.timestamp, snapshot: $0) }
        }
    }

    /// Drops samples older than `window` relative to the newest sample.
    public func trimmed(to window: TimeInterval) -> SampleHistory {
        guard let latest else { return self }
        let cutoff = latest.timestamp.addingTimeInterval(-window)
        return SampleHistory(samples: samples.filter { $0.timestamp >= cutoff })
    }
}
