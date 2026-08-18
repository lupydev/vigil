import Foundation
import VigilCore

enum LifetimeCpuRuleTests {
    static let rule = LifetimeCpuRule()
    static let sixDays: TimeInterval = 6 * 86_400 + 4 * 3_600

    static var suite: Suite {
        Suite(name: "LifetimeCpuRule", cases: [
            TestCase(name: "flags a process burning since birth from ONE sample", run: flagsFromSingleSample),
            TestCase(name: "ignores a busy process with a calm lifetime", run: ignoresRecentlyBusyProcess),
            TestCase(name: "ignores a heavy past that is now quiet", run: ignoresFinishedWork),
            TestCase(name: "ignores a young process", run: ignoresYoungProcess),
            TestCase(name: "ignores the busiest process on a healthy machine", run: ignoresHealthyMachinePeak),
        ])
    }

    static func history(_ process: ProcessSnapshot) -> SampleHistory {
        SampleHistory(samples: [makeSample(at: origin, processes: [process])])
    }

    /// The whole point: no window, no warm-up, no storage. One reading of the
    /// kernel's counters is enough to identify six days of abandoned work.
    static func flagsFromSingleSample(_ t: Assertions) {
        let process = makeProcess(
            pid: 21653,
            startedAt: origin.addingTimeInterval(-sixDays),
            cpu: 102,
            lifetimeCpu: 99
        )

        let anomalies = rule.evaluate(history(process))

        t.equal(anomalies.count, 1)
        t.equal(anomalies.first?.severity, .critical)
        t.equal(anomalies.first?.remedy.command, "kill -9 21653")
        t.expect(anomalies.first?.title.contains("6d") == true, "title should state the age")
    }

    /// A thirty-day process that jammed two hours ago has a diluted lifetime
    /// average. This rule must leave it alone — `SustainedCpuRule` owns that case,
    /// and reporting it twice would be worse than not reporting it at all.
    static func ignoresRecentlyBusyProcess(_ t: Assertions) {
        let process = makeProcess(
            startedAt: origin.addingTimeInterval(-30 * 86_400),
            cpu: 100,
            lifetimeCpu: 0.3
        )

        t.expect(rule.evaluate(history(process)).isEmpty, "a diluted lifetime belongs to the other rule")
    }

    /// A process can carry a heavy history and be perfectly idle now. Killing it
    /// would destroy finished work for no reason.
    static func ignoresFinishedWork(_ t: Assertions) {
        let process = makeProcess(
            startedAt: origin.addingTimeInterval(-sixDays),
            cpu: 0.4,
            lifetimeCpu: 95
        )

        t.expect(rule.evaluate(history(process)).isEmpty, "not hot now means not stuck now")
    }

    static func ignoresYoungProcess(_ t: Assertions) {
        let process = makeProcess(
            startedAt: origin.addingTimeInterval(-600),
            cpu: 340,
            lifetimeCpu: 99
        )

        t.expect(rule.evaluate(history(process)).isEmpty, "a ten-minute build is a build")
    }

    /// Measured on a real healthy machine, WindowServer topped the list at 35.8%
    /// lifetime. The threshold has to sit clear above that.
    static func ignoresHealthyMachinePeak(_ t: Assertions) {
        let process = makeProcess(
            startedAt: origin.addingTimeInterval(-4150),
            name: "WindowServer",
            cpu: 36,
            lifetimeCpu: 35.8
        )

        t.expect(rule.evaluate(history(process)).isEmpty, "the busiest healthy process must stay quiet")
    }
}
