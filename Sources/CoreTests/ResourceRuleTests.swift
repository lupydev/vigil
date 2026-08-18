import Foundation
import VigilCore

enum SwapPressureRuleTests {
    static let rule = SwapPressureRule()

    static var suite: Suite {
        Suite(name: "SwapPressureRule", cases: [
            TestCase(name: "reports nothing when no swap is allocated", run: handlesZeroSwapTotal),
            TestCase(name: "flags near-exhausted swap as critical", run: flagsExhaustedSwap),
            TestCase(name: "flags elevated swap as a warning", run: flagsElevatedSwap),
            TestCase(name: "stays quiet at healthy swap levels", run: ignoresHealthySwap),
        ])
    }

    static func history(swapUsed: UInt64, swapTotal: UInt64) -> SampleHistory {
        SampleHistory(samples: [
            makeSample(at: origin, resources: makeResources(swapUsed: swapUsed, swapTotal: swapTotal))
        ])
    }

    /// A freshly booted Mac reports a swap total of zero. That is the healthiest
    /// state there is — it must not divide by zero and must not read as pressure.
    static func handlesZeroSwapTotal(_ t: Assertions) {
        t.expect(rule.evaluate(history(swapUsed: 0, swapTotal: 0)).isEmpty, "zero swap is health, not pressure")
    }

    /// The state the machine was actually found in: 18.5 GB of 19.4 GB.
    static func flagsExhaustedSwap(_ t: Assertions) {
        let anomalies = rule.evaluate(history(swapUsed: 19_440_000_000, swapTotal: 20_400_000_000))

        t.equal(anomalies.count, 1)
        t.equal(anomalies.first?.severity, .critical)
        t.isNil(anomalies.first?.remedy.command)
    }

    static func flagsElevatedSwap(_ t: Assertions) {
        let anomalies = rule.evaluate(history(swapUsed: 15_000_000_000, swapTotal: 20_000_000_000))

        t.equal(anomalies.count, 1)
        t.equal(anomalies.first?.severity, .warning)
    }

    static func ignoresHealthySwap(_ t: Assertions) {
        t.expect(rule.evaluate(history(swapUsed: 6_000_000_000, swapTotal: 20_000_000_000)).isEmpty)
    }
}

enum DiskPressureRuleTests {
    static let rule = DiskPressureRule()

    static var suite: Suite {
        Suite(name: "DiskPressureRule", cases: [
            TestCase(name: "stays quiet with healthy headroom", run: ignoresHealthyDisk),
            TestCase(name: "warns when headroom gets thin", run: warnsOnLowDisk),
            TestCase(name: "escalates when the disk is nearly full", run: flagsCriticalDisk),
            TestCase(name: "reports nothing when capacity is unknown", run: handlesZeroTotal),
        ])
    }

    static func history(free: UInt64, total: UInt64) -> SampleHistory {
        SampleHistory(samples: [
            makeSample(at: origin, resources: makeResources(diskFree: free, diskTotal: total))
        ])
    }

    /// 38 GB free of 245 GB — tight-ish, but not the problem. Must stay quiet.
    static func ignoresHealthyDisk(_ t: Assertions) {
        t.expect(rule.evaluate(history(free: 38_000_000_000, total: 245_000_000_000)).isEmpty)
    }

    static func warnsOnLowDisk(_ t: Assertions) {
        let anomalies = rule.evaluate(history(free: 18_000_000_000, total: 245_000_000_000))

        t.equal(anomalies.count, 1)
        t.equal(anomalies.first?.severity, .warning)
    }

    static func flagsCriticalDisk(_ t: Assertions) {
        let anomalies = rule.evaluate(history(free: 6_000_000_000, total: 245_000_000_000))

        t.equal(anomalies.count, 1)
        t.equal(anomalies.first?.severity, .critical)
    }

    static func handlesZeroTotal(_ t: Assertions) {
        t.expect(rule.evaluate(history(free: 0, total: 0)).isEmpty)
    }
}
