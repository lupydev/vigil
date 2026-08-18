import Foundation

/// Identifies a process across samples.
///
/// A bare pid is not enough: macOS reuses pids, so a long-lived observation
/// window can otherwise stitch together two unrelated processes and report a
/// sustained anomaly that never happened. Pairing the pid with its start time
/// makes the identity stable.
public struct ProcessIdentity: Hashable, Sendable, Codable {
    public let pid: Int32
    public let startedAt: Date

    public init(pid: Int32, startedAt: Date) {
        self.pid = pid
        self.startedAt = startedAt
    }
}

/// One observation of a single process at a point in time.
public struct ProcessSnapshot: Equatable, Sendable, Codable {
    public let identity: ProcessIdentity
    public let name: String
    public let executablePath: String

    /// CPU utilization as reported by the platform.
    ///
    /// This is a decaying average over roughly the last minute, not a lifetime
    /// average, and it can exceed 100% on multi-core machines. It answers "is
    /// this process hot right now?" and says nothing about for how long — which
    /// is why sustained-load detection needs a history, not a single reading.
    public let cpuPercent: Double

    /// Total CPU time the process has consumed since it started.
    ///
    /// This is the kernel's own running total, and it is the reason this app
    /// needs no database. Divided by the process's age it yields a lifetime
    /// average that no amount of local sampling could reconstruct as
    /// accurately: the kernel counted every nanosecond, a sampler only sees
    /// the moments it happened to look.
    public let cumulativeCpuSeconds: Double

    public let memoryBytes: UInt64

    public init(
        identity: ProcessIdentity,
        name: String,
        executablePath: String,
        cpuPercent: Double,
        cumulativeCpuSeconds: Double,
        memoryBytes: UInt64
    ) {
        self.identity = identity
        self.name = name
        self.executablePath = executablePath
        self.cpuPercent = cpuPercent
        self.cumulativeCpuSeconds = cumulativeCpuSeconds
        self.memoryBytes = memoryBytes
    }

    public var pid: Int32 { identity.pid }
    public var startedAt: Date { identity.startedAt }

    /// How long the process has existed, as of `referenceDate`.
    public func age(at referenceDate: Date) -> TimeInterval {
        referenceDate.timeIntervalSince(identity.startedAt)
    }

    /// Average CPU consumed across the process's whole life, as a percentage of
    /// one core. `nil` for a process too young to divide by.
    ///
    /// On a healthy machine almost nothing exceeds 35%. A process that has been
    /// pinned since it started approaches 100% — which makes this single number,
    /// available from one reading, enough to identify abandoned work.
    public func lifetimeCpuPercent(at referenceDate: Date) -> Double? {
        let age = age(at: referenceDate)
        guard age >= 1 else { return nil }
        return (cumulativeCpuSeconds / age) * 100
    }
}
