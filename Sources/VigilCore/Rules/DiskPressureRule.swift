import Foundation

/// Detects a disk with too little headroom left.
///
/// Low disk is rarely the cause of heat, but it starves swap and caches, so it
/// turns unrelated problems into worse ones. It is reported as context, not as
/// an emergency, unless it gets genuinely tight.
public struct DiskPressureRule: AnomalyRule {
    public let identifier = "disk-pressure"

    public let warningFreeFraction: Double
    public let criticalFreeFraction: Double

    public init(warningFreeFraction: Double = 0.10, criticalFreeFraction: Double = 0.05) {
        self.warningFreeFraction = warningFreeFraction
        self.criticalFreeFraction = criticalFreeFraction
    }

    public func evaluate(_ history: SampleHistory) -> [Anomaly] {
        guard let latest = history.latest else { return [] }
        guard let free = latest.resources.diskFreeFraction else { return [] }
        guard free <= warningFreeFraction else { return [] }

        let severity: Severity = free <= criticalFreeFraction ? .critical : .warning

        return [
            Anomaly(
                id: identifier,
                title: "Only \(Int(free * 100))% of the disk is free",
                detail: """
                    Low free space starves swap and system caches, which makes every other \
                    pressure on the machine worse than it needs to be.
                    """,
                severity: severity,
                evidence: [
                    "free \(ByteFormat.gigabytes(latest.resources.diskFreeBytes))",
                    "total \(ByteFormat.gigabytes(latest.resources.diskTotalBytes))",
                ],
                remedy: Remedy(
                    summary: "Review the largest caches and build artifacts before deleting anything.",
                    command: "du -sh ~/Library/Caches ~/Library/Containers"
                )
            )
        ]
    }
}
