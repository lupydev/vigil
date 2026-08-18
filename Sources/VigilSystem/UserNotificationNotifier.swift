import Foundation
import VigilCore
import UserNotifications

/// Delivers findings as native notifications.
///
/// `UNUserNotificationCenter` requires a real bundle identifier and traps
/// without one, which is exactly the state of a bare SwiftPM executable. The
/// notifier therefore degrades to silence when unbundled instead of taking the
/// app down, and reports whether it is actually live.
public final class UserNotificationNotifier: Notifier, @unchecked Sendable {
    public let isAvailable: Bool
    private let lock = NSLock()
    private var announced: Set<String> = []

    public init() {
        isAvailable = Bundle.main.bundleIdentifier != nil
    }

    public func requestAuthorization() async {
        guard isAvailable else { return }
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    public func notify(_ anomalies: [Anomaly]) async {
        guard isAvailable else { return }

        let fresh = lock.withLock { () -> [Anomaly] in
            let unseen = anomalies.filter { !announced.contains($0.id) }
            // Anomalies that cleared may legitimately fire again later.
            announced = Set(anomalies.map(\.id))
            return unseen
        }

        for anomaly in fresh where anomaly.severity >= .warning {
            let content = UNMutableNotificationContent()
            content.title = anomaly.title
            content.body = anomaly.remedy.summary
            content.sound = anomaly.severity == .critical ? .default : nil

            let request = UNNotificationRequest(
                identifier: anomaly.id,
                content: content,
                trigger: nil
            )
            try? await UNUserNotificationCenter.current().add(request)
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
