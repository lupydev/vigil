import Foundation

/// Detects memory that has overflowed onto the SSD.
///
/// Heavy swap is quieter than a runaway process — the CPU can look calm while
/// the machine pages against disk continuously — and it does not recover on its
/// own. Once the pages are written, only a restart reclaims them.
public struct SwapPressureRule: AnomalyRule {
    public let identifier = "swap-pressure"

    public let warningFraction: Double
    public let criticalFraction: Double

    public init(warningFraction: Double = 0.70, criticalFraction: Double = 0.90) {
        self.warningFraction = warningFraction
        self.criticalFraction = criticalFraction
    }

    public func evaluate(_ history: SampleHistory) -> [Anomaly] {
        guard let latest = history.latest else { return [] }

        // No swap allocated is the healthiest possible state, not a division
        // waiting to happen.
        guard let fraction = latest.resources.swapUsedFraction else { return [] }
        guard fraction >= warningFraction else { return [] }

        let severity: Severity = fraction >= criticalFraction ? .critical : .warning
        let used = ByteFormat.gigabytes(latest.resources.swapUsedBytes)
        let total = ByteFormat.gigabytes(latest.resources.swapTotalBytes)

        return [
            Anomaly(
                id: identifier,
                title: "Swap is \(Int(fraction * 100))% full (\(used) of \(total))",
                detail: """
                    Memory has overflowed onto the SSD. The system is paging against disk, \
                    which generates heat and wear even when CPU looks idle. macOS does not \
                    release these pages while running — a restart is what reclaims them.
                    """,
                severity: severity,
                evidence: [
                    "swap used \(used)",
                    "swap total \(total)",
                    "memory free \(Int(latest.resources.memoryFreeFraction * 100))%",
                ],
                remedy: Remedy(
                    summary: "Close what you no longer need, then restart to reclaim the swap.",
                    command: nil
                )
            )
        ]
    }
}

enum ByteFormat {
    static func gigabytes(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
    }
}
