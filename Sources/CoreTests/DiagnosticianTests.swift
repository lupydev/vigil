import Foundation
import VigilCore

enum DiagnosticianTests {
    static var suite: Suite {
        Suite(name: "Diagnostician", cases: [
            TestCase(name: "ranks the most severe finding first", run: ranksBySeverity),
            TestCase(name: "reports a clean machine as clean", run: reportsHealthyMachine),
            TestCase(name: "never reports one stuck process twice", run: neverDoubleReports),
        ])
    }

    /// The exact machine state that started this: a daemon burning since birth
    /// plus swap pressure, with plenty of disk left.
    static func ranksBySeverity(_ t: Assertions) {
        let startedAt = origin.addingTimeInterval(-6 * 86_400)
        let resources = makeResources(
            swapUsed: 15_000_000_000,   // warning
            swapTotal: 20_000_000_000,
            diskFree: 38_000_000_000,   // healthy
            diskTotal: 245_000_000_000
        )
        let history = makeHistory(count: 6, resources: resources) { _ in
            [makeProcess(pid: 21653, startedAt: startedAt, cpu: 102, lifetimeCpu: 99)]
        }

        let anomalies = Diagnostician.standard.diagnose(history)

        t.equal(anomalies.count, 2)
        t.equal(anomalies.first?.severity, .critical)
        t.expect(anomalies.first?.id.hasPrefix("lifetime-cpu") == true, "cpu finding should rank first")
        t.equal(anomalies.last?.severity, .warning)
        t.equal(anomalies.last?.id, "swap-pressure")
    }

    static func reportsHealthyMachine(_ t: Assertions) {
        let history = makeHistory(count: 6) { _ in
            [makeProcess(pid: 500, startedAt: origin.addingTimeInterval(-86_400), cpu: 3, lifetimeCpu: 2)]
        }

        t.expect(Diagnostician.standard.diagnose(history).isEmpty, "a calm machine produces no findings")
    }

    /// Both CPU rules see the same process table. Their thresholds must not
    /// overlap, or every stuck process would be announced twice.
    static func neverDoubleReports(_ t: Assertions) {
        let lifetimes: [Double] = [0.3, 20, 69, 70, 85, 99]

        for lifetime in lifetimes {
            let history = makeHistory(count: 6) { _ in
                [makeProcess(
                    pid: 999,
                    startedAt: origin.addingTimeInterval(-30 * 86_400),
                    cpu: 100,
                    lifetimeCpu: lifetime
                )]
            }

            let cpuFindings = Diagnostician.standard.diagnose(history).filter {
                $0.id.hasPrefix("lifetime-cpu") || $0.id.hasPrefix("recently-stuck")
            }

            t.equal(cpuFindings.count, 1)
        }
    }
}

enum SampleHistoryTests {
    static var suite: Suite {
        Suite(name: "SampleHistory", cases: [
            TestCase(name: "orders samples oldest first", run: sortsSamples),
            TestCase(name: "trims samples outside the window", run: trimsOldSamples),
        ])
    }

    static func sortsSamples(_ t: Assertions) {
        let history = SampleHistory(samples: [
            makeSample(at: origin),
            makeSample(at: origin.addingTimeInterval(-600)),
            makeSample(at: origin.addingTimeInterval(-300)),
        ])

        t.equal(history.oldest?.timestamp, origin.addingTimeInterval(-600))
        t.equal(history.latest?.timestamp, origin)
        t.equal(history.span, 600)
    }

    static func trimsOldSamples(_ t: Assertions) {
        let history = makeHistory(count: 10, interval: 300) { _ in [] }

        t.equal(history.trimmed(to: 900).samples.count, 4)
    }
}

enum InMemorySampleStoreTests {
    static var suite: Suite {
        Suite(name: "InMemorySampleStore", cases: [
            TestCase(name: "never grows past its cap", run: staysBounded),
            TestCase(name: "keeps the newest samples when it overflows", run: keepsNewest),
            TestCase(name: "compacts what it retains", run: compactsRetained),
        ])
    }

    /// Unbounded memory is the same mistake as unbounded disk, one restart away
    /// from being invisible instead of absent.
    static func staysBounded(_ t: Assertions) {
        let store = InMemorySampleStore(maximumSamples: 10)

        for index in 0..<500 {
            try? store.append(makeSample(at: origin.addingTimeInterval(Double(index))))
        }

        t.equal((try? store.history(within: .infinity))?.samples.count, 10)
    }

    static func keepsNewest(_ t: Assertions) {
        let store = InMemorySampleStore(maximumSamples: 3)

        for index in 0..<10 {
            try? store.append(makeSample(at: origin.addingTimeInterval(Double(index))))
        }

        t.equal((try? store.history(within: .infinity))?.latest?.timestamp, origin.addingTimeInterval(9))
    }

    static func compactsRetained(_ t: Assertions) {
        let store = InMemorySampleStore(maximumSamples: 5)
        let quiet = (0..<200).map { index in
            makeProcess(pid: Int32(index), startedAt: origin.addingTimeInterval(-3600), cpu: 1)
        }

        try? store.append(makeSample(at: origin, processes: quiet))

        t.equal((try? store.history(within: .infinity))?.latest?.processes.count, 0)
    }
}
