import Foundation
import VigilCore
import VigilSystem

/// `--scan` runs the same pipeline the menu bar uses and prints the result.
///
/// The rules need consecutive readings before they can judge anything, so a
/// scan takes several samples rather than one. It exists to prove the adapters
/// read the real machine, and to inspect findings without opening the UI.
if CommandLine.arguments.contains("--scan") {
    await Scan.run(
        samples: Scan.intArgument("--samples") ?? 4,
        interval: Scan.doubleArgument("--interval") ?? 3,
        minimumAge: Scan.doubleArgument("--min-age")
    )
} else {
    VigilApp.main()
}

enum Scan {
    /// Rules for a scan, optionally with a shortened age requirement.
    ///
    /// The real thresholds wait two hours before calling anything abandoned,
    /// which makes them impossible to exercise interactively. `--min-age`
    /// shortens that for a single scan so a rule can be validated, or a
    /// threshold tried out, without waiting for the afternoon to pass.
    static func diagnostician(minimumAge: TimeInterval?) -> Diagnostician {
        guard let minimumAge else { return .standard }

        return Diagnostician(rules: [
            LifetimeCpuRule(minimumAge: minimumAge),
            SustainedCpuRule(
                minimumAge: minimumAge,
                minimumSustainedWindow: 0,
                minimumObservations: 2
            ),
            SwapPressureRule(),
            DiskPressureRule(),
        ])
    }

    static func run(samples count: Int, interval: TimeInterval, minimumAge: TimeInterval?) async {
        let processSampler = LibprocProcessSampler()
        let resourceSampler = SysctlResourceSampler()
        let clock = SystemClock()
        var collected: [Sample] = []

        print("Sampling \(count) times, \(Int(interval))s apart...\n")

        for index in 1...count {
            do {
                let sample = Sample(
                    timestamp: clock.now,
                    processes: try processSampler.sampleProcesses(),
                    resources: try resourceSampler.sampleResources()
                )
                collected.append(sample)

                let hottest = sample.processes.max { $0.cpuPercent < $1.cpuPercent }
                let peak = hottest.map { "\($0.name) \(Int($0.cpuPercent))%" } ?? "n/a"
                print("  [\(index)/\(count)] \(sample.processes.count) processes · hottest \(peak)")
            } catch {
                print("  [\(index)/\(count)] sampling failed: \(error)")
            }

            if index < count {
                try? await Task.sleep(for: .seconds(interval))
            }
        }

        guard let latest = collected.last else {
            print("\nNo samples collected.")
            exit(1)
        }

        printResources(latest.resources)
        printFindings(
            diagnostician(minimumAge: minimumAge)
                .diagnose(SampleHistory(samples: collected))
        )
        exit(0)
    }

    private static func printResources(_ resources: ResourceSnapshot) {
        let swap = resources.swapUsedFraction
            .map { "\(Int($0 * 100))% used" } ?? "none allocated"
        let disk = resources.diskFreeFraction
            .map { "\(Int($0 * 100))% free" } ?? "unknown"

        print("""

            RESOURCES
              swap    \(swap)
              memory  \(Int(resources.memoryFreeFraction * 100))% free
              disk    \(disk)
            """)
    }

    private static func printFindings(_ anomalies: [Anomaly]) {
        guard !anomalies.isEmpty else {
            print("\nFINDINGS\n  none — the machine looks healthy\n")
            return
        }

        print("\nFINDINGS")
        for anomaly in anomalies {
            print("\n  [\(label(for: anomaly.severity))] \(anomaly.title)")
            for line in anomaly.evidence {
                print("      · \(line)")
            }
            print("      → \(anomaly.remedy.summary)")
            if let command = anomaly.remedy.command {
                print("        \(command)")
            }
        }
        print("")
    }

    private static func label(for severity: Severity) -> String {
        switch severity {
        case .critical: "CRITICAL"
        case .warning: "WARNING"
        case .info: "INFO"
        }
    }

    static func intArgument(_ name: String) -> Int? {
        value(for: name).flatMap(Int.init)
    }

    static func doubleArgument(_ name: String) -> Double? {
        value(for: name).flatMap(Double.init)
    }

    private static func value(for name: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }
}
