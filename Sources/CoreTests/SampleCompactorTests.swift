import Foundation
import VigilCore

enum SampleCompactorTests {
    static var suite: Suite {
        Suite(name: "SampleCompactor", cases: [
            TestCase(name: "drops processes below the floor", run: dropsQuietProcesses),
            TestCase(name: "keeps every process a rule could flag", run: keepsRuleCandidates),
            TestCase(name: "caps how many processes are stored", run: capsStoredProcesses),
            TestCase(name: "always keeps resources", run: keepsResources),
            TestCase(name: "reports no blind spot for the standard rules", run: noBlindSpotByDefault),
            TestCase(name: "reports a blind spot when a rule sits below the floor", run: detectsBlindSpot),
        ])
    }

    static let compactor = SampleCompactor()

    static func sample(cpus: [Double]) -> Sample {
        let processes = cpus.enumerated().map { index, cpu in
            makeProcess(pid: Int32(1000 + index), startedAt: origin.addingTimeInterval(-3600), cpu: cpu)
        }
        return makeSample(at: origin, processes: processes)
    }

    /// 550 processes at 131 KB per sample becomes 1.26 GB over a week. Almost
    /// all of it is processes doing nothing.
    static func dropsQuietProcesses(_ t: Assertions) {
        let compacted = compactor.compact(sample(cpus: [0, 0.4, 3, 12, 49]))

        t.equal(compacted.processes.count, 0)
    }

    /// The floor exists to save space, never to hide evidence. Anything
    /// `SustainedCpuRule` could act on at 80% must survive a 50% floor.
    static func keepsRuleCandidates(_ t: Assertions) {
        let compacted = compactor.compact(sample(cpus: [0, 5, 50, 81, 102, 340]))

        t.equal(compacted.processes.count, 4)
        t.equal(compacted.processes.first?.cpuPercent, 340)
        t.expect(
            compacted.processes.allSatisfy { $0.cpuPercent >= 50 },
            "everything kept should be at or above the floor"
        )
    }

    static func capsStoredProcesses(_ t: Assertions) {
        let busy = Array(repeating: 95.0, count: 40)
        let compacted = SampleCompactor(minimumCpuPercent: 50, maximumProcesses: 20)
            .compact(sample(cpus: busy))

        t.equal(compacted.processes.count, 20)
    }

    /// Resource readings are a handful of numbers, so they are never dropped.
    static func keepsResources(_ t: Assertions) {
        let original = makeSample(
            at: origin,
            processes: [],
            resources: makeResources(swapUsed: 9, swapTotal: 10)
        )

        t.equal(compactor.compact(original).resources, original.resources)
    }

    static func noBlindSpotByDefault(_ t: Assertions) {
        t.expect(
            compactor.blindSpots(against: Diagnostician.standard.rules).isEmpty,
            "the default floor must not blind the default rules"
        )
    }

    /// Lowering a rule below the floor is a silent failure: the rule would never
    /// fire because its evidence was thrown away before storage.
    static func detectsBlindSpot(_ t: Assertions) {
        let rules: [any AnomalyRule] = [SustainedCpuRule(cpuThreshold: 30)]

        t.equal(compactor.blindSpots(against: rules).count, 1)
    }
}
