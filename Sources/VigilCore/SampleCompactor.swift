import Foundation

/// Reduces a sample to what could still matter to a rule before it is stored.
///
/// A full sample carries every process on the machine — around 550 of them, or
/// 131 KB. Persisted every minute for seven days that is 1.26 GB, and because
/// the store rewrites the whole file on each append, it would also mean parsing
/// more than a gigabyte of JSON every sixty seconds. A tool that watches for
/// runaway resource use has no business becoming one.
///
/// Sampling still reads every process — the CPU delta needs the complete
/// picture in memory — but only the plausible candidates are written down.
///
/// The floor **must stay below the lowest rule threshold**. `SustainedCpuRule`
/// fires at 80%, so a floor of 50% keeps a wide margin. Lowering a rule
/// threshold below the floor would silently blind it, which is why
/// `validate(against:)` exists.
public struct SampleCompactor: Sendable {
    public let minimumCpuPercent: Double
    public let maximumProcesses: Int

    public init(minimumCpuPercent: Double = 50, maximumProcesses: Int = 20) {
        self.minimumCpuPercent = minimumCpuPercent
        self.maximumProcesses = maximumProcesses
    }

    public func compact(_ sample: Sample) -> Sample {
        let kept = sample.processes
            .filter { $0.cpuPercent >= minimumCpuPercent }
            .sorted { $0.cpuPercent > $1.cpuPercent }
            .prefix(maximumProcesses)

        return Sample(
            timestamp: sample.timestamp,
            processes: Array(kept),
            resources: sample.resources
        )
    }

    /// Rule thresholds this compactor would render undetectable.
    ///
    /// Any returned rule is a configuration mistake: its findings could never
    /// fire because the evidence is discarded before it reaches the store.
    public func blindSpots(against rules: [any AnomalyRule]) -> [String] {
        rules.compactMap { rule in
            guard let cpuRule = rule as? SustainedCpuRule,
                  cpuRule.cpuThreshold < minimumCpuPercent
            else { return nil }
            return "\(rule.identifier) fires at \(Int(cpuRule.cpuThreshold))% "
                + "but samples below \(Int(minimumCpuPercent))% are never stored"
        }
    }
}
