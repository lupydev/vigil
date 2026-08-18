import AppKit
import VigilCore
import SwiftUI

struct VigilApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(engine: delegate.engine)
        } label: {
            Image(systemName: Self.icon(for: delegate.engine.worstSeverity))
        }
        .menuBarExtraStyle(.window)
    }

    private static func icon(for severity: Severity?) -> String {
        switch severity {
        case .critical: "stethoscope.circle.fill"
        case .warning: "stethoscope.circle"
        case .info, .none: "stethoscope"
        }
    }
}

/// Owns the monitor's lifecycle.
///
/// The engine must not start from the menu's `.task`: `MenuBarExtra` builds its
/// content lazily, the first time the icon is clicked. Monitoring would then
/// only run while the user was watching — the exact failure this app exists to
/// prevent. Launch is the only correct trigger.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let engine = MonitorEngine()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keeps the app out of the Dock and the app switcher.
        NSApp.setActivationPolicy(.accessory)
        engine.start()

        if ProcessInfo.processInfo.environment["VIGIL_DIAGNOSE_UI"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { Self.reportStatusItem() }
        }
    }

    /// Reports whether the menu bar item actually exists.
    ///
    /// A `MenuBarExtra` that never appears is indistinguishable from one hidden
    /// behind the notch or pushed off a crowded menu bar, and guessing between
    /// those wastes far more time than asking the app directly.
    private static func reportStatusItem() {
        let windows = NSApp.windows
        let statusWindows = windows.filter {
            String(describing: type(of: $0)).contains("StatusBar")
        }

        FileHandle.standardError.write(Data("""
            [ui] activationPolicy=\(NSApp.activationPolicy().rawValue)
            [ui] windows=\(windows.count)
            [ui] statusBarWindows=\(statusWindows.count)
            [ui] frames=\(statusWindows.map { NSStringFromRect($0.frame) }.joined(separator: " "))
            [ui] classes=\(windows.map { String(describing: type(of: $0)) }.joined(separator: ","))

            """.utf8))
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
    }
}
