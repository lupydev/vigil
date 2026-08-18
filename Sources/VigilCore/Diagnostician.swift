import Foundation

/// Runs the rule set over a history window and ranks what it finds.
///
/// This type is the whole application in advise-only mode: it observes,
/// explains, and stops. It holds no ability to act, by construction rather than
/// by discipline — there is no port here that can change the machine.
public struct Diagnostician: Sendable {
    public let rules: [any AnomalyRule]

    public init(rules: [any AnomalyRule]) {
        self.rules = rules
    }

    public static var standard: Diagnostician {
        Diagnostician(rules: [
            LifetimeCpuRule(),
            SustainedCpuRule(),
            SwapPressureRule(),
            DiskPressureRule(),
        ])
    }

    /// Most severe first; ties keep rule order so output stays stable between runs.
    public func diagnose(_ history: SampleHistory) -> [Anomaly] {
        rules
            .flatMap { $0.evaluate(history) }
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.severity != rhs.element.severity {
                    return lhs.element.severity > rhs.element.severity
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
