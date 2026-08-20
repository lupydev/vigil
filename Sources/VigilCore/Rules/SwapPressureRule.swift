import Foundation

/// Reports swap that has overflowed onto the SSD, and how much it still hurts.
///
/// Swap fullness alone cannot carry a severity, because it **lags** the
/// condition that produced it. Two different quantities are involved and they
/// behave differently:
///
/// - **used** — pages actually written out. Falls again as processes exit or
///   their pages are read back, so quitting an application reclaims some of it
///   without a restart.
/// - **total** — the size of the swap files macOS allocated. Grows under
///   pressure and is not given back while the system is running.
///
/// Because `total` only ratchets up, the fraction stays high long after memory
/// pressure has passed. Observed on a recovered machine: 84% full with the
/// kernel reporting normal pressure, memory free back to 46%, and not one page
/// swapped out between readings. A rule keyed on fullness alone stays lit for
/// hours against a healthy system, which is how alerts get ignored.
///
/// So fullness is treated as a fact, and severity comes from
/// `kern.memorystatus_vm_pressure_level` — the kernel's own live verdict, which
/// weighs compression ratio, clean page availability and file-backed pressure,
/// none of which is visible from here. One fewer threshold to invent, and a
/// better answer than approximating it from a paging rate.
public struct SwapPressureRule: AnomalyRule {
    public let identifier = "swap-pressure"

    /// How full swap must be before it is worth mentioning at all.
    public let warningFraction: Double

    public init(warningFraction: Double = 0.70) {
        self.warningFraction = warningFraction
    }

    public func evaluate(_ history: SampleHistory) -> [Anomaly] {
        guard let latest = history.latest else { return [] }

        // No swap allocated is the healthiest possible state, not a division
        // waiting to happen.
        guard let fraction = latest.resources.swapUsedFraction else { return [] }
        guard fraction >= warningFraction else { return [] }

        let pressure = latest.resources.memoryPressureLevel
        let used = ByteFormat.gigabytes(latest.resources.swapUsedBytes)
        let total = ByteFormat.gigabytes(latest.resources.swapTotalBytes)

        return [
            Anomaly(
                id: identifier,
                title: title(fraction: fraction, used: used, total: total, pressure: pressure),
                detail: detail(pressure: pressure, used: used),
                severity: severity(for: pressure),
                evidence: [
                    "swap used \(used) of \(total)",
                    "memory free \(Int(latest.resources.memoryFreeFraction * 100))%",
                    "kernel memory pressure: \(describe(pressure))",
                ],
                remedy: Remedy(
                    summary: pressure >= .warning
                        ? "Quit whichever application is holding the most memory — its pages are "
                            + "released as it exits. Logging out clears them all without a restart."
                        : "Nothing is urgent. Quitting a heavy application still reclaims part of "
                            + "the \(used) in use; only the swap files themselves wait for a restart.",
                    command: nil
                )
            )
        ]
    }

    /// Severity is the kernel's judgement, never ours.
    ///
    /// `unknown` means the sysctl was unavailable, which is the absence of
    /// evidence. It never escalates.
    private func severity(for pressure: MemoryPressureLevel) -> Severity {
        switch pressure {
        case .critical: .critical
        case .warning: .warning
        case .normal, .unknown: .info
        }
    }

    private func title(
        fraction: Double,
        used: String,
        total: String,
        pressure: MemoryPressureLevel
    ) -> String {
        let size = "\(Int(fraction * 100))% full (\(used) of \(total))"
        return pressure >= .warning
            ? "Swap is \(size) and the system is under memory pressure"
            : "Swap is \(size), held over from earlier pressure"
    }

    private func detail(pressure: MemoryPressureLevel, used: String) -> String {
        switch pressure {
        case .critical:
            return """
                Memory has overflowed onto the SSD and the kernel reports critical \
                pressure right now. The system is paging against disk, which generates \
                heat and wear even when CPU looks idle, and macOS may begin terminating \
                applications.
                """
        case .warning:
            return """
                Memory has overflowed onto the SSD and the kernel still reports elevated \
                pressure. The system is working against disk rather than RAM, which costs \
                heat and latency even when CPU looks idle.
                """
        case .normal, .unknown:
            return """
                The kernel reports normal memory pressure, so whatever caused this has already \
                passed. The figure stays high because macOS does not shrink the swap files it \
                allocated — but the \(used) in use is not stuck: those pages are released as \
                processes exit or their pages are read back. Worth knowing, not worth \
                interrupting anything for.
                """
        }
    }

    private func describe(_ pressure: MemoryPressureLevel) -> String {
        switch pressure {
        case .critical: "critical"
        case .warning: "warning"
        case .normal: "normal"
        case .unknown: "unavailable"
        }
    }
}

enum ByteFormat {
    static func gigabytes(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
    }
}
