import Foundation
import VigilCore

/// Fixed reference point so tests never depend on the wall clock.
let origin = Date(timeIntervalSince1970: 1_750_000_000)

/// `lifetimeCpu` is the average CPU the process consumed across its whole life,
/// as a percentage. It defaults to a well-behaved 1%, so a test only states it
/// when the lifetime axis is the thing under test.
func makeProcess(
    pid: Int32 = 100,
    startedAt: Date,
    name: String = "java",
    path: String = "/opt/homebrew/Cellar/openjdk@17/bin/java",
    cpu: Double,
    lifetimeCpu: Double = 1,
    at referenceDate: Date = origin,
    memory: UInt64 = 400_000_000
) -> ProcessSnapshot {
    let age = referenceDate.timeIntervalSince(startedAt)
    return ProcessSnapshot(
        identity: ProcessIdentity(pid: pid, startedAt: startedAt),
        name: name,
        executablePath: path,
        cpuPercent: cpu,
        cumulativeCpuSeconds: max(0, age) * (lifetimeCpu / 100),
        memoryBytes: memory
    )
}

func makeResources(
    swapUsed: UInt64 = 0,
    swapTotal: UInt64 = 0,
    memoryFree: Double = 0.6,
    diskFree: UInt64 = 40_000_000_000,
    diskTotal: UInt64 = 245_000_000_000
) -> ResourceSnapshot {
    ResourceSnapshot(
        swapUsedBytes: swapUsed,
        swapTotalBytes: swapTotal,
        memoryFreeFraction: memoryFree,
        diskFreeBytes: diskFree,
        diskTotalBytes: diskTotal
    )
}

func makeSample(
    at timestamp: Date,
    processes: [ProcessSnapshot] = [],
    resources: ResourceSnapshot = makeResources()
) -> Sample {
    Sample(timestamp: timestamp, processes: processes, resources: resources)
}

/// Builds a window of samples spaced `interval` apart, ending at `origin`.
func makeHistory(
    count: Int,
    interval: TimeInterval = 300,
    resources: ResourceSnapshot = makeResources(),
    process: (Date) -> [ProcessSnapshot]
) -> SampleHistory {
    let samples = (0..<count).map { index -> Sample in
        let timestamp = origin.addingTimeInterval(-Double(count - 1 - index) * interval)
        return makeSample(at: timestamp, processes: process(timestamp), resources: resources)
    }
    return SampleHistory(samples: samples)
}
