import Foundation
import VigilCore

enum SwapPressureRuleTests {
    static let rule = SwapPressureRule()

    static var suite: Suite {
        Suite(name: "SwapPressureRule", cases: [
            TestCase(name: "reports nothing when no swap is allocated", run: handlesZeroSwapTotal),
            TestCase(name: "stays quiet at healthy swap levels", run: ignoresHealthySwap),
            TestCase(name: "escalates to critical only when the kernel does", run: followsKernelCritical),
            TestCase(name: "warns when the kernel reports elevated pressure", run: followsKernelWarning),
            TestCase(name: "downgrades to info once pressure has passed", run: downgradesStaleSwap),
            TestCase(name: "never escalates on an unavailable pressure reading", run: neverEscalatesOnUnknown),
            TestCase(name: "severity ignores how full swap is", run: severityIndependentOfFullness),
        ])
    }

    static func history(
        swapUsed: UInt64,
        swapTotal: UInt64,
        pressure: MemoryPressureLevel = .normal,
        memoryFree: Double = 0.46
    ) -> SampleHistory {
        SampleHistory(samples: [
            makeSample(
                at: origin,
                resources: makeResources(
                    swapUsed: swapUsed,
                    swapTotal: swapTotal,
                    memoryFree: memoryFree,
                    pressure: pressure
                )
            )
        ])
    }

    /// A freshly booted Mac reports a swap total of zero. That is the healthiest
    /// state there is — it must not divide by zero and must not read as pressure.
    static func handlesZeroSwapTotal(_ t: Assertions) {
        t.expect(rule.evaluate(history(swapUsed: 0, swapTotal: 0)).isEmpty, "zero swap is health, not pressure")
    }

    static func ignoresHealthySwap(_ t: Assertions) {
        t.expect(
            rule.evaluate(history(swapUsed: 6_000_000_000, swapTotal: 20_000_000_000, pressure: .critical)).isEmpty,
            "without swap overflow there is nothing to report, whatever the pressure"
        )
    }

    static func followsKernelCritical(_ t: Assertions) {
        let anomalies = rule.evaluate(
            history(swapUsed: 19_440_000_000, swapTotal: 20_400_000_000, pressure: .critical, memoryFree: 0.05)
        )

        t.equal(anomalies.count, 1)
        t.equal(anomalies.first?.severity, .critical)
        t.isNil(anomalies.first?.remedy.command)
    }

    static func followsKernelWarning(_ t: Assertions) {
        let anomalies = rule.evaluate(
            history(swapUsed: 15_000_000_000, swapTotal: 20_000_000_000, pressure: .warning)
        )

        t.equal(anomalies.count, 1)
        t.equal(anomalies.first?.severity, .warning)
    }

    /// Regression for issue #1.
    ///
    /// macOS never shrinks the swap file while running, so a machine that was
    /// briefly starved keeps reporting a full swap for hours afterwards. The
    /// observed case: swap 84% full, kernel pressure back to normal, memory free
    /// recovered from 18% to 46%, and not one page swapped out between readings.
    /// The old rule kept firing CRITICAL against a healthy machine.
    static func downgradesStaleSwap(_ t: Assertions) {
        let anomalies = rule.evaluate(
            history(swapUsed: 6_000_000_000, swapTotal: 7_168_000_000, pressure: .normal, memoryFree: 0.46)
        )

        t.equal(anomalies.count, 1)
        t.equal(anomalies.first?.severity, .info)
        t.expect(
            anomalies.first?.title.contains("held over from earlier") == true,
            "the title should say the condition is historical"
        )
    }

    /// An unreadable sysctl is the absence of evidence, not evidence of calm —
    /// but it must never manufacture urgency either.
    static func neverEscalatesOnUnknown(_ t: Assertions) {
        let anomalies = rule.evaluate(
            history(swapUsed: 19_440_000_000, swapTotal: 20_400_000_000, pressure: .unknown)
        )

        t.equal(anomalies.count, 1)
        t.equal(anomalies.first?.severity, .info)
    }

    /// The whole point of the fix: how full swap is decides *whether* to speak,
    /// never *how loudly*.
    static func severityIndependentOfFullness(_ t: Assertions) {
        let fractions: [(UInt64, UInt64)] = [
            (14_000_000_000, 20_000_000_000),   // 70%
            (18_000_000_000, 20_000_000_000),   // 90%
            (19_800_000_000, 20_000_000_000),   // 99%
        ]

        for (used, total) in fractions {
            let anomalies = rule.evaluate(history(swapUsed: used, swapTotal: total, pressure: .normal))
            t.equal(anomalies.first?.severity, .info)
        }
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
