import Darwin
import Foundation
import VigilCore

/// Reads the process table through `libproc`.
///
/// CPU is computed as a delta between consecutive samples rather than read from
/// a platform average. `ps` reports a decaying average over roughly the last
/// minute, which cannot distinguish a process that just got busy from one that
/// has been stuck for days — the exact distinction this app exists to make.
/// Measuring consumed CPU time between two known instants gives an honest
/// percentage over a known interval.
public final class LibprocProcessSampler: ProcessSampler, @unchecked Sendable {
    private struct CpuReading {
        let totalTicks: UInt64
        let takenAt: Date
    }

    /// Mach absolute-time units per nanosecond.
    ///
    /// `proc_taskinfo` documents `pti_total_user` and `pti_total_system` as
    /// nanoseconds, but on Apple Silicon it returns mach absolute-time ticks,
    /// which are 125/3 ns each. Treating ticks as nanoseconds silently
    /// underreports CPU by roughly 42x — enough to make a process pinned at a
    /// full core look like it is idling at 2%.
    private static let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        guard mach_timebase_info(&info) == KERN_SUCCESS, info.denom != 0 else {
            return (1, 1)
        }
        return (UInt64(info.numer), UInt64(info.denom))
    }()

    private static func nanoseconds(fromTicks ticks: UInt64) -> UInt64 {
        ticks / timebase.denom * timebase.numer
            + ticks % timebase.denom * timebase.numer / timebase.denom
    }

    private let lock = NSLock()
    private var previous: [ProcessIdentity: CpuReading] = [:]
    private let clock: any Clock

    public init(clock: any Clock = SystemClock()) {
        self.clock = clock
    }

    public func sampleProcesses() throws -> [ProcessSnapshot] {
        let now = clock.now
        let pids = try Self.listPids()

        lock.lock()
        defer { lock.unlock() }

        var current: [ProcessIdentity: CpuReading] = [:]
        var snapshots: [ProcessSnapshot] = []

        for pid in pids where pid > 0 {
            guard let info = Self.taskAllInfo(for: pid) else { continue }

            let startedAt = Date(timeIntervalSince1970: TimeInterval(info.pbsd.pbi_start_tvsec))
            let identity = ProcessIdentity(pid: pid, startedAt: startedAt)
            let consumed = info.ptinfo.pti_total_user + info.ptinfo.pti_total_system
            let reading = CpuReading(totalTicks: consumed, takenAt: now)
            current[identity] = reading

            snapshots.append(
                ProcessSnapshot(
                    identity: identity,
                    name: Self.string(from: info.pbsd.pbi_name) ?? Self.string(from: info.pbsd.pbi_comm) ?? "pid \(pid)",
                    executablePath: Self.path(for: pid) ?? "",
                    cpuPercent: Self.cpuPercent(previous: previous[identity], current: reading),
                    cumulativeCpuSeconds: Double(Self.nanoseconds(fromTicks: consumed)) / 1_000_000_000,
                    memoryBytes: info.ptinfo.pti_resident_size
                )
            )
        }

        previous = current
        return snapshots
    }

    /// Percentage of one core consumed between the two readings.
    ///
    /// The first sighting of a process has nothing to compare against, so it
    /// reports zero rather than guessing. The rules require several consecutive
    /// readings anyway, so nothing is lost.
    private static func cpuPercent(previous: CpuReading?, current: CpuReading) -> Double {
        guard let previous else { return 0 }

        let elapsed = current.takenAt.timeIntervalSince(previous.takenAt)
        guard elapsed > 0, current.totalTicks >= previous.totalTicks else { return 0 }

        let consumedNanoseconds = nanoseconds(fromTicks: current.totalTicks - previous.totalTicks)
        let consumedSeconds = Double(consumedNanoseconds) / 1_000_000_000
        return (consumedSeconds / elapsed) * 100
    }

    private static func listPids() throws -> [Int32] {
        let byteCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard byteCount > 0 else { throw SamplerError.processListUnavailable }

        let capacity = Int(byteCount) / MemoryLayout<Int32>.size
        var pids = [Int32](repeating: 0, count: capacity)
        let written = proc_listpids(
            UInt32(PROC_ALL_PIDS),
            0,
            &pids,
            Int32(capacity * MemoryLayout<Int32>.size)
        )
        guard written > 0 else { throw SamplerError.processListUnavailable }

        return Array(pids.prefix(Int(written) / MemoryLayout<Int32>.size))
    }

    private static func taskAllInfo(for pid: Int32) -> proc_taskallinfo? {
        var info = proc_taskallinfo()
        let size = Int32(MemoryLayout<proc_taskallinfo>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, $0, size)
        }
        // Processes we lack permission for, and processes that exit mid-scan,
        // are expected. They are skipped, never treated as failures.
        return result == size ? info : nil
    }

    /// `PROC_PIDPATHINFO_MAXSIZE` is `4 * MAXPATHLEN`, but the macro does not
    /// survive the C import, so the value is spelled out.
    private static let maxPathLength = 4 * 1024

    private static func path(for pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: maxPathLength)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func string<T>(from tuple: T) -> String? {
        withUnsafeBytes(of: tuple) { raw in
            guard let base = raw.baseAddress else { return nil }
            let value = String(cString: base.assumingMemoryBound(to: CChar.self))
            return value.isEmpty ? nil : value
        }
    }
}

public enum SamplerError: Error {
    case processListUnavailable
    case resourcesUnavailable
}
