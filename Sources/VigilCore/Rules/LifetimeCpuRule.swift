import Foundation

/// Detects work that has been burning CPU since it started.
///
/// This rule needs no history, no window and no storage. The kernel keeps a
/// running total of every nanosecond each process has consumed; divided by the
/// process's age it gives a lifetime average that is strictly more accurate
/// than anything local sampling could reconstruct, because the kernel counted
/// continuously while a sampler only sees the moments it looked.
///
/// Measured on a healthy machine, nothing exceeded 36% and almost everything
/// sat under 10%. A process pinned since birth approaches 100%. The signal
/// separates itself.
///
/// It still requires the process to be hot *now*: a lifetime average alone
/// cannot distinguish work that is stuck from work that finished and went
/// quiet without exiting.
public struct LifetimeCpuRule: AnomalyRule {
    public let identifier = "lifetime-cpu"

    public let lifetimeThreshold: Double
    public let currentThreshold: Double
    public let minimumAge: TimeInterval

    public init(
        lifetimeThreshold: Double = 70,
        currentThreshold: Double = 50,
        minimumAge: TimeInterval = 2 * 3600
    ) {
        self.lifetimeThreshold = lifetimeThreshold
        self.currentThreshold = currentThreshold
        self.minimumAge = minimumAge
    }

    public func evaluate(_ history: SampleHistory) -> [Anomaly] {
        guard let latest = history.latest else { return [] }

        return latest.processes.compactMap { process -> Anomaly? in
            let age = process.age(at: latest.timestamp)
            guard age >= minimumAge else { return nil }

            guard let lifetime = process.lifetimeCpuPercent(at: latest.timestamp),
                  lifetime >= lifetimeThreshold
            else { return nil }

            // Still burning, not merely a process with a heavy past.
            guard process.cpuPercent >= currentThreshold else { return nil }

            return Anomaly(
                id: "\(identifier):\(process.pid):\(Int(process.startedAt.timeIntervalSince1970))",
                title: "\(process.name) has burned \(Format.percent(lifetime)) CPU for its entire \(Format.duration(age)) life",
                detail: """
                    The kernel reports \(Format.duration(process.cumulativeCpuSeconds)) of CPU time \
                    consumed over \(Format.duration(age)) of wall clock, and the process is still \
                    running hot. Work that has never stopped since it started is almost always work \
                    that was abandoned rather than work still making progress.
                    """,
                severity: .critical,
                evidence: [
                    "pid \(process.pid)",
                    "lifetime average \(Format.percent(lifetime))",
                    "current \(Format.percent(process.cpuPercent))",
                    "cpu time \(Format.duration(process.cumulativeCpuSeconds)) over \(Format.duration(age))",
                    process.executablePath,
                ],
                remedy: Remedy(
                    summary: "Confirm the work is genuinely abandoned, then stop the process.",
                    command: "kill -9 \(process.pid)"
                )
            )
        }
    }
}

enum Format {
    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }

    static func duration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded())
        let days = totalSeconds / 86_400
        let hours = (totalSeconds % 86_400) / 3_600
        let minutes = (totalSeconds % 3_600) / 60

        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        // Sub-minute spans show up whenever `--min-age` is used to try a
        // threshold out, and "0m" reads like a bug.
        return "\(totalSeconds)s"
    }
}
