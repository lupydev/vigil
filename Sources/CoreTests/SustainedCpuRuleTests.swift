import Foundation
import VigilCore

enum SustainedCpuRuleTests {
    static let rule = SustainedCpuRule()
    static let thirtyDays: TimeInterval = 30 * 86_400

    static var suite: Suite {
        Suite(name: "SustainedCpuRule (recently stuck)", cases: [
            TestCase(name: "flags a long-lived process that jammed recently", run: flagsRecentlyStuckProcess),
            TestCase(name: "defers to LifetimeCpuRule when it burned since birth", run: defersToLifetimeRule),
            TestCase(name: "ignores a hot but young process", run: ignoresYoungProcess),
            TestCase(name: "ignores a short observation window", run: ignoresShortWindow),
            TestCase(name: "ignores a process that dipped below threshold", run: ignoresBurstyProcess),
            TestCase(name: "does not stitch history across a reused pid", run: ignoresReusedPid),
            TestCase(name: "returns nothing for an empty history", run: handlesEmptyHistory),
        ])
    }

    /// The case the kernel's counters cannot see: thirty days of good behaviour
    /// dilutes the lifetime average to nothing, so only a window reveals it.
    static func flagsRecentlyStuckProcess(_ t: Assertions) {
        let startedAt = origin.addingTimeInterval(-thirtyDays)
        let history = makeHistory(count: 6) { _ in
            [makeProcess(pid: 4242, startedAt: startedAt, cpu: 101, lifetimeCpu: 0.3)]
        }

        let anomalies = rule.evaluate(history)

        t.equal(anomalies.count, 1)
        t.equal(anomalies.first?.severity, .critical)
        t.equal(anomalies.first?.remedy.command, "kill -9 4242")
        t.expect(
            anomalies.first?.evidence.contains(where: { $0.contains("lifetime average") }) == true,
            "evidence should show the lifetime average that made this the other shape"
        )
    }

    /// Two rules reporting one stuck process would be worse than one. The
    /// lifetime ceiling keeps them mutually exclusive by construction.
    static func defersToLifetimeRule(_ t: Assertions) {
        let startedAt = origin.addingTimeInterval(-6 * 86_400)
        let history = makeHistory(count: 6) { _ in
            [makeProcess(pid: 21653, startedAt: startedAt, cpu: 102, lifetimeCpu: 99)]
        }

        t.expect(rule.evaluate(history).isEmpty, "burning since birth belongs to LifetimeCpuRule")
    }

    /// A build at 100% CPU is a build. Without the age axis this rule would cry
    /// wolf on every compile.
    static func ignoresYoungProcess(_ t: Assertions) {
        let history = makeHistory(count: 6, interval: 60) { _ in
            [makeProcess(pid: 900, startedAt: origin.addingTimeInterval(-300), cpu: 340, lifetimeCpu: 60)]
        }

        t.expect(rule.evaluate(history).isEmpty, "a five-minute-old process is not an anomaly")
    }

    static func ignoresShortWindow(_ t: Assertions) {
        let history = makeHistory(count: 3, interval: 60) { _ in
            [makeProcess(pid: 4242, startedAt: origin.addingTimeInterval(-thirtyDays), cpu: 102, lifetimeCpu: 0.3)]
        }

        t.expect(rule.evaluate(history).isEmpty, "two minutes of observation proves nothing")
    }

    /// Bursty work dips. Stuck work does not. One reading below the threshold is
    /// enough to tell them apart.
    static func ignoresBurstyProcess(_ t: Assertions) {
        let startedAt = origin.addingTimeInterval(-thirtyDays)
        let cpuByIndex: [Double] = [102, 98, 12, 105, 99, 101]
        let samples = cpuByIndex.enumerated().map { index, cpu in
            makeSample(
                at: origin.addingTimeInterval(-Double(5 - index) * 300),
                processes: [makeProcess(pid: 4242, startedAt: startedAt, cpu: cpu, lifetimeCpu: 0.3)]
            )
        }

        t.expect(rule.evaluate(SampleHistory(samples: samples)).isEmpty, "a dip means it is working, not stuck")
    }

    /// macOS reuses pids. Matching on pid alone would stitch a dead process's
    /// history onto a live one and invent a sustained load that never happened.
    static func ignoresReusedPid(_ t: Assertions) {
        let oldIncarnation = origin.addingTimeInterval(-60 * 86_400)
        let newIncarnation = origin.addingTimeInterval(-thirtyDays)

        var samples = (0..<5).map { index in
            makeSample(
                at: origin.addingTimeInterval(-Double(5 - index) * 300),
                processes: [makeProcess(pid: 777, startedAt: oldIncarnation, cpu: 99, lifetimeCpu: 0.3)]
            )
        }
        samples.append(
            makeSample(
                at: origin,
                processes: [makeProcess(pid: 777, startedAt: newIncarnation, cpu: 99, lifetimeCpu: 0.3)]
            )
        )

        t.expect(
            rule.evaluate(SampleHistory(samples: samples)).isEmpty,
            "the new incarnation has only one observation of its own"
        )
    }

    static func handlesEmptyHistory(_ t: Assertions) {
        t.expect(rule.evaluate(SampleHistory(samples: [])).isEmpty, "no samples means no findings")
    }
}
