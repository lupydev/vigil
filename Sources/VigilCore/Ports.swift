import Foundation

/// Reads the current process table.
public protocol ProcessSampler: Sendable {
    func sampleProcesses() throws -> [ProcessSnapshot]
}

/// Reads machine-wide resource usage.
public protocol ResourceSampler: Sendable {
    func sampleResources() throws -> ResourceSnapshot
}

/// Holds the short rolling window that recently-stuck detection depends on.
///
/// Deliberately not a persistence port. Nothing this app learns is worth
/// writing to the user's disk, because the only history that matters over long
/// spans is the one the kernel already keeps.
public protocol SampleStore: Sendable {
    func append(_ sample: Sample) throws
    func history(within window: TimeInterval) throws -> SampleHistory
}

/// Tells the user something changed. Never acts on their behalf.
public protocol Notifier: Sendable {
    func notify(_ anomalies: [Anomaly]) async
}

public protocol Clock: Sendable {
    var now: Date { get }
}

public struct SystemClock: Clock {
    public init() {}
    public var now: Date { Date() }
}

/// A rule that turns observed history into anomalies.
public protocol AnomalyRule: Sendable {
    var identifier: String { get }
    func evaluate(_ history: SampleHistory) -> [Anomaly]
}
