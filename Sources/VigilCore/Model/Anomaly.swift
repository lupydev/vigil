import Foundation

public enum Severity: Int, Comparable, Sendable, CaseIterable {
    case info = 0
    case warning = 1
    case critical = 2

    public static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// What the user could do about an anomaly.
///
/// In advise-only mode the app never runs `command`. It is shown so the user
/// can read it, understand it, and decide. Automation comes later, and only
/// once recorded history justifies the thresholds that would trigger it.
public struct Remedy: Equatable, Sendable {
    public let summary: String
    public let command: String?

    public init(summary: String, command: String? = nil) {
        self.summary = summary
        self.command = command
    }
}

/// Something worth the user's attention, with the evidence that justifies it.
public struct Anomaly: Equatable, Identifiable, Sendable {
    /// Stable across samples so the UI and the notifier can deduplicate.
    public let id: String
    public let title: String
    public let detail: String
    public let severity: Severity
    public let evidence: [String]
    public let remedy: Remedy

    public init(
        id: String,
        title: String,
        detail: String,
        severity: Severity,
        evidence: [String],
        remedy: Remedy
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.severity = severity
        self.evidence = evidence
        self.remedy = remedy
    }
}
