import Foundation

/// Detects a long-lived process that got stuck recently.
///
/// `LifetimeCpuRule` catches work that has burned since birth using nothing but
/// the kernel's counters. It cannot catch the other shape: a process that
/// behaved for weeks and jammed two hours ago. Thirty days of good behaviour
/// dilutes its lifetime average to near zero, so that case needs an observation
/// window — but only a short one, held in memory and never written down.
///
/// The `maximumLifetimePercent` ceiling keeps the two rules mutually exclusive
/// by construction, so a single stuck process is never reported twice.
public struct SustainedCpuRule: AnomalyRule {
    public let identifier = "recently-stuck"

    public let cpuThreshold: Double
    public let maximumLifetimePercent: Double
    public let minimumAge: TimeInterval
    public let minimumSustainedWindow: TimeInterval
    public let minimumObservations: Int

    public init(
        cpuThreshold: Double = 80,
        maximumLifetimePercent: Double = 70,
        minimumAge: TimeInterval = 2 * 3600,
        minimumSustainedWindow: TimeInterval = 10 * 60,
        minimumObservations: Int = 3
    ) {
        self.cpuThreshold = cpuThreshold
        self.maximumLifetimePercent = maximumLifetimePercent
        self.minimumAge = minimumAge
        self.minimumSustainedWindow = minimumSustainedWindow
        self.minimumObservations = minimumObservations
    }

    public func evaluate(_ history: SampleHistory) -> [Anomaly] {
        guard let latest = history.latest else { return [] }

        return latest.processes.compactMap { process -> Anomaly? in
            guard process.cpuPercent >= cpuThreshold else { return nil }

            let age = process.age(at: latest.timestamp)
            guard age >= minimumAge else { return nil }

            // Burning since birth belongs to LifetimeCpuRule.
            let lifetime = process.lifetimeCpuPercent(at: latest.timestamp) ?? 0
            guard lifetime < maximumLifetimePercent else { return nil }

            let observations = history.observations(of: process.identity)
            guard observations.count >= minimumObservations,
                  let first = observations.first
            else { return nil }

            let observedSpan = latest.timestamp.timeIntervalSince(first.timestamp)
            guard observedSpan >= minimumSustainedWindow else { return nil }

            // A single dip below the threshold means the process is working in
            // bursts, not stuck. That is normal behaviour, not an anomaly.
            guard observations.allSatisfy({ $0.snapshot.cpuPercent >= cpuThreshold })
            else { return nil }

            let peak = observations.map(\.snapshot.cpuPercent).max() ?? process.cpuPercent

            return Anomaly(
                id: "\(identifier):\(process.pid):\(Int(process.startedAt.timeIntervalSince1970))",
                title: "\(process.name) has been stuck at \(Format.percent(process.cpuPercent)) CPU for \(Format.duration(observedSpan))",
                detail: """
                    This process has stayed above \(Format.percent(cpuThreshold)) in every reading \
                    for the last \(Format.duration(observedSpan)), yet its lifetime average is only \
                    \(Format.percent(lifetime)) across \(Format.duration(age)). It behaved normally \
                    until recently, which points at work that jammed rather than work that was \
                    always heavy.
                    """,
                severity: .critical,
                evidence: [
                    "pid \(process.pid)",
                    "current \(Format.percent(process.cpuPercent))",
                    "peak \(Format.percent(peak))",
                    "lifetime average \(Format.percent(lifetime))",
                    "age \(Format.duration(age))",
                    "\(observations.count) consecutive readings above threshold",
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
